<?php

namespace App\Http\Middleware;

use App\Models\Customer;
use App\Services\FirestoreService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Authenticates API requests using Bearer token (or X-Session-Token).
 * Token is stored in cache by ApiAuthController::login() as: CACHE_PREFIX . $token => customer_id.
 * Sets the Customer on the request so $request->user() returns the customer in account(), profile(), etc.
 *
 * Firestore-backed logins store the Firestore document id in cache; those rows are not in MySQL
 * {@see Customer}, so we fall back to {@see FirestoreService} and a stdClass user (same shape as
 * {@see \App\Support\FirestoreCustomerUser}) so controllers like ApiOrderPaymentController see a valid id.
 */
class AuthenticateApiCustomer
{
    public const CACHE_PREFIX = 'api_customer_token:';
    public const TTL_MINUTES = 60 * 24 * 7; // 7 days

    public function handle(Request $request, Closure $next): Response
    {
        $token = $this->getTokenFromRequest($request);

        if (!$token) {
            return response()->json([
                'success' => false,
                'message' => 'Not authenticated.',
            ], 401);
        }

        $customerId = Cache::get(self::CACHE_PREFIX . $token);

        if ($customerId === null) {
            return response()->json([
                'success' => false,
                'message' => 'Not authenticated.',
            ], 401);
        }

        $customer = Customer::find($customerId);

        if ($customer === null) {
            $customer = $this->resolveFirestoreCustomer($customerId);
        }

        if ($customer === null) {
            Cache::forget(self::CACHE_PREFIX . $token);
            return response()->json([
                'success' => false,
                'message' => 'Not authenticated.',
            ], 401);
        }

        // So $request->user() in controllers returns the Customer
        $request->setUserResolver(fn () => $customer);

        return $next($request);
    }

    /**
     * @return object|null  Eloquent Customer or stdClass with id, firstname, lastname, email, contact_no, image
     */
    private function resolveFirestoreCustomer(mixed $customerId): ?object
    {
        if (! class_exists(FirestoreService::class)) {
            return null;
        }

        try {
            $firestore = app(FirestoreService::class);
        } catch (\Throwable) {
            return null;
        }

        $idStr = (string) $customerId;
        $row = $firestore->get('customers', $idStr);
        if (! is_array($row) || $row === []) {
            return null;
        }

        return $this->customerFromFirestoreRow($row, $idStr);
    }

    /**
     * @param  array<string, mixed>  $row
     */
    private function customerFromFirestoreRow(array $row, string $cachedCustomerId): object
    {
        $u = new \stdClass;
        $fromDoc = (string) ($row['id'] ?? '');
        $u->id = $fromDoc !== '' ? $fromDoc : $cachedCustomerId;
        $u->firstname = $row['firstname'] ?? null;
        $u->lastname = $row['lastname'] ?? null;
        $u->email = $row['email'] ?? null;
        $u->contact_no = $row['contact_no'] ?? null;
        $u->image = $row['image'] ?? 'img/default-user.png';

        return $u;
    }

    private function getTokenFromRequest(Request $request): ?string
    {
        $header = $request->header('Authorization');
        if ($header && preg_match('/^Bearer\s+(.+)$/i', $header, $m)) {
            return trim($m[1]);
        }
        return $request->header('X-Session-Token') ?: null;
    }
}
