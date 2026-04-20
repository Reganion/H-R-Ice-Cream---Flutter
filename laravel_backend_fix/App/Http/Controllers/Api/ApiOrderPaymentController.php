<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use App\Models\Invoice;
use App\Models\Order;
use App\Models\Flavor;
use App\Models\AdminNotification;
use App\Models\CustomerNotification;
use App\Services\FirebaseRealtimeService;
use App\Services\PayMongoService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ApiOrderPaymentController extends Controller
{
    protected $paymongo;

    public function __construct(
        PayMongoService $paymongo,
        protected FirebaseRealtimeService $firebase
    ) {
        $this->paymongo = $paymongo;
    }

    public function qrindex()
    {
        $paymentIntent = $this->paymongo->createPaymentIntent(100, "Test QRPH Payment");

        $paymentMethod = $this->paymongo->createQrphPaymentMethod(
            'Juan Dela Cruz',
            'juan@example.com',
            '09171234567'
        );

        $attachResponse = $this->paymongo->attachPaymentMethodToIntent(
            $paymentIntent['id'],
            $paymentMethod['id']
        );

        $qrData = $attachResponse['data']['attributes']['next_action']['code']['image_url'] ?? null;

        return view('payment.qrph.qrph', ['qrData' => $qrData]);
    }

    /**
     * Create a PaymentIntent for customer downpayment (QRPH) and a pending invoice.
     * Order is created only after payment succeeds (no order record until paid).
     * Flutter mobile app calls this after "Place Order" when payment method is Gcash/QRPH.
     *
     * Body (JSON):
     * - product_name, product_type, gallon_size, delivery_date, delivery_time, delivery_address
     * - amount (full order amount), quantity/qty
     * - payment_method ("Gcash" / "QRPH"), downpayment_percent (0.25, 0.5, 0.75, 1.0)
     * - idempotency_key (optional): unique key per "Place Order" to avoid duplicate on retry
     *
     * Response (200): order_id is null until payment succeeds; use invoice_id for status polling.
     */
    public function createDownpayment(Request $request): JsonResponse
    {
        $request->validate([
            'product_name' => 'required|string|max:255',
            'product_type' => 'required|string|max:255',
            'gallon_size' => 'required|string|max:50',
            'delivery_date' => 'required|date',
            'delivery_time' => 'required|string',
            'delivery_address' => 'required|string',
            'amount' => 'required|numeric|min:0.01',
            'payment_method' => 'required|string|max:50',
            'downpayment_percent' => 'required|numeric|min:0.25|max:1.0',
            'quantity' => 'nullable|integer|min:1',
            'qty' => 'nullable|integer|min:1',
            'idempotency_key' => 'nullable|string|max:64',
        ]);

        $user = $request->user();
        if (!$user instanceof Customer) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid user.',
            ], 401);
        }

        $idempotencyKey = $request->input('idempotency_key');
        if ($idempotencyKey !== null && $idempotencyKey !== '') {
            $existing = Invoice::where('idempotency_key', $idempotencyKey)->first();
            if ($existing) {
                $ownerId = $existing->customer_id ?? $existing->order?->customer_id;
                if ($ownerId !== null && (int) $ownerId === (int) $user->id) {
                    $order = $existing->order;
                    $balance = $order ? (float) $order->balance : (float) ($existing->order_payload['balance'] ?? 0);
                    return response()->json([
                        'success' => true,
                        'message' => 'Downpayment already initialized.',
                        'data' => [
                            'order_id' => $order?->id,
                            'invoice_id' => $existing->id,
                            'payment_intent_id' => $existing->payment_intent_id,
                            'qr_image_url' => $existing->qr_image_url,
                            'downpayment_amount' => (float) $existing->amount,
                            'balance' => $balance,
                        ],
                    ]);
                }
            }
        }

        $percent = (float) $request->downpayment_percent;
        $fullAmount = (float) $request->amount;
        $downpaymentAmount = round($fullAmount * $percent, 2);
        $downpaymentCentavos = (int) round($downpaymentAmount * 100);
        $balanceAmount = max(0, $fullAmount - $downpaymentAmount);

        if ($downpaymentCentavos <= 0) {
            return response()->json([
                'success' => false,
                'message' => 'Downpayment amount must be greater than zero.',
            ], 422);
        }

        $quantity = max(
            1,
            (int) $request->input('quantity', $request->input('qty', 1))
        );

        $customerFullName = trim($user->firstname . ' ' . $user->lastname);
        $customerName = $customerFullName !== '' ? $customerFullName : 'Guest';
        $customerPhone = (string) ($user->contact_no ?? '');
        $customerImage = $user->image ?? 'img/default-user.png';

        $flavor = Flavor::where('name', $request->product_name)->first();
        $productImage = $flavor?->image ?? 'img/default-product.png';

        $description = sprintf(
            'Downpayment %.0f%% - %s',
            $percent * 100,
            $request->product_name
        );

        $paymentIntent = $this->paymongo->createPaymentIntent($downpaymentCentavos, $description, $idempotencyKey);
        if (!$paymentIntent || !isset($paymentIntent['id'])) {
            return response()->json([
                'success' => false,
                'message' => 'Could not initialize payment. Please try again.',
            ], 502);
        }

        $paymentMethod = $this->paymongo->createQrphPaymentMethod(
            $customerName,
            $user->email,
            $customerPhone
        );

        if (!$paymentMethod || !isset($paymentMethod['id'])) {
            return response()->json([
                'success' => false,
                'message' => 'Could not initialize payment method. Please try again.',
            ], 502);
        }

        $attachResponse = $this->paymongo->attachPaymentMethodToIntent(
            $paymentIntent['id'],
            $paymentMethod['id']
        );

        $qrImageUrl = $attachResponse['data']['attributes']['next_action']['code']['image_url'] ?? null;
        if (!$qrImageUrl) {
            return response()->json([
                'success' => false,
                'message' => 'Could not generate QR code. Please try again.',
            ], 502);
        }

        $orderPayload = [
            'customer_id' => $user->id,
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
            'amount' => $fullAmount,
            'downpayment' => $downpaymentAmount,
            'balance' => $balanceAmount,
            'qty' => $quantity,
            'payment_method' => $request->payment_method,
            'status' => 'pending',
        ];

        $invoice = Invoice::create([
            'order_id' => null,
            'customer_id' => $user->id,
            'order_payload' => $orderPayload,
            'idempotency_key' => $idempotencyKey ?: null,
            'payment_intent_id' => $paymentIntent['id'],
            'source_id' => $paymentMethod['id'],
            'amount' => $downpaymentAmount,
            'currency' => 'PHP',
            'status' => 'pending',
            'payment_method' => 'qrph',
            'qr_image_url' => $qrImageUrl,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Downpayment initialized. Scan the QR code to pay.',
            'data' => [
                'order_id' => null,
                'invoice_id' => $invoice->id,
                'payment_intent_id' => $paymentIntent['id'],
                'qr_image_url' => $qrImageUrl,
                'downpayment_amount' => $downpaymentAmount,
                'balance' => $balanceAmount,
            ],
        ]);
    }

    /**
     * Check PayMongo status for a downpayment and update invoice/order.
     * When payment succeeds, Order is created from stored payload and linked to invoice.
     * GET /api/v1/orders/downpayment/status/{invoice}
     */
    public function checkDownpaymentStatus(Request $request, Invoice $invoice): JsonResponse
    {
        $user = $request->user();
        if (!$user instanceof Customer) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid user.',
            ], 401);
        }

        $ownerId = $invoice->customer_id ?? $invoice->order?->customer_id;
        if ($ownerId === null || (int) $ownerId !== (int) $user->id) {
            return response()->json([
                'success' => false,
                'message' => 'Invoice not found.',
            ], 404);
        }

        if (!$invoice->payment_intent_id) {
            return response()->json([
                'success' => false,
                'message' => 'No payment intent found for this invoice.',
            ], 422);
        }

        $status = $this->paymongo->getPaymentStatus($invoice->payment_intent_id);

        if ($status === 'succeeded' && $invoice->status !== 'paid') {
            $order = $invoice->order;

            if ($order === null && is_array($invoice->order_payload) && !empty($invoice->order_payload)) {
                $payload = $invoice->order_payload;
                $order = Order::create([
                    'customer_id' => $payload['customer_id'],
                    'transaction_id' => $payload['transaction_id'],
                    'product_name' => $payload['product_name'],
                    'product_type' => $payload['product_type'],
                    'gallon_size' => $payload['gallon_size'],
                    'product_image' => $payload['product_image'] ?? 'img/default-product.png',
                    'customer_name' => $payload['customer_name'],
                    'customer_phone' => $payload['customer_phone'],
                    'customer_image' => $payload['customer_image'] ?? 'img/default-user.png',
                    'delivery_date' => $payload['delivery_date'],
                    'delivery_time' => $payload['delivery_time'],
                    'delivery_address' => $payload['delivery_address'],
                    'amount' => $payload['amount'],
                    'downpayment' => $payload['downpayment'],
                    'balance' => $payload['balance'],
                    'qty' => $payload['qty'],
                    'payment_method' => $payload['payment_method'],
                    'status' => 'pending',
                ]);
                $invoice->order_id = $order->id;
                $invoice->save();

                $productImage = $order->product_image ?? 'img/default-product.png';
                CustomerNotification::create([
                    'customer_id'   => $order->customer_id,
                    'type'          => CustomerNotification::TYPE_ORDER_PLACED,
                    'title'         => $order->product_name,
                    'message'       => 'Your downpayment was received. Order confirmed.',
                    'image_url'     => $productImage,
                    'related_type'  => 'Order',
                    'related_id'    => $order->id,
                    'data'          => ['transaction_id' => $order->transaction_id],
                ]);
                AdminNotification::createForAllAdmins(
                    AdminNotification::TYPE_ORDER_NEW,
                    $order->customer_name,
                    null,
                    $productImage,
                    'Order',
                    $order->id,
                    [
                        'subtitle' => 'paid downpayment for Order #' . $order->transaction_id,
                        'highlight' => $order->product_name,
                    ]
                );
                $this->firebase->touchOrdersUpdated();
            }

            $invoice->status = 'paid';
            $invoice->save();

            if ($order !== null) {
                $currentReceived = (float) ($order->received_amount ?? 0.0);
                $newReceived = $currentReceived + (float) $invoice->amount;
                $order->received_amount = $newReceived;
                $order->balance = max(0, (float) $order->amount - $newReceived);
                $order->save();
                $this->firebase->touchOrdersUpdated();
            }
        } elseif (in_array($status, ['failed', 'cancelled'], true) && $invoice->status !== 'failed') {
            $invoice->status = 'failed';
            $invoice->save();

            $order = $invoice->order;
            if ($order !== null && $order->status === 'pending') {
                $order->status = 'cancelled';
                $order->reason = 'Downpayment failed or cancelled.';
                $order->save();
                $this->firebase->touchOrdersUpdated();
            }
        }

        $order = $invoice->order;
        $orderStatus = $order?->status;
        $orderBalance = $order !== null ? (float) $order->balance : (float) ($invoice->order_payload['balance'] ?? 0);
        $orderReceivedAmount = $order !== null ? (float) $order->received_amount : 0;

        return response()->json([
            'success' => true,
            'data' => [
                'invoice_status' => $invoice->status,
                'order_id' => $order?->id,
                'order_status' => $orderStatus,
                'payment_status' => $status,
                'order_balance' => $orderBalance,
                'order_received_amount' => $orderReceivedAmount,
            ],
        ]);
    }

    /**
     * Cancel a pending downpayment from the app (X/Close button on QR screen).
     * No order record exists until paid, so backing out only marks the invoice failed.
     * POST /api/v1/orders/downpayment/cancel/{invoice}
     */
    public function cancelDownpayment(Request $request, Invoice $invoice): JsonResponse
    {
        $user = $request->user();
        if (!$user instanceof Customer) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid user.',
            ], 401);
        }

        $ownerId = $invoice->customer_id ?? $invoice->order?->customer_id;
        if ($ownerId === null || (int) $ownerId !== (int) $user->id) {
            return response()->json([
                'success' => false,
                'message' => 'Invoice not found.',
            ], 404);
        }

        if ($invoice->status === 'paid') {
            return response()->json([
                'success' => false,
                'message' => 'Downpayment is already paid and cannot be cancelled.',
            ], 422);
        }

        $invoice->status = 'failed';
        $invoice->save();

        $order = $invoice->order;
        if ($order !== null && $order->status === 'pending') {
            $order->status = 'cancelled';
            $order->reason = 'Customer closed payment screen before completing downpayment.';
            $order->save();
            $this->firebase->touchOrdersUpdated();
        }

        return response()->json([
            'success' => true,
            'message' => 'Downpayment has been cancelled.',
            'data' => [
                'invoice_status' => $invoice->status,
                'order_status' => $order?->status,
            ],
        ]);
    }
}