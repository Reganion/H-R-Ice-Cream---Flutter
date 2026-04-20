<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Services\FirebaseRealtimeService;
use App\Services\FirestoreService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class ApiChatController extends Controller
{
    public function __construct(
        protected FirebaseRealtimeService $firebase,
        protected FirestoreService $firestore,
    ) {}

    /**
     * Get chat conversation with admin (messages for the authenticated customer).
     * GET /api/v1/chat/messages?page=1&per_page=20
     */
    public function messages(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $customerId = (string) $customer->id;
        $perPage = min(max((int) $request->get('per_page', 50), 1), 100);
        $page = max(1, (int) $request->get('page', 1));

        $all = $this->customerMessages($customerId);
        $total = $all->count();
        $lastPage = max(1, (int) ceil($total / $perPage));
        $offset = ($page - 1) * $perPage;

        $slice = $all->slice($offset, $perPage)->values();
        $items = $slice->map(fn (array $m) => $this->formatMessage($m))->all();

        return response()->json([
            'success' => true,
            'data' => $items,
            'meta' => [
                'current_page' => $page,
                'last_page' => $lastPage,
                'per_page' => $perPage,
                'total' => $total,
            ],
        ]);
    }

    /**
     * Send a message to admin (customer → admin).
     * POST /api/v1/chat/messages
     * body: optional text, image: optional file (multipart)
     */
    public function store(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $customerId = (string) $customer->id;

        $body = $request->input('body');
        $imagePath = null;

        if ($request->hasFile('image')) {
            $file = $request->file('image');
            if ($file->isValid() && str_starts_with($file->getMimeType(), 'image/')) {
                $dir = public_path('img/chat');
                if (! is_dir($dir)) {
                    mkdir($dir, 0755, true);
                }
                $name = 'chat_'.$customerId.'_'.time().'_'.uniqid().'.'.$file->getClientOriginalExtension();
                if ($file->move($dir, $name)) {
                    $imagePath = 'img/chat/'.$name;
                }
            }
        }

        if (empty(trim((string) ($body ?? ''))) && ! $imagePath) {
            return response()->json([
                'success' => false,
                'message' => 'Provide a message (body) or an image.',
            ], 422);
        }

        $messageId = (string) now()->format('YmdHis').(string) random_int(1000, 9999);
        $payload = [
            'customer_id' => $customerId,
            'sender_type' => ChatMessage::SENDER_CUSTOMER,
            'body' => trim((string) ($body ?? '')) ?: null,
            'image_path' => $imagePath,
            'read_at' => null,
            'created_at' => now()->toIso8601String(),
            'updated_at' => now()->toIso8601String(),
        ];
        $this->firestore->set('chat_messages', $messageId, $payload);

        $message = $this->firestore->get('chat_messages', $messageId) ?? array_merge($payload, ['id' => $messageId]);
        $formatted = $this->formatMessage($message);
        $this->firebase->syncChatMessage($customerId, $messageId, $formatted);
        $this->firebase->touchAdminChatUpdated();

        return response()->json([
            'success' => true,
            'data' => $formatted,
        ]);
    }

    /**
     * Get last message preview and unread count (for chat list/badge).
     * GET /api/v1/chat
     */
    public function index(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $customerId = (string) $customer->id;
        $messages = $this->customerMessages($customerId);

        $lastMessage = $messages->sortByDesc(fn (array $m) => (string) ($m['created_at'] ?? ''))->first();

        $unreadFromAdmin = $messages
            ->filter(fn (array $m) => strtolower((string) ($m['sender_type'] ?? '')) === ChatMessage::SENDER_ADMIN
                && empty($m['read_at']))
            ->count();

        return response()->json([
            'success' => true,
            'data' => [
                'last_message' => $lastMessage ? [
                    'id' => (string) ($lastMessage['id'] ?? ''),
                    'sender_type' => $lastMessage['sender_type'] ?? null,
                    'body' => $lastMessage['body'] ?? null,
                    'image_url' => $this->imageUrlFromPath($lastMessage['image_path'] ?? null),
                    'created_at' => ! empty($lastMessage['created_at'])
                        ? Carbon::parse((string) $lastMessage['created_at'])->toIso8601String()
                        : now()->toIso8601String(),
                ] : null,
                'unread_count' => $unreadFromAdmin,
            ],
        ]);
    }

    /**
     * Mark admin messages as read.
     * POST /api/v1/chat/read
     */
    public function markRead(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Invalid user.'], 401);
        }

        $customerId = (string) $customer->id;
        $toMark = $this->customerMessages($customerId)->filter(function (array $m) {
            return strtolower((string) ($m['sender_type'] ?? '')) === ChatMessage::SENDER_ADMIN
                && empty($m['read_at']);
        });

        $readAt = now()->toIso8601String();
        foreach ($toMark as $m) {
            $msgId = (string) ($m['id'] ?? '');
            if ($msgId === '') {
                continue;
            }
            $this->firestore->update('chat_messages', $msgId, ['read_at' => $readAt]);
            $this->firebase->updateChatMessageReadAt($customerId, $msgId, $readAt);
        }

        return response()->json([
            'success' => true,
            'message' => 'Marked as read.',
        ]);
    }

    private function customerMessages(string $customerId): Collection
    {
        return collect($this->firestore->where('chat_messages', 'customer_id', $customerId))
            ->sortBy(fn (array $m) => (string) ($m['created_at'] ?? ''))
            ->values();
    }

    private function formatMessage(array $m): array
    {
        $imageUrl = $this->imageUrlFromPath($m['image_path'] ?? null);

        return [
            'id' => (string) ($m['id'] ?? ''),
            'sender_type' => (string) ($m['sender_type'] ?? ''),
            'body' => $m['body'] ?? null,
            'image_url' => $imageUrl,
            'created_at' => ! empty($m['created_at'])
                ? Carbon::parse((string) $m['created_at'])->toIso8601String()
                : now()->toIso8601String(),
            'read_at' => ! empty($m['read_at'])
                ? Carbon::parse((string) $m['read_at'])->toIso8601String()
                : null,
        ];
    }

    private function imageUrlFromPath(mixed $path): ?string
    {
        $path = (string) ($path ?? '');
        if ($path === '') {
            return null;
        }

        return str_starts_with($path, 'img/') ? asset($path) : asset('storage/'.$path);
    }

    private function isAuthenticatedCustomer(mixed $customer): bool
    {
        return is_object($customer) && isset($customer->id) && (string) $customer->id !== '';
    }
}
