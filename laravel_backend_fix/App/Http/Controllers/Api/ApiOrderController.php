<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdminNotification;
use App\Models\CustomerNotification;
use App\Models\OrderMessage;
use App\Services\FirebaseRealtimeService;
use App\Services\FirestoreService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Str;

class ApiOrderController extends Controller
{
    public function __construct(
        protected FirebaseRealtimeService $firebase,
        protected FirestoreService $firestore,
    ) {}

    /** Status filter values for order history tabs: all, completed, processing, cancelled */
    private const STATUS_FILTER_ALL = 'all';

    private const STATUS_COMPLETED = ['completed', 'delivered', 'walk-in', 'walk_in', 'walk in', 'walkin'];

    /** Processing: pending, preparing, assigned, ready, out of delivery (and variants). */
    private const STATUS_PROCESSING = [
        'pending',
        'preparing',
        'assigned',
        'ready',
        'out of delivery',
        'out for delivery',
        'out_of_delivery',
    ];

    private const STATUS_CANCELLED = ['cancelled', 'canceled'];

    /** Only orders with this status can be rated (feedback). */
    private const STATUS_RATEABLE = ['completed'];

    /** Only these processing statuses allow cancellation (not ready / out of delivery). */
    private const STATUS_CANCELLABLE = ['pending', 'preparing', 'assigned'];

    /**
     * Firebase Realtime paths use int customerId; derive a stable int from Firestore string ids.
     */
    private function firebaseNumericCustomerId(string $customerId): int
    {
        $customerId = trim($customerId);
        if ($customerId !== '' && ctype_digit($customerId)) {
            return (int) $customerId;
        }

        return (int) (sprintf('%u', crc32($customerId)) % 2147483647);
    }

    /**
     * List orders for the authenticated customer (Firestore `orders`).
     * Query: ?status=all|completed|processing|cancelled (default: all).
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $this->isCustomerUser($user)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $customerId = (string) $user->id;
        $orders = $this->ordersForCustomer($customerId);

        $statusFilter = strtolower((string) $request->query('status', self::STATUS_FILTER_ALL));
        if ($statusFilter === 'completed') {
            $orders = $orders->filter(fn (array $o) => $this->statusMatches($o, self::STATUS_COMPLETED));
        } elseif ($statusFilter === 'processing') {
            $orders = $orders->filter(fn (array $o) => $this->statusMatches($o, self::STATUS_PROCESSING));
        } elseif ($statusFilter === 'cancelled') {
            $orders = $orders->filter(fn (array $o) => $this->statusMatches($o, self::STATUS_CANCELLED));
        }

        $orders = $orders->sortByDesc(fn (array $o) => (string) ($o['created_at'] ?? ''))->values();

        $forDriverChats = (bool) $request->query('for_driver_chats');
        $allMessages = collect($this->firestore->where('order_messages', 'customer_id', $customerId));

        if ($forDriverChats) {
            $orders = $orders->filter(function (array $order) use ($allMessages) {
                if (empty($order['driver_id'])) {
                    return false;
                }
                $oid = (string) ($order['id'] ?? '');
                $msgs = $allMessages->filter(fn (array $m) => (string) ($m['order_id'] ?? '') === $oid);
                if ($msgs->isEmpty()) {
                    return true;
                }

                return $msgs->contains(function (array $m) {
                    return strtolower((string) ($m['customer_status'] ?? OrderMessage::CUSTOMER_STATUS_ACTIVE))
                        === OrderMessage::CUSTOMER_STATUS_ACTIVE;
                });
            })->values();
        }

        $latestMessageByOrder = [];
        if ($forDriverChats && $orders->isNotEmpty()) {
            $activeMsgs = $allMessages
                ->filter(fn (array $m) => strtolower((string) ($m['customer_status'] ?? OrderMessage::CUSTOMER_STATUS_ACTIVE))
                    === OrderMessage::CUSTOMER_STATUS_ACTIVE)
                ->sortByDesc(fn (array $m) => (string) ($m['created_at'] ?? ''));
            foreach ($activeMsgs as $msg) {
                $oid = (string) ($msg['order_id'] ?? '');
                if ($oid !== '' && ! isset($latestMessageByOrder[$oid])) {
                    $latestMessageByOrder[$oid] = $msg;
                }
            }
        }

        $data = $orders->map(function (array $order) use ($latestMessageByOrder) {
            $oid = (string) ($order['id'] ?? '');

            return $this->formatOrderForApi($order, $latestMessageByOrder[$oid] ?? null);
        });

        return response()->json(['success' => true, 'data' => $data]);
    }

    /**
     * @param  array<string, mixed>|null  $latestOrderMessage  Firestore `order_messages` row
     */
    private function formatOrderForApi(array $order, ?array $latestOrderMessage = null): array
    {
        $downpayment = (float) ($order['downpayment'] ?? 0.0);
        $imagePath = $order['product_image'] ?? 'img/default-product.png';
        $imageUrl = str_starts_with((string) $imagePath, 'http') ? $imagePath : url($imagePath);
        $amount = (float) ($order['amount'] ?? 0);
        $balance = (float) ($order['balance'] ?? max(0, $amount - $downpayment));
        $amountFormatted = '₱'.number_format($amount, 0);

        $driver = null;
        if (! empty($order['driver_id'])) {
            $driver = $this->firestore->get('drivers', (string) $order['driver_id']);
        }
        $driverName = $this->firstNonEmptyString([$driver['name'] ?? null, 'Driver']);
        $driverPhone = $this->firstNonEmptyString([$driver['phone'] ?? null, '']);
        $driverCode = $this->firstNonEmptyString([$driver['driver_code'] ?? null, '']);

        $customerRow = null;
        if (! empty($order['customer_id'])) {
            $customerRow = $this->firestore->get('customers', (string) $order['customer_id']);
        }
        $customerPhone = $this->firstNonEmptyString([
            $order['customer_phone'] ?? null,
            $customerRow['contact_no'] ?? null,
        ]);

        $deliveryDate = null;
        if (! empty($order['delivery_date'])) {
            try {
                $deliveryDate = Carbon::parse((string) $order['delivery_date'])->format('Y-m-d');
            } catch (\Throwable) {
                $deliveryDate = null;
            }
        }

        $createdAt = null;
        if (! empty($order['created_at'])) {
            try {
                $createdAt = Carbon::parse((string) $order['created_at']);
            } catch (\Throwable) {
                $createdAt = null;
            }
        }

        $payload = [
            'id' => $order['id'] ?? null,
            'customer_id' => $order['customer_id'] ?? null,
            'customer_phone' => $customerPhone !== '' ? $customerPhone : null,
            'driver_id' => ! empty($order['driver_id']) ? (string) $order['driver_id'] : null,
            'driver_name' => $driverName,
            'assigned_driver_name' => $driverName,
            'driver_phone' => $driverPhone,
            'driver_code' => $driverCode,
            'driver' => $driver ? [
                'id' => (string) ($driver['id'] ?? ''),
                'name' => $driverName,
                'phone' => $driverPhone,
                'driver_code' => $driverCode,
            ] : null,
            'transaction_id' => $order['transaction_id'] ?? null,
            'product_name' => $order['product_name'] ?? null,
            'product_type' => $order['product_type'] ?? null,
            'gallon_size' => $order['gallon_size'] ?? null,
            'product_image' => $order['product_image'] ?? null,
            'product_image_url' => $imageUrl,
            'delivery_date' => $deliveryDate,
            'delivery_time' => $order['delivery_time'] ?? null,
            'delivery_address' => $order['delivery_address'] ?? null,
            'amount' => $amount,
            'amount_formatted' => $amountFormatted,
            'downpayment' => $downpayment,
            'balance' => $balance,
            'quantity' => (int) ($order['qty'] ?? 1),
            'payment_method' => $order['payment_method'] ?? null,
            'status' => $order['status'] ?? null,
            'reason' => $order['reason'] ?? null,
            'created_at' => $createdAt?->toIso8601String(),
            'created_at_formatted' => $createdAt?->format('M d, Y h:i A'),
        ];

        if ($latestOrderMessage !== null) {
            $msgCreated = null;
            if (! empty($latestOrderMessage['created_at'])) {
                try {
                    $msgCreated = Carbon::parse((string) $latestOrderMessage['created_at']);
                } catch (\Throwable) {
                    $msgCreated = null;
                }
            }
            $payload['latest_message'] = [
                'id' => $latestOrderMessage['id'] ?? null,
                'order_id' => (string) ($latestOrderMessage['order_id'] ?? ''),
                'sender_type' => $latestOrderMessage['sender_type'] ?? null,
                'message' => $latestOrderMessage['message'] ?? null,
                'created_at' => $msgCreated?->toIso8601String(),
            ];
            $payload['last_message_at'] = $msgCreated?->toIso8601String();
            $payload['last_message'] = $latestOrderMessage['message'] ?? null;
        }

        return $payload;
    }

    /**
     * Create order (Firestore). Merges into an existing cancellable order when slot matches.
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'product_name' => 'required|string|max:255',
            'product_type' => 'required|string|max:255',
            'gallon_size' => 'required|string|max:50',
            'delivery_date' => 'required|date',
            'delivery_time' => 'required|string',
            'delivery_address' => 'required|string',
            'amount' => 'required|numeric|min:0',
            'payment_method' => 'required|string|max:50',
            'quantity' => 'nullable|integer|min:1',
            'qty' => 'nullable|integer|min:1',
            'customer_name' => 'nullable|string|max:255',
            'customer_phone' => 'nullable|string|max:50',
            'address_first_name' => 'nullable|string|max:100',
            'address_last_name' => 'nullable|string|max:100',
            'address_contact' => 'nullable|string|max:50',
        ]);

        $user = $request->user();
        $addressFirstName = trim((string) $request->input('address_first_name', $request->input('first_name', '')));
        $addressLastName = trim((string) $request->input('address_last_name', $request->input('last_name', '')));
        $addressContact = trim((string) $request->input('address_contact', $request->input('contact_no', $request->input('phone', ''))));
        $addressName = trim($addressFirstName.' '.$addressLastName);
        $customerName = $this->firstNonEmptyString([
            $request->input('customer_name'),
            $addressName,
            $this->isCustomerUser($user) ? trim((string) (($user->firstname ?? '').' '.($user->lastname ?? ''))) : null,
            'Guest',
        ]);
        $customerPhone = $this->firstNonEmptyString([
            $request->input('customer_phone'),
            $addressContact,
            $this->isCustomerUser($user) ? ($user->contact_no ?? null) : null,
            '',
        ]);
        $customerImage = $request->input('customer_image', 'img/default-user.png');
        $customerId = $this->isCustomerUser($user) ? (string) $user->id : null;
        $addQty = max(1, (int) $request->input('quantity', $request->input('qty', 1)));
        $addAmount = (float) $request->amount;
        $downpayment = 0.0;
        $balance = $addAmount;

        $flavor = $this->firestore->firstWhere('flavors', 'name', (string) $request->product_name);
        $productImage = $flavor['image'] ?? 'img/default-product.png';

        $reqDeliveryDate = Carbon::parse((string) $request->delivery_date)->format('Y-m-d');
        $reqDeliveryTime = trim((string) $request->delivery_time);
        $reqAddress = trim((string) $request->delivery_address);

        $existing = $this->findMergeableOrder(
            $customerId,
            (string) $request->product_name,
            (string) $request->gallon_size,
            $reqDeliveryDate,
            $reqDeliveryTime,
            $reqAddress
        );

        if ($existing) {
            $eid = (string) $existing['id'];
            $newQty = (int) ($existing['qty'] ?? 1) + $addQty;
            $newAmount = (float) ($existing['amount'] ?? 0) + $addAmount;
            $existingDownpayment = (float) ($existing['downpayment'] ?? 0.0);
            $this->firestore->update('orders', $eid, [
                'qty' => $newQty,
                'amount' => $newAmount,
                'balance' => max(0, $newAmount - $existingDownpayment),
            ]);
            $order = $this->firestore->get('orders', $eid) ?? array_merge($existing, [
                'qty' => $newQty,
                'amount' => $newAmount,
                'balance' => max(0, $newAmount - $existingDownpayment),
            ]);
            $this->firebase->touchOrdersUpdated();

            return response()->json(['success' => true, 'data' => $this->formatOrderForApi($order), 'merged' => true], 200);
        }

        $orderId = $this->firestore->add('orders', [
            'customer_id' => $customerId,
            'transaction_id' => strtoupper(Str::random(10)),
            'product_name' => $request->product_name,
            'product_type' => $request->product_type,
            'gallon_size' => $request->gallon_size,
            'product_image' => $productImage,
            'customer_name' => $customerName,
            'customer_phone' => $customerPhone,
            'customer_image' => $customerImage,
            'delivery_date' => $request->delivery_date,
            'delivery_time' => $request->delivery_time,
            'delivery_address' => $request->delivery_address,
            'amount' => $request->amount,
            'downpayment' => $downpayment,
            'balance' => $balance,
            'qty' => $addQty,
            'payment_method' => $request->payment_method,
            'status' => 'pending',
        ]);

        $order = $this->firestore->get('orders', $orderId) ?? ['id' => $orderId];

        if ($customerId !== null) {
            $notifId = $this->firestore->add('customer_notifications', [
                'customer_id' => $customerId,
                'type' => CustomerNotification::TYPE_ORDER_PLACED,
                'title' => (string) ($order['product_name'] ?? ''),
                'message' => 'Your order request was placed successfully.',
                'image_url' => $productImage,
                'related_type' => 'Order',
                'related_id' => (string) ($order['id'] ?? $orderId),
                'data' => ['transaction_id' => (string) ($order['transaction_id'] ?? '')],
                'read_at' => null,
            ]);
            try {
                $this->firebase->syncNotification(
                    $this->firebaseNumericCustomerId($customerId),
                    (int) preg_replace('/\D/', '', (string) $notifId) ?: crc32((string) $notifId),
                    [
                        'id' => $notifId,
                        'type' => CustomerNotification::TYPE_ORDER_PLACED,
                        'title' => (string) ($order['product_name'] ?? ''),
                        'message' => 'Your order request was placed successfully.',
                        'image_url' => $productImage,
                        'related_type' => 'Order',
                        'related_id' => (string) ($order['id'] ?? $orderId),
                        'data' => ['transaction_id' => (string) ($order['transaction_id'] ?? '')],
                        'read_at' => null,
                        'created_at' => now()->toIso8601String(),
                    ]
                );
            } catch (\Throwable $e) {
                report($e);
            }
        }

        $this->createAdminNotificationsOrderNew($customerName, $productImage, (string) ($order['id'] ?? $orderId), (string) ($order['transaction_id'] ?? ''), (string) ($order['product_name'] ?? ''));

        $this->firebase->touchOrdersUpdated();

        return response()->json(['success' => true, 'data' => $this->formatOrderForApi($order)], 201);
    }

    /**
     * Single order for authenticated customer.
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (! $this->isCustomerUser($user)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }
        $order = $this->firestore->get('orders', $id);
        if (! $order || (string) ($order['customer_id'] ?? '') !== (string) $user->id) {
            return response()->json(['success' => false, 'message' => 'Order not found.'], 404);
        }

        return response()->json(['success' => true, 'data' => $this->formatOrderForApi($order)]);
    }

    /**
     * Cancel an order (only pending, preparing, or assigned).
     * PATCH /api/v1/orders/{id}/cancel
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (! $this->isCustomerUser($user)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $request->validate([
            'reason' => 'nullable|string|max:500',
            'reason_detail' => 'nullable|string|max:1000',
        ]);

        $order = $this->firestore->get('orders', $id);
        if (! $order || (string) ($order['customer_id'] ?? '') !== (string) $user->id) {
            return response()->json(['success' => false, 'message' => 'Order not found.'], 404);
        }

        if (! in_array($this->normalizeStatus((string) ($order['status'] ?? '')), self::STATUS_CANCELLABLE, true)) {
            return response()->json([
                'success' => false,
                'message' => 'Only pending or assigned orders can be cancelled.',
            ], 422);
        }

        $reason = $request->input('reason');
        $detail = $request->input('reason_detail');
        $reasonText = $reason;
        if ($detail !== null && $detail !== '') {
            $reasonText = ($reason ? $reason.': ' : '').$detail;
        }

        $this->firestore->update('orders', $id, [
            'status' => 'cancelled',
            'reason' => $reasonText,
        ]);

        $updated = $this->firestore->get('orders', $id) ?? array_merge($order, ['status' => 'cancelled', 'reason' => $reasonText]);

        $notifId = $this->firestore->add('customer_notifications', [
            'customer_id' => (string) $user->id,
            'type' => CustomerNotification::TYPE_ORDER_STATUS,
            'title' => $updated['product_name'] ?? 'Order Update',
            'message' => 'Order request cancelled successfully.',
            'image_url' => $updated['product_image'] ?? 'img/default-product.png',
            'related_type' => 'Order',
            'related_id' => (string) ($updated['id'] ?? $id),
            'data' => [
                'transaction_id' => (string) ($updated['transaction_id'] ?? ''),
                'status' => 'cancelled',
            ],
            'read_at' => null,
        ]);
        try {
            $this->firebase->syncNotification(
                $this->firebaseNumericCustomerId((string) $user->id),
                (int) preg_replace('/\D/', '', (string) $notifId) ?: crc32((string) $notifId),
                [
                    'id' => $notifId,
                    'type' => CustomerNotification::TYPE_ORDER_STATUS,
                    'title' => $updated['product_name'] ?? 'Order Update',
                    'message' => 'Order request cancelled successfully.',
                    'image_url' => $updated['product_image'] ?? 'img/default-product.png',
                    'related_type' => 'Order',
                    'related_id' => (string) ($updated['id'] ?? $id),
                    'data' => [
                        'transaction_id' => (string) ($updated['transaction_id'] ?? ''),
                        'status' => 'cancelled',
                    ],
                    'read_at' => null,
                    'created_at' => now()->toIso8601String(),
                ]
            );
        } catch (\Throwable $e) {
            report($e);
        }

        $this->firebase->touchOrdersUpdated();

        return response()->json([
            'success' => true,
            'message' => 'Order cancelled successfully.',
            'data' => $this->formatOrderForApi($updated),
        ]);
    }

    public function feedback(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (! $this->isCustomerUser($user)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'message' => 'nullable|string|max:2000',
        ]);

        $order = $this->firestore->get('orders', $id);
        if (! $order || (string) ($order['customer_id'] ?? '') !== (string) $user->id) {
            return response()->json(['success' => false, 'message' => 'Order not found.'], 404);
        }

        if (! in_array($this->normalizeStatus((string) ($order['status'] ?? '')), self::STATUS_RATEABLE, true)) {
            return response()->json([
                'success' => false,
                'message' => 'You can only rate orders with status Completed.',
            ], 422);
        }

        $flavor = $this->firestore->firstWhere('flavors', 'name', (string) ($order['product_name'] ?? ''));
        $customerName = trim((string) (($user->firstname ?? '').' '.($user->lastname ?? '')));
        $photo = $user->image ?? null;
        $testimonial = (string) $request->input('message', '');
        $rating = (int) $request->input('rating');

        $existing = collect($this->firestore->where('feedback', 'order_id', (string) $id))->first();

        $feedbackPayload = [
            'flavor_id' => $flavor['id'] ?? null,
            'order_id' => (string) $id,
            'customer_name' => $customerName,
            'photo' => $photo,
            'rating' => $rating,
            'testimonial' => $testimonial,
            'feedback_date' => now()->toIso8601String(),
        ];

        $created = false;
        if ($existing) {
            $this->firestore->update('feedback', (string) $existing['id'], $feedbackPayload);
            $fb = $this->firestore->get('feedback', (string) $existing['id']) ?? array_merge($existing, $feedbackPayload);
        } else {
            $fid = $this->firestore->add('feedback', $feedbackPayload);
            $fb = $this->firestore->get('feedback', $fid) ?? array_merge($feedbackPayload, ['id' => $fid]);
            $created = true;
        }

        $fd = $fb['feedback_date'] ?? null;

        return response()->json([
            'success' => true,
            'message' => 'Thank you for your feedback!',
            'data' => [
                'id' => $fb['id'] ?? null,
                'order_id' => $id,
                'rating' => $fb['rating'] ?? $rating,
                'message' => $fb['testimonial'] ?? $testimonial,
                'feedback_date' => $fd ? Carbon::parse((string) $fd)->toIso8601String() : null,
            ],
        ], $created ? 201 : 200);
    }

    private function ordersForCustomer(string $customerId): Collection
    {
        return collect($this->firestore->all('orders'))
            ->filter(fn (array $o) => (string) ($o['customer_id'] ?? '') === $customerId);
    }

    private function findMergeableOrder(
        ?string $customerId,
        string $productName,
        string $gallonSize,
        string $reqDeliveryDateYmd,
        string $reqDeliveryTime,
        string $reqAddress
    ): ?array {
        if ($customerId === null || $customerId === '') {
            return null;
        }

        $candidates = $this->ordersForCustomer($customerId)->filter(function (array $o) use (
            $productName,
            $gallonSize,
            $reqDeliveryDateYmd,
            $reqDeliveryTime,
            $reqAddress
        ) {
            if ((string) ($o['product_name'] ?? '') !== $productName) {
                return false;
            }
            if ((string) ($o['gallon_size'] ?? '') !== $gallonSize) {
                return false;
            }
            $d = '';
            if (! empty($o['delivery_date'])) {
                try {
                    $d = Carbon::parse((string) $o['delivery_date'])->format('Y-m-d');
                } catch (\Throwable) {
                    $d = '';
                }
            }
            if ($d !== $reqDeliveryDateYmd) {
                return false;
            }
            if (trim((string) ($o['delivery_time'] ?? '')) !== trim($reqDeliveryTime)) {
                return false;
            }
            if (trim((string) ($o['delivery_address'] ?? '')) !== trim($reqAddress)) {
                return false;
            }

            return in_array($this->normalizeStatus((string) ($o['status'] ?? '')), self::STATUS_CANCELLABLE, true);
        });

        return $candidates->sortByDesc(fn ($o) => (string) ($o['created_at'] ?? ''))->first();
    }

    private function statusMatches(array $order, array $allowedRaw): bool
    {
        return in_array($this->normalizeStatus((string) ($order['status'] ?? '')), array_map(
            fn (string $s) => $this->normalizeStatus($s),
            $allowedRaw
        ), true);
    }

    private function createAdminNotificationsOrderNew(
        string $customerName,
        string $productImage,
        string $orderId,
        string $transactionId,
        string $productName
    ): void {
        $admins = $this->firestore->all('admins');
        foreach ($admins as $admin) {
            if (empty($admin['id'])) {
                continue;
            }
            $this->firestore->add('admin_notifications', [
                'user_id' => (string) $admin['id'],
                'type' => AdminNotification::TYPE_ORDER_NEW,
                'title' => $customerName,
                'message' => null,
                'image_url' => $productImage,
                'related_type' => 'Order',
                'related_id' => $orderId,
                'data' => ['subtitle' => 'Order #'.$transactionId, 'highlight' => $productName],
                'read_at' => null,
            ]);
        }
        try {
            $this->firebase->touchAdminNotificationsUpdated();
        } catch (\Throwable $e) {
            report($e);
        }
    }

    private function isCustomerUser(mixed $user): bool
    {
        return is_object($user) && isset($user->id) && (string) $user->id !== '';
    }

    private function normalizeStatus(string $status): string
    {
        return strtolower(trim($status));
    }

    /**
     * @param  array<int, mixed>  $values
     */
    private function firstNonEmptyString(array $values): string
    {
        foreach ($values as $value) {
            $text = trim((string) $value);
            if ($text !== '') {
                return $text;
            }
        }

        return '';
    }
}
