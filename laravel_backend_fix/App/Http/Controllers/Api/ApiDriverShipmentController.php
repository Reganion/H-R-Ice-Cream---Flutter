<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Enums\OrderStatusDriver;
use App\Models\AdminNotification;
use App\Models\CustomerNotification;
use App\Models\Driver;
use App\Models\DriverNotification;
use App\Models\Order;
use App\Models\OrderMessage;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use App\Http\Controllers\Concerns\NormalizesDriverShipmentsTab;
use App\Services\DeliveryService;
use App\Services\FirebaseRealtimeService;

class ApiDriverShipmentController extends Controller
{
    use NormalizesDriverShipmentsTab;

    /** Order status when driver has started delivery (out for delivery). */
    private const STATUS_OUT_FOR_DELIVERY = 'out for delivery';

    /**
     * Send customer notification for shipment/order status changes.
     */
    private function notifyCustomerOrderStatus(Order $order): void
    {
        if (!$order->customer_id) {
            return;
        }

        $status = strtolower(trim((string) ($order->status ?? '')));
        $status = str_replace('-', '_', preg_replace('/\s+/', '_', $status));

        $message = match ($status) {
            'out_for_delivery' => 'Your order is out for delivery.',
            'completed', 'delivered' => 'Order successfully delivered.',
            default => null,
        };

        if ($message === null) {
            return;
        }

        CustomerNotification::create([
            'customer_id'  => (int) $order->customer_id,
            'type'         => CustomerNotification::TYPE_ORDER_STATUS,
            'title'        => $order->product_name ?? 'Order Update',
            'message'      => $message,
            'image_url'    => $order->product_image ?? 'img/default-product.png',
            'related_type' => 'Order',
            'related_id'   => $order->id,
            'data'         => [
                'transaction_id' => $order->transaction_id,
                'status' => $status,
            ],
        ]);
    }

    /**
     * Build full URL for delivery proof image so the app can load it.
     * Uses request host (so device can load the image), normalizes path, fallback to asset() if no host.
     */
    private function deliveryProofUrl(Request $request, ?string $path): ?string
    {
        if ($path === null || trim($path) === '') {
            return null;
        }
        // Normalize: DB may store "delivery-proofs/abc.jpg" or with backslashes on Windows
        $path = str_replace('\\', '/', trim($path));
        $path = 'storage/' . ltrim($path, '/');
        $base = $request->getSchemeAndHttpHost();
        if ($base !== '') {
            return rtrim($base, '/') . '/' . ltrim($path, '/');
        }
        return asset($path);
    }

    // please make it a habit to do dependency injection for services 
    protected $deliveryService;

    public function __construct(
        DeliveryService $deliveryService,
        protected FirebaseRealtimeService $firebase
    ) {
        $this->deliveryService = $deliveryService;
    }
    // please make it a habit to do dependency injection for services 


    /**
     * Driver shipments list by tab.
     * GET /api/v1/driver/shipments?tab=incoming|accepted|completed&search=...
     */
    public function index(Request $request): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $tab = $this->normalizeDriverShipmentsTab($request);

        $statuses = $this->statusesForTab($tab);

        $query = Order::query()
            ->where('driver_id', $driver->id)
            ->whereRaw(
                'LOWER(status) IN (' . implode(',', array_fill(0, count($statuses), '?')) . ')',
                $statuses
            )
            ->orderByRaw('COALESCE(delivery_date, created_at) DESC')
            ->orderBy('id', 'desc');

        if ($tab === 'incoming') {
            $query->where('status_driver', OrderStatusDriver::Pending);
        } elseif ($tab === 'accepted') {
            $query->where('status_driver', OrderStatusDriver::Accepted);
        } else {
            $query->where('status_driver', OrderStatusDriver::Completed);
        }

        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $query->where(function ($q) use ($search): void {
                $q->where('transaction_id', 'like', '%' . $search . '%')
                    ->orWhere('product_name', 'like', '%' . $search . '%')
                    ->orWhere('delivery_address', 'like', '%' . $search . '%')
                    ->orWhere('customer_name', 'like', '%' . $search . '%');
            });
        }

        $shipments = $query->get()->map(function (Order $order) use ($tab, $request) {
            $deliveryDate = $order->delivery_date ? Carbon::parse($order->delivery_date) : null;
            $deliveryTime = $order->delivery_time ? Carbon::parse($order->delivery_time) : null;
            $schedule = $this->formatSchedule($deliveryDate, $deliveryTime);
            $proofUrl = $this->deliveryProofUrl($request, $order->delivery_proof_image);
            $deliveredTime = $order->delivered_at ? Carbon::parse($order->delivered_at)->format('h:i A') : null;
            $deliveredDate = $order->delivery_date ? Carbon::parse($order->delivery_date)->format('d F Y') : null;
            $deliveredTimeCompact = $order->delivered_at ? strtoupper(Carbon::parse($order->delivered_at)->format('h:ia')) : null;
            $downpayment = (float) ($order->downpayment ?? 0.0);
            $amount = (float) ($order->amount ?? 0.0);
            $balance = (float) ($order->balance ?? max(0, $amount - $downpayment));

            return [
                'id' => $order->id,
                'transaction_id' => (string) ($order->transaction_id ?? ''),
                'transaction_label' => '#' . (string) ($order->transaction_id ?? ''),
                'product_name' => (string) ($order->product_name ?? '—'),
                'amount' => $amount,
                'amount_text' => 'PHP ' . number_format($amount, 2),
                'downpayment' => $downpayment,
                'balance' => $balance,
                'expected_on' => $schedule,
                'location' => (string) ($order->delivery_address ?? '—'),
                'status' => strtolower((string) ($order->status ?? '')),
                'status_driver' => strtolower($order->status_driver?->value ?? ''),
                'received_amount' => $order->received_amount !== null ? (float) $order->received_amount : null,
                'delivery_payment_method' => (string) ($order->delivery_payment_method ?? ''),
                'delivery_proof_url' => $proofUrl,
                'delivery_proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'proof_image_url' => $proofUrl,
                'proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'expected_time' => $deliveryTime ? $deliveryTime->format('h:i A') : null,
                'time' => $deliveryTime ? $deliveryTime->format('h:i A') : null,
                'delivery_time_compact' => $this->formatTimeCompact($order->delivery_time),
                'delivered_time' => $deliveredTime,
                'delivered_time_compact' => $deliveredTimeCompact,
                'delivered_date' => $deliveredDate,
                'badge' => $this->badgeForTab($tab),
                'badge_color' => $this->badgeColorForTab($tab),
                'customer_name' => (string) ($order->customer_name ?? ''),
                'customer_phone' => (string) ($order->customer_phone ?? ''),
                'delivery_date' => $deliveryDate ? $deliveryDate->format('Y-m-d') : null,
                'delivery_time' => $deliveryTime ? $deliveryTime->format('H:i') : null,
            ];
        })->values();

        return response()->json([
            'success' => true,
            'tab' => $tab,
            'count' => $shipments->count(),
            'shipments' => $shipments,
        ]);
    }

    /**
     * Driver shipment details.
     * GET /api/v1/driver/shipments/{id}
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $order = Order::query()
            ->where('driver_id', $driver->id)
            ->whereKey($id)
            ->first();

        if (!$order) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment not found.',
            ], 404);
        }

        $deliveryDate = $order->delivery_date ? Carbon::parse($order->delivery_date) : null;
        $deliveryTime = $order->delivery_time ? Carbon::parse($order->delivery_time) : null;
        $proofUrl = $this->deliveryProofUrl($request, $order->delivery_proof_image);
        $deliveredTime = $order->delivered_at ? Carbon::parse($order->delivered_at)->format('h:i A') : null;
        $deliveredDate = $order->delivery_date ? Carbon::parse($order->delivery_date)->format('d F Y') : null;
        $deliveredTimeCompact = $order->delivered_at ? strtoupper(Carbon::parse($order->delivered_at)->format('h:ia')) : null;
        $downpayment = (float) ($order->downpayment ?? 0.0);
        $amount = (float) ($order->amount ?? 0.0);
        $balance = (float) ($order->balance ?? max(0, $amount - $downpayment));

        return response()->json([
            'success' => true,
            'shipment' => [
                'id' => $order->id,
                'transaction_id' => (string) ($order->transaction_id ?? ''),
                'transaction_label' => '#' . (string) ($order->transaction_id ?? ''),
                'expected_on' => $this->formatSchedule($deliveryDate, $deliveryTime),
                'customer_name' => (string) ($order->customer_name ?? ''),
                'customer_phone' => (string) ($order->customer_phone ?? ''),
                'delivery_address' => (string) ($order->delivery_address ?? '—'),
                'quantity' => (int) ($order->qty ?? 1),
                'size' => (string) ($order->gallon_size ?? ''),
                'order_name' => (string) ($order->product_name ?? ''),
                'order_type' => (string) ($order->product_type ?? ''),
                'cost' => $amount,
                'cost_text' => 'PHP ' . number_format($amount, 2),
                'downpayment' => $downpayment,
                'balance' => $balance,
                'status' => strtolower((string) ($order->status ?? '')),
                'status_driver' => strtolower($order->status_driver?->value ?? ''),
                'received_amount' => $order->received_amount !== null ? (float) $order->received_amount : null,
                'delivery_payment_method' => (string) ($order->delivery_payment_method ?? ''),
                'delivery_proof_url' => $proofUrl,
                'delivery_proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'proof_image_url' => $proofUrl,
                'proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'expected_time' => $deliveryTime ? $deliveryTime->format('h:i A') : null,
                'time' => $deliveryTime ? $deliveryTime->format('h:i A') : null,
                'delivery_time_compact' => $this->formatTimeCompact($order->delivery_time),
                'delivered_time' => $deliveredTime,
                'delivered_time_compact' => $deliveredTimeCompact,
                'delivered_date' => $deliveredDate,
            ],
        ]);
    }

    /**
     * Driver accepts a shipment.
     * Keep order status as assigned; set status_driver=Accepted.
     */
    public function accept(Request $request, string $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $order = Order::query()
            ->where('driver_id', $driver->id)
            ->whereKey($id)
            ->first();

        if (!$order) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment not found.',
            ], 404);
        }

        if (strtolower((string) ($order->status ?? '')) !== 'assigned') {
            return response()->json([
                'success' => false,
                'message' => 'Only assigned shipments can be accepted.',
            ], 422);
        }

        if ($order->status_driver !== OrderStatusDriver::Pending) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment was already accepted.',
            ], 422);
        }

        $order->status_driver = OrderStatusDriver::Accepted;
        $order->save();

        AdminNotification::createForAllAdmins(
            AdminNotification::TYPE_ORDER_DRIVER_ACCEPTED,
            $order->customer_name ?? 'Customer',
            null,
            $order->product_image ?? 'img/default-product.png',
            'Order',
            $order->id,
            [
                'subtitle' => 'Driver accepted Order #' . ($order->transaction_id ?? ''),
                'highlight' => $order->product_name ?? '',
            ]
        );

        $this->firebase->touchOrdersUpdated();

        // Reactivate order_messages for this order so the driver–customer thread is visible again
        OrderMessage::query()
            ->where('order_id', $order->id)
            ->update(['status' => OrderMessage::STATUS_ACTIVE]);

        return response()->json([
            'success' => true,
            'message' => 'Shipment accepted.',
        ]);
    }

    /**
     * Driver rejects shipment.
     * Set order back to pending and unassign driver.
     */
    public function reject(Request $request, string $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $order = Order::query()
            ->where('driver_id', $driver->id)
            ->whereKey($id)
            ->first();

        if (!$order) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment not found.',
            ], 404);
        }

        $order->update([
            'status' => 'pending',
            'driver_id' => null,
            'status_driver' => OrderStatusDriver::Pending,
        ]);

        $this->firebase->touchOrdersUpdated();

        return response()->json([
            'success' => true,
            'message' => 'Shipment rejected and moved back to pending.',
        ]);
    }

    /**
     * Driver starts the route for an accepted shipment.
     * Sets order status to "out for delivery"; status_driver remains Accepted.
     */
    public function deliver(Request $request, string $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $order = Order::query()
            ->where('driver_id', $driver->id)
            ->whereKey($id)
            ->first();

        if (!$order) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment not found.',
            ], 404);
        }

        $orderStatus = strtolower(trim((string) ($order->status ?? '')));
        $allowedForDeliver = ['assigned', 'preparing', 'ready'];
        if (!in_array($orderStatus, $allowedForDeliver, true)) {
            return response()->json([
                'success' => false,
                'message' => 'Only assigned, preparing, or ready shipments can be started for delivery.',
            ], 422);
        }

        $currentDriverStatus = $order->status_driver;
        if ($currentDriverStatus !== OrderStatusDriver::Accepted) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment must be accepted before starting delivery.',
            ], 422);
        }

        $driver->status = Driver::STATUS_ON_ROUTE;
        $driver->save();

        $order->status = self::STATUS_OUT_FOR_DELIVERY;
        $order->status_driver = OrderStatusDriver::Accepted;
        $order->save();
        $this->notifyCustomerOrderStatus($order);

        AdminNotification::createForAllAdmins(
            AdminNotification::TYPE_ORDER_OUT_FOR_DELIVERY,
            $order->customer_name ?? 'Customer',
            null,
            $order->product_image ?? 'img/default-product.png',
            'Order',
            $order->id,
            [
                'subtitle' => 'Driver is out for delivery for Order #' . ($order->transaction_id ?? ''),
                'highlight' => $order->product_name ?? '',
            ]
        );

        $this->firebase->touchOrdersUpdated();

        $coords = $this->deliveryService->geocodeAddress($order->delivery_address);

        return response()->json([
            'success' => true,
            'message' => 'Driver is now on route.',
            'destrination' => $coords
        ]);
    }

    /**
     * Driver completes delivery after collecting amount and proof image.
     * Set order status to completed and status_driver=completed.
     */
    public function complete(Request $request, string $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $order = Order::query()
            ->where('driver_id', $driver->id)
            ->whereKey($id)
            ->first();

        if (!$order) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment not found.',
            ], 404);
        }

        $orderStatus = strtolower(trim((string) ($order->status ?? '')));
        $allowedForComplete = ['assigned', 'preparing', 'ready', 'out for delivery', 'out_of_delivery'];
        if (!in_array($orderStatus, $allowedForComplete, true)) {
            return response()->json([
                'success' => false,
                'message' => 'Only assigned or out-for-delivery shipments can be submitted.',
            ], 422);
        }

        $driverShipmentStatus = $order->status_driver;
        if ($driverShipmentStatus !== OrderStatusDriver::Accepted) {
            return response()->json([
                'success' => false,
                'message' => 'Shipment must be accepted before completion.',
            ], 422);
        }

        $validated = $request->validate([
            'received_amount' => ['required', 'numeric', 'min:0'],
            'payment_method' => ['nullable', 'string', 'max:50'],
            'proof_photo' => ['required', 'image', 'max:5120'],
        ]);

        $proofPath = $request->file('proof_photo')->store('delivery-proofs', 'public');

        $newReceived = (float) $validated['received_amount'];
        $order->received_amount = $newReceived;
        $order->status = 'completed';
        $order->status_driver = OrderStatusDriver::Completed;
        $order->delivery_payment_method = (string) ($validated['payment_method'] ?? '');
        $order->delivery_proof_image = $proofPath;
        $order->delivered_at = now();
        $amount = (float) ($order->amount ?? 0.0);
        $order->balance = max(0, $amount - $newReceived);
        $order->save();
        $this->notifyCustomerOrderStatus($order);

        AdminNotification::createForAllAdmins(
            AdminNotification::TYPE_DELIVERY_SUCCESS,
            $order->customer_name ?? 'Customer',
            null,
            $order->product_image ?? 'img/default-product.png',
            'Order',
            $order->id,
            [
                'subtitle' => 'Order #' . ($order->transaction_id ?? ''),
                'highlight' => 'Delivered successfully',
            ]
        );

        DriverNotification::create([
            'driver_id' => (int) $driver->id,
            'type' => DriverNotification::TYPE_SHIPMENT_COMPLETED,
            'title' => 'Delivered Successfully',
            'message' => 'Booking has been delivered completely.',
            'image_url' => $order->product_image ?? 'img/default-product.png',
            'related_type' => 'Order',
            'related_id' => $order->id,
            'data' => [
                'transaction_id' => $order->transaction_id,
                'status' => 'completed',
            ],
        ]);

        $this->firebase->touchOrdersUpdated();

        // Archive this order's messages for the customer unless they have another accepted order
        $customerId = $order->customer_id;
        $hasOtherAcceptedOrder = $customerId !== null
            && Order::query()
                ->where('customer_id', $customerId)
                ->where('id', '!=', $order->id)
                ->where('status_driver', OrderStatusDriver::Accepted)
                ->exists();
        if (!$hasOtherAcceptedOrder) {
            OrderMessage::query()
                ->where('order_id', $order->id)
                ->update(['status' => OrderMessage::STATUS_ARCHIVE]);
        }

        // Set driver back to available after submit, except if they still have an order "Out for delivery"
        $hasOutForDelivery = Order::query()
            ->where('driver_id', $driver->id)
            ->whereRaw('LOWER(TRIM(COALESCE(status, ""))) IN (?, ?)', ['out for delivery', 'out_of_delivery'])
            ->exists();

        if (!$hasOutForDelivery) {
            $driver->status = Driver::STATUS_AVAILABLE;
            $driver->save();
        }

        $proofUrl = $this->deliveryProofUrl($request, $order->delivery_proof_image);
        return response()->json([
            'success' => true,
            'message' => 'Shipment marked completed.',
            'shipment' => [
                'id' => $order->id,
                'status' => strtolower((string) $order->status),
                'status_driver' => strtolower($order->status_driver?->value ?? ''),
                'received_amount' => (float) $order->received_amount,
                'balance' => (float) ($order->balance ?? 0.0),
                'delivery_payment_method' => (string) ($order->delivery_payment_method ?? ''),
                'delivery_proof_url' => $proofUrl,
                'delivery_proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'proof_image_url' => $proofUrl,
                'proof_image' => (string) ($order->delivery_proof_image ?? ''),
                'delivery_time_compact' => $this->formatTimeCompact($order->delivery_time),
                'delivered_time' => Carbon::parse($order->delivered_at)->format('h:i A'),
                'delivered_time_compact' => strtoupper(Carbon::parse($order->delivered_at)->format('h:ia')),
                'delivered_date' => $order->delivery_date ? Carbon::parse($order->delivery_date)->format('d F Y') : null,
            ],
        ]);
    }

    /**
     * Order statuses per tab. Accepted tab shows all orders the driver has accepted
     * (status_driver = Accepted) regardless of admin-set order status
     * (Assigned, Preparing, Ready, Out for Delivery).
     */
    private function statusesForTab(string $tab): array
    {
        return match ($tab) {
            'accepted' => [
                'assigned',
                'preparing',
                'ready',
                'out for delivery',
                'out_of_delivery',
            ],
            'completed' => ['completed'],
            default => ['assigned'],
        };
    }

    private function formatSchedule(?Carbon $deliveryDate, ?Carbon $deliveryTime): string
    {
        if (!$deliveryDate && !$deliveryTime) {
            return '—';
        }

        $datePart = $deliveryDate ? $deliveryDate->format('d M') : null;
        $timePart = $deliveryTime ? $deliveryTime->format('h:i A') : null;

        if ($datePart && $timePart) {
            return $datePart . ', ' . $timePart;
        }

        return (string) ($datePart ?? $timePart ?? '—');
    }

    private function badgeForTab(string $tab): string
    {
        return match ($tab) {
            'accepted' => 'Pending',
            'completed' => 'Completed',
            default => 'New',
        };
    }

    private function badgeColorForTab(string $tab): string
    {
        return match ($tab) {
            'accepted' => '#FF6805',
            'completed' => '#00AE2A',
            default => '#007CFF',
        };
    }

    private function formatTimeCompact(?string $time): ?string
    {
        $value = trim((string) ($time ?? ''));
        if ($value === '') {
            return null;
        }

        try {
            return strtoupper(Carbon::parse($value)->format('h:ia'));
        } catch (\Throwable) {
            return $value;
        }
    }
}
