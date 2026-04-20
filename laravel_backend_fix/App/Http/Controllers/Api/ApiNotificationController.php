<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use App\Models\CustomerNotification;
use App\Services\FirebaseRealtimeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ApiNotificationController extends Controller
{
    public function __construct(
        protected FirebaseRealtimeService $firebase
    ) {}

    /**
     * List notifications for the authenticated customer.
     * GET /api/v1/notifications
     * Query: ?page=1&per_page=20&unread_only=0
     */
    public function index(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $perPage = min((int) $request->get('per_page', 20), 50);
        $unreadOnly = $request->boolean('unread_only');

        $query = CustomerNotification::forCustomer($customer->id)->orderBy('created_at', 'desc');

        if ($unreadOnly) {
            $query->unread();
        }

        $notifications = $query->paginate($perPage);

        $unreadCount = CustomerNotification::forCustomer($customer->id)->unread()->count();

        return response()->json([
            'success' => true,
            'data' => $notifications->items(),
            'meta' => [
                'current_page' => $notifications->currentPage(),
                'last_page' => $notifications->lastPage(),
                'per_page' => $notifications->perPage(),
                'total' => $notifications->total(),
            ],
            'unread_count' => $unreadCount,
        ]);
    }

    /**
     * Get unread count only (for badge).
     * GET /api/v1/notifications/unread-count
     */
    public function unreadCount(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $count = CustomerNotification::forCustomer($customer->id)->unread()->count();

        return response()->json([
            'success' => true,
            'unread_count' => $count,
        ]);
    }

    /**
     * Mark a single notification as read.
     * POST /api/v1/notifications/{id}/read
     */
    public function markRead(Request $request, int $id): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $notification = CustomerNotification::forCustomer($customer->id)->where('id', $id)->first();

        if (!$notification) {
            return response()->json(['success' => false, 'message' => 'Notification not found.'], 404);
        }

        $notification->markAsRead();

        return response()->json(['success' => true, 'message' => 'Marked as read.']);
    }

    /**
     * Mark all notifications as read for the current customer.
     * POST /api/v1/notifications/read-all
     */
    public function markAllRead(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $unreadIds = CustomerNotification::forCustomer($customer->id)->unread()->pluck('id');
        CustomerNotification::forCustomer($customer->id)->unread()->update(['read_at' => now()]);
        $readAt = now()->toIso8601String();
        foreach ($unreadIds as $nid) {
            $this->firebase->updateNotificationReadAt((int) $customer->id, (int) $nid, $readAt);
        }

        return response()->json(['success' => true, 'message' => 'All marked as read.']);
    }

    /**
     * Delete a single notification for the current customer.
     * DELETE /api/v1/notifications/{id}
     */
    public function destroy(Request $request, int $id): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $notification = CustomerNotification::forCustomer($customer->id)
            ->where('id', $id)
            ->first();

        if (!$notification) {
            return response()->json(['success' => false, 'message' => 'Notification not found.'], 404);
        }

        $notification->delete();

        return response()->json([
            'success' => true,
            'message' => 'Notification deleted successfully.',
        ]);
    }

    /**
     * Delete all notifications for the current customer.
     * DELETE /api/v1/notifications
     */
    public function destroyAll(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (!$customer instanceof Customer) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $ids = CustomerNotification::forCustomer($customer->id)->pluck('id');
        $deleted = CustomerNotification::forCustomer($customer->id)->delete();
        foreach ($ids as $nid) {
            $this->firebase->deleteCustomerNotificationItem((int) $customer->id, (int) $nid);
        }

        return response()->json([
            'success' => true,
            'message' => 'All notifications deleted successfully.',
            'deleted_count' => (int) $deleted,
        ]);
    }
}
