<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Driver;
use App\Models\DriverNotification;
use App\Services\FirebaseRealtimeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ApiDriverNotificationController extends Controller
{
    public function __construct(
        protected FirebaseRealtimeService $firebase
    ) {}

    /**
     * List notifications for authenticated driver.
     * GET /api/v1/driver/notifications
     */
    public function index(Request $request): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $perPage = min((int) $request->get('per_page', 20), 50);
        $unreadOnly = $request->boolean('unread_only');

        $query = DriverNotification::forDriver((int) $driver->id)->orderBy('created_at', 'desc');
        if ($unreadOnly) {
            $query->unread();
        }

        $notifications = $query->paginate($perPage);
        $unreadCount = DriverNotification::forDriver((int) $driver->id)->unread()->count();

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
     * GET /api/v1/driver/notifications/unread-count
     */
    public function unreadCount(Request $request): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $count = DriverNotification::forDriver((int) $driver->id)->unread()->count();

        return response()->json([
            'success' => true,
            'unread_count' => $count,
        ]);
    }

    /**
     * POST /api/v1/driver/notifications/{id}/read
     */
    public function markRead(Request $request, int $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $notification = DriverNotification::forDriver((int) $driver->id)->where('id', $id)->first();
        if (!$notification) {
            return response()->json(['success' => false, 'message' => 'Notification not found.'], 404);
        }

        $notification->markAsRead();

        return response()->json(['success' => true, 'message' => 'Marked as read.']);
    }

    /**
     * POST /api/v1/driver/notifications/read-all
     */
    public function markAllRead(Request $request): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $unreadIds = DriverNotification::forDriver((int) $driver->id)->unread()->pluck('id');
        DriverNotification::forDriver((int) $driver->id)->unread()->update(['read_at' => now()]);
        $readAt = now()->toIso8601String();
        foreach ($unreadIds as $nid) {
            $this->firebase->updateDriverNotificationReadAt((int) $driver->id, (int) $nid, $readAt);
        }

        return response()->json(['success' => true, 'message' => 'All marked as read.']);
    }

    /**
     * DELETE /api/v1/driver/notifications/{id}
     */
    public function destroy(Request $request, int $id): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $notification = DriverNotification::forDriver((int) $driver->id)->where('id', $id)->first();
        if (!$notification) {
            return response()->json(['success' => false, 'message' => 'Notification not found.'], 404);
        }

        $notification->delete();

        return response()->json(['success' => true, 'message' => 'Notification deleted successfully.']);
    }

    /**
     * DELETE /api/v1/driver/notifications
     */
    public function destroyAll(Request $request): JsonResponse
    {
        $driver = $request->user();
        if (!$driver instanceof Driver) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $ids = DriverNotification::forDriver((int) $driver->id)->pluck('id');
        $deleted = DriverNotification::forDriver((int) $driver->id)->delete();
        foreach ($ids as $nid) {
            $this->firebase->deleteDriverNotificationItem((int) $driver->id, (int) $nid);
        }

        return response()->json([
            'success' => true,
            'message' => 'All notifications deleted successfully.',
            'deleted_count' => (int) $deleted,
        ]);
    }
}

