<?php

/**
 * Updated ApiOrderMessageController – use this to fix archive not updating customer_status.
 *
 * 1. Copy the customerArchive and customerArchiveSelected methods below into your
 *    app/Http/Controllers/Api/ApiOrderMessageController.php (replace the existing ones).
 *
 * 2. Add at the top: use Illuminate\Support\Facades\DB;
 *
 * 3. Ensure order_messages table has column customer_status. If missing, create a migration:
 *
 *    php artisan make:migration add_customer_status_to_order_messages_table
 *
 *    In the migration up() method:
 *        Schema::table('order_messages', function (Blueprint $table) {
 *            $table->string('customer_status', 50)->default('active')->after('message');
 *        });
 *
 *    In down(): $table->dropColumn('customer_status');
 *
 * 4. In app/Models/OrderMessage.php define:
 *    const CUSTOMER_STATUS_ACTIVE = 'active';
 *    const CUSTOMER_STATUS_ARCHIVE = 'archive';
 */

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use App\Models\Driver;
use App\Models\Order;
use App\Models\OrderMessage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ApiOrderMessageController extends Controller
{
    // ... keep all your existing methods (driverMessages, driverSend, customerMessages, etc.) ...

    /**
     * Customer: archive all messages in this order thread (soft-delete from customer view).
     * POST /api/v1/orders/{id}/messages/archive
     * Uses DB::table so customer_status is always updated (avoids Eloquent $guarded).
     */
    public function customerArchive(Request $request, int $id): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $order = $this->resolveCustomerOrder($customer, $id);
        if (!$order) {
            return response()->json(['success' => false, 'message' => 'Order not found.'], 404);
        }

        $archiveStatus = OrderMessage::CUSTOMER_STATUS_ARCHIVE;
        $updated = DB::table('order_messages')
            ->where('order_id', $order->id)
            ->update(['customer_status' => $archiveStatus]);

        return response()->json([
            'success' => true,
            'message' => 'Messages deleted successfully.',
            'archived_count' => $updated,
        ]);
    }

    /**
     * Customer: archive selected messages (soft-delete from customer view).
     * POST /api/v1/orders/{id}/messages/archive-selected
     * Uses DB::table so customer_status is always updated.
     */
    public function customerArchiveSelected(Request $request, int $id): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $order = $this->resolveCustomerOrder($customer, $id);
        if (!$order) {
            return response()->json(['success' => false, 'message' => 'Order not found.'], 404);
        }

        $request->validate([
            'message_ids' => ['required', 'array'],
            'message_ids.*' => ['nullable'],
        ]);

        $rawIds = $request->input('message_ids', []);
        $messageIds = array_values(array_unique(array_filter(array_map(function ($v) {
            $id = is_numeric($v) ? (int) $v : null;
            return $id > 0 ? $id : null;
        }, $rawIds))));

        if ($messageIds === []) {
            return response()->json(['success' => false, 'message' => 'No valid message IDs provided.'], 422);
        }

        $customerOrderIds = Order::query()
            ->where('customer_id', $customer->id)
            ->pluck('id')
            ->all();

        if ($customerOrderIds === []) {
            return response()->json([
                'success' => true,
                'message' => 'Selected messages archived.',
                'archived_count' => 0,
            ]);
        }

        $archiveStatus = OrderMessage::CUSTOMER_STATUS_ARCHIVE;
        $updated = DB::table('order_messages')
            ->whereIn('order_id', $customerOrderIds)
            ->whereIn('id', $messageIds)
            ->update(['customer_status' => $archiveStatus]);

        return response()->json([
            'success' => true,
            'message' => 'Selected messages archived.',
            'archived_count' => $updated,
        ]);
    }
}
