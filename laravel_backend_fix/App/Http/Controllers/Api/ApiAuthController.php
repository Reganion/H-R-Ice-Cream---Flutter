<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AuthenticateApiCustomer;
use App\Mail\OtpVerificationMail;
use App\Support\AdminNotification;
use App\Services\FirebaseRealtimeService;
use App\Services\FirestoreService;
use App\Support\FirestoreCacheKeys;
use App\Support\FirestoreCustomerUser;
use Carbon\Carbon;
use Google_Client;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Kreait\Firebase\Contract\Auth as FirebaseAuthContract;

class ApiAuthController extends Controller
{
    public function __construct(
        protected FirestoreService $firestore,
        protected FirebaseRealtimeService $firebase,
        protected FirebaseAuthContract $firebaseAuth,
    ) {}

    private const STATUS_ACTIVE = 'active';

    private function normalizeEmail(string $email): string
    {
        return strtolower(trim($email));
    }

    /**
     * Trim client id_token and strip accidental "Bearer " prefix (common in HTTP headers).
     */
    private function normalizeBearerIdToken(string $raw): string
    {
        $t = trim($raw);
        if ($t !== '' && stripos($t, 'Bearer ') === 0) {
            $t = trim(substr($t, 7));
        }

        return $t;
    }

    /**
     * Optional password + confirmation after Google auth (Flutter “set password” screen).
     * When `password` is present, it must match `password_confirmation` and meet min length.
     */
    private function validateOptionalGooglePassword(Request $request): void
    {
        if (! $request->filled('password')) {
            return;
        }

        $request->validate([
            'password' => 'required|string|confirmed|min:6',
        ], [
            'password.required' => 'Password is required.',
            'password.confirmed' => 'Passwords do not match.',
            'password.min' => 'Password must be at least 6 characters.',
        ]);
    }

    private function hashGoogleFlowPasswordOrRandom(Request $request): string
    {
        return $request->filled('password')
            ? Hash::make((string) $request->password)
            : Hash::make(Str::random(32));
    }

    /**
     * Verify ID token from the mobile app.
     *
     * Flutter often sends a Firebase Auth ID token (`user.getIdToken()`), not a raw Google OAuth
     * JWT. Those tokens have issuer `https://securetoken.google.com/...` and must be verified with
     * the Firebase Admin SDK (same credentials as Firestore), not Google_Client OAuth client IDs.
     *
     * If the client sends a Google OAuth ID token (`GoogleSignInAuthentication.idToken`), verify
     * with Web / Android OAuth client IDs from config.
     */
    private function verifyGoogleIdTokenOrNull(string $idToken): ?array
    {
        $idToken = $this->normalizeBearerIdToken($idToken);
        if ($idToken === '') {
            return null;
        }

        // Firebase ID tokens first (Flutter should send user.getIdToken()).
        $firebaseProfile = $this->verifyFirebaseIdTokenOrNull($idToken);
        if ($firebaseProfile !== null) {
            return $firebaseProfile;
        }

        $peek = $this->peekJwtClaims($idToken);
        $issuer = (string) ($peek['iss'] ?? '');

        if (str_contains($issuer, 'securetoken.google.com')) {
            return null;
        }

        // Google OAuth ID tokens: aud must match a configured OAuth client.
        $webClientId = (string) (config('services.google.client_id') ?: '');
        $androidClientId = (string) (config('services.google.android_client_id') ?: '');
        $iosClientId = (string) (config('services.google.ios_client_id') ?: '');

        $clientIds = array_values(array_unique(array_filter([$webClientId, $androidClientId, $iosClientId])));

        foreach ($clientIds as $clientId) {
            try {
                $client = new Google_Client([
                    'client_id' => $clientId,
                ]);

                $payload = $client->verifyIdToken($idToken);
                if ($payload) {
                    $p = json_decode(json_encode($payload), true);

                    return is_array($p) ? $this->profileFromGoogleStyleClaims($p) : null;
                }
            } catch (\Throwable $e) {
                // Keep trying other configured client IDs.
            }
        }

        return null;
    }

    /**
     * Build a normalized profile from Google JWT / Firebase identity claims (email, names).
     *
     * @param  array<string, mixed>  $claims
     * @return array{email: string, given_name: ?string, family_name: ?string}|null
     */
    private function profileFromGoogleStyleClaims(array $claims): ?array
    {
        $email = $this->normalizeEmail((string) ($claims['email'] ?? ''));
        if ($email === '') {
            return null;
        }

        $name = (string) ($claims['name'] ?? '');
        $givenName = (string) ($claims['given_name'] ?? '');
        $familyName = (string) ($claims['family_name'] ?? '');

        if ($givenName === '' && $familyName === '' && $name !== '') {
            $chunks = preg_split('/\s+/', trim($name)) ?: [];
            $givenName = (string) ($chunks[0] ?? '');
            $familyName = (string) ($chunks[count($chunks) - 1] ?? '');
        }

        return [
            'email' => $email,
            'given_name' => $givenName !== '' ? $givenName : null,
            'family_name' => $familyName !== '' ? $familyName : null,
        ];
    }

    private function verifyFirebaseIdTokenOrNull(string $idToken): ?array
    {
        $idToken = $this->normalizeBearerIdToken($idToken);

        // Basic shape check (JWT usually contains 2 dots).
        if (substr_count($idToken, '.') < 2) {
            return null;
        }

        $parts = explode('.', $idToken);
        $payloadSegment = $parts[1] ?? '';
        if ($payloadSegment === '') {
            return null;
        }

        $payloadSegment = strtr($payloadSegment, '-_', '+/');
        $payloadSegment .= str_repeat('=', (4 - (strlen($payloadSegment) % 4)) % 4);

        $decodedJson = base64_decode($payloadSegment, true);
        if ($decodedJson === false) {
            return null;
        }

        $payload = json_decode($decodedJson, true);
        if (! is_array($payload)) {
            return null;
        }

        $issuer = (string) ($payload['iss'] ?? '');
        if ($issuer === '' || ! str_contains($issuer, 'securetoken.google.com')) {
            return null;
        }

        try {
            // Laravel Firebase binding (not raw env()) so config cache works.
            // Leeway helps mobile devices with slight clock skew.
            $verifiedToken = $this->firebaseAuth->verifyIdToken($idToken, false, 120);
            $claims = $verifiedToken->claims()->all();
        } catch (\Throwable $e) {
            return null;
        }

        $email = (string) ($claims['email'] ?? '');
        if ($email === '' && isset($claims['sub']) && is_string($claims['sub']) && $claims['sub'] !== '') {
            try {
                $userRecord = $this->firebaseAuth->getUser($claims['sub']);
                $email = (string) ($userRecord->email ?? '');
            } catch (\Throwable) {
                // ignore
            }
        }
        if ($email === '') {
            return null;
        }

        $claims['email'] = $this->normalizeEmail($email);

        return $this->profileFromGoogleStyleClaims($claims);
    }

    /**
     * Decode JWT payload without verifying signature (debug only).
     *
     * @return array<string, mixed>
     */
    private function peekJwtClaims(string $jwt): array
    {
        if (substr_count($jwt, '.') < 2) {
            return [];
        }

        $parts = explode('.', $jwt);
        $payloadSegment = $parts[1] ?? '';
        if ($payloadSegment === '') {
            return [];
        }

        $payloadSegment = strtr($payloadSegment, '-_', '+/');
        $payloadSegment .= str_repeat('=', (4 - (strlen($payloadSegment) % 4)) % 4);

        $decodedJson = base64_decode($payloadSegment, true);
        if ($decodedJson === false) {
            return [];
        }

        $payload = json_decode($decodedJson, true);
        return is_array($payload) ? $payload : [];
    }

    /**
     * Customer login (for Flutter). Starts session: creates token, stores in cache, returns token + customer.
     * Client sends token as Authorization: Bearer {token} or X-Session-Token on protected routes.
     */
    public function login(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        $row = $this->firestore->firstWhere('customers', 'email', $email);

        if (! $row || ! Hash::check($request->password, (string) ($row['password'] ?? ''))) {
            throw ValidationException::withMessages(['email' => ['The provided credentials are incorrect.']]);
        }

        $customer = FirestoreCustomerUser::fromArray($row);
        if (! $customer || ! FirestoreCustomerUser::isEmailVerified($customer)) {
            return response()->json([
                'success' => false,
                'message' => 'Please verify your email with the 4-digit OTP first.',
                'email' => $email,
            ], 403);
        }

        $token = Str::random(64);
        Cache::put(AuthenticateApiCustomer::CACHE_PREFIX.$token, (string) $row['id'], now()->addMinutes(AuthenticateApiCustomer::TTL_MINUTES));

        return response()->json([
            'success' => true,
            'message' => 'Logged in successfully.',
            'customer' => $this->customerProfileArray($row),
            'token' => $token,
        ]);
    }

    public function googleLogin(Request $request): JsonResponse
    {
        $request->validate([
            'id_token' => 'required|string',
        ]);
        $this->validateOptionalGooglePassword($request);

        $payload = $this->verifyGoogleIdTokenOrNull((string) $request->id_token);
        if ($payload === null) {
            $claims = $this->peekJwtClaims((string) $request->id_token);
            $iss = (string) ($claims['iss'] ?? '');
            $aud = $claims['aud'] ?? null;
            return response()->json([
                'success' => false,
                'message' => 'Invalid Google token.',
                'debug' => [
                    'iss' => $iss,
                    // aud can be string or array depending on issuer/version.
                    'aud' => is_array($aud) ? array_values($aud) : $aud,
                ],
            ], 401);
        }

        $email = $this->normalizeEmail((string) ($payload['email'] ?? ''));
        if ($email === '') {
            return response()->json([
                'success' => false,
                'message' => 'Google token missing email.',
            ], 422);
        }

        $firstname = $payload['given_name'] ?? null;
        $lastname = $payload['family_name'] ?? null;

        $row = $this->firestore->firstWhere('customers', 'email', $email);

        if (! $row) {
            $id = $this->firestore->add('customers', [
                'firstname' => $firstname ?: 'Google',
                'lastname' => $lastname ?: 'User',
                'email' => $email,
                'contact_no' => null,
                'image' => 'img/default-user.png',
                'status' => self::STATUS_ACTIVE,
                'password' => $this->hashGoogleFlowPasswordOrRandom($request),
                'otp' => null,
                'otp_expires_at' => null,
                'email_verified_at' => now()->toIso8601String(),
            ]);
            FirestoreCacheKeys::invalidateCustomers();
            $row = $this->firestore->get('customers', $id);
        } else {
            $id = (string) $row['id'];
            $updates = [];
            if (empty($row['email_verified_at'])) {
                $updates['email_verified_at'] = now()->toIso8601String();
            }
            $updates['otp'] = null;
            $updates['otp_expires_at'] = null;
            if (empty($row['firstname']) && $firstname) {
                $updates['firstname'] = $firstname;
            }
            if (empty($row['lastname']) && $lastname) {
                $updates['lastname'] = $lastname;
            }
            if ($request->filled('password')) {
                $updates['password'] = Hash::make((string) $request->password);
            }
            if ($updates !== []) {
                $this->firestore->update('customers', $id, $updates);
                $row = $this->firestore->get('customers', $id) ?? array_merge($row, $updates, ['id' => $id]);
            }
        }

        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Could not load customer.'], 500);
        }

        $token = Str::random(64);
        Cache::put(
            AuthenticateApiCustomer::CACHE_PREFIX.$token,
            (string) $row['id'],
            now()->addMinutes(AuthenticateApiCustomer::TTL_MINUTES)
        );

        return response()->json([
            'success' => true,
            'message' => 'Google login successful.',
            'customer' => $this->customerProfileArray($row),
            'token' => $token,
        ]);
    }

    /**
     * Google sign-in endpoint (alias of googleLogin for clarity).
     * POST /api/v1/google-sign-in { id_token, optional password, password_confirmation }
     */
    public function googleSignIn(Request $request): JsonResponse
    {
        return $this->googleLogin($request);
    }

    /**
     * Google sign-up endpoint (fails if account already exists).
     * POST /api/v1/google-sign-up { id_token, optional password, password_confirmation }
     */
    public function googleSignUp(Request $request): JsonResponse
    {
        $request->validate([
            'id_token' => 'required|string',
        ]);
        $this->validateOptionalGooglePassword($request);

        $payload = $this->verifyGoogleIdTokenOrNull((string) $request->id_token);
        if ($payload === null) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid Google token.',
            ], 401);
        }

        $email = $this->normalizeEmail((string) ($payload['email'] ?? ''));
        if ($email === '') {
            return response()->json([
                'success' => false,
                'message' => 'Google token missing email.',
            ], 422);
        }

        $firstname = $payload['given_name'] ?? null;
        $lastname = $payload['family_name'] ?? null;

        $row = $this->firestore->firstWhere('customers', 'email', $email);
        if ($row) {
            return response()->json([
                'success' => false,
                'message' => 'Account already exists. Use /api/v1/google-sign-in.',
                'email' => $email,
            ], 409);
        }

        $id = $this->firestore->add('customers', [
            'firstname' => $firstname ?: 'Google',
            'lastname' => $lastname ?: 'User',
            'email' => $email,
            'contact_no' => null,
            'image' => 'img/default-user.png',
            'status' => self::STATUS_ACTIVE,
            'password' => $this->hashGoogleFlowPasswordOrRandom($request),
            'otp' => null,
            'otp_expires_at' => null,
            'email_verified_at' => now()->toIso8601String(),
        ]);

        FirestoreCacheKeys::invalidateCustomers();
        $row = $this->firestore->get('customers', $id);

        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Could not create customer.'], 500);
        }

        $token = Str::random(64);
        Cache::put(
            AuthenticateApiCustomer::CACHE_PREFIX.$token,
            (string) $row['id'],
            now()->addMinutes(AuthenticateApiCustomer::TTL_MINUTES)
        );

        return response()->json([
            'success' => true,
            'message' => 'Google sign up successful.',
            'customer' => $this->customerProfileArray($row),
            'token' => $token,
        ]);
    }

    /**
     * Customer register (for Flutter). Sends OTP to email; verify via verify-otp before login.
     */
    public function register(Request $request): JsonResponse
    {
        $request->validate([
            'firstname' => 'required|string|max:50',
            'lastname' => 'required|string|max:50',
            'email' => 'required|email|max:100',
            'contact_no' => 'nullable|string|max:20',
            'password' => 'required|string|confirmed|min:6',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        if ($this->firestore->firstWhere('customers', 'email', $email)) {
            throw ValidationException::withMessages(['email' => ['The email has already been taken.']]);
        }

        $otp = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $otpExpiresAt = now()->addMinutes(10);

        $this->firestore->add('customers', [
            'firstname' => $request->firstname,
            'lastname' => $request->lastname,
            'email' => $email,
            'contact_no' => $request->contact_no,
            'image' => 'img/default-user.png',
            'status' => self::STATUS_ACTIVE,
            'password' => Hash::make($request->password),
            'otp' => $otp,
            'otp_expires_at' => $otpExpiresAt->toIso8601String(),
            'email_verified_at' => null,
        ]);
        FirestoreCacheKeys::invalidateCustomers();

        $customerRow = $this->firestore->firstWhere('customers', 'email', $email);
        if (! $customerRow) {
            return response()->json(['success' => false, 'message' => 'Registration failed.'], 500);
        }

        try {
            Mail::to($email)->send(new OtpVerificationMail($otp, $email));
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'success' => false,
                'message' => 'Account created but we could not send the verification email.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'Account created. A 4-digit code was sent to your email. Verify with POST /api/v1/verify-otp.',
            'email' => $email,
            'customer' => [
                'id' => $customerRow['id'],
                'firstname' => $customerRow['firstname'] ?? null,
                'lastname' => $customerRow['lastname'] ?? null,
                'email' => $customerRow['email'] ?? null,
                'contact_no' => $customerRow['contact_no'] ?? null,
            ],
        ], 201);
    }

    /**
     * Verify OTP (for Flutter). Send email + otp; returns success so client can then call login.
     */
    public function verifyOtp(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'otp' => 'required|string|size:4|regex:/^\d{4}$/',
        ], [
            'otp.required' => 'Please enter the 4-digit code.',
            'otp.size' => 'The code must be 4 digits.',
            'otp.regex' => 'The code must be 4 digits only.',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        $customer = $this->firestore->firstWhere('customers', 'email', $email);
        if (! $customer) {
            return response()->json([
                'success' => false,
                'message' => 'Account not found.',
            ], 404);
        }

        if (($customer['otp'] ?? null) !== $request->otp) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid or expired code. Please try again.',
            ], 422);
        }

        $expires = ! empty($customer['otp_expires_at'])
            ? Carbon::parse((string) $customer['otp_expires_at'])
            : null;
        if ($expires && $expires->isPast()) {
            return response()->json([
                'success' => false,
                'message' => 'This code has expired. Request a new one with POST /api/v1/resend-otp.',
            ], 422);
        }

        $id = (string) $customer['id'];
        $this->firestore->update('customers', $id, [
            'email_verified_at' => now()->toIso8601String(),
            'otp' => null,
            'otp_expires_at' => null,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Email verified. You can now log in.',
            'email' => $email,
        ]);
    }

    /**
     * Resend OTP (for Flutter). Send email; generates new 4-digit code and emails it.
     */
    public function resendOtp(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        $customer = $this->firestore->firstWhere('customers', 'email', $email);
        if (! $customer) {
            return response()->json([
                'success' => false,
                'message' => 'Account not found.',
            ], 404);
        }

        $otp = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $id = (string) $customer['id'];
        $this->firestore->update('customers', $id, [
            'otp' => $otp,
            'otp_expires_at' => now()->addMinutes(10)->toIso8601String(),
        ]);

        try {
            Mail::to($email)->send(new OtpVerificationMail($otp, $email));
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'success' => false,
                'message' => 'Could not send the new code. Please try again later.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'A new 4-digit code has been sent to your email.',
            'email' => $email,
        ]);
    }

    /**
     * Save/refresh FCM token for authenticated customer device.
     * POST /api/v1/push/token
     */
    public function updateFcmToken(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'token' => 'nullable|string|max:2048',
            'fcm_token' => 'nullable|string|max:2048',
            'platform' => 'nullable|string|in:android,ios,web',
        ]);

        $rawToken = trim((string) ($request->input('token') ?? $request->input('fcm_token') ?? ''));
        if ($rawToken === '') {
            return response()->json([
                'success' => false,
                'message' => 'Provide `token` or `fcm_token` (FCM registration token).',
            ], 422);
        }

        $this->firestore->update('customers', (string) $customer->id, [
            'fcm_token' => $rawToken,
            'fcm_platform' => $request->filled('platform') ? trim((string) $request->input('platform')) : null,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Push token saved successfully.',
        ]);
    }

    /**
     * Clear FCM token for authenticated customer (e.g. on logout).
     * DELETE /api/v1/push/token
     */
    public function clearFcmToken(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $this->firestore->update('customers', (string) $customer->id, [
            'fcm_token' => null,
            'fcm_platform' => null,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Push token removed successfully.',
        ]);
    }

    /**
     * End session: remove token from cache. Send same Bearer token or X-Session-Token as when logged in.
     */
    public function logout(Request $request): JsonResponse
    {
        $token = $this->getTokenFromRequest($request);
        if ($token) {
            Cache::forget(AuthenticateApiCustomer::CACHE_PREFIX.$token);
        }

        return response()->json(['success' => true, 'message' => 'Logged out.']);
    }

    private function getTokenFromRequest(Request $request): ?string
    {
        $header = $request->header('Authorization');
        if ($header && preg_match('/^Bearer\s+(.+)$/i', $header, $m)) {
            return trim($m[1]);
        }

        return $request->header('X-Session-Token') ?: null;
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $this->isAuthenticatedCustomer($user)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }
        $row = $this->firestore->get('customers', (string) $user->id);

        return response()->json([
            'success' => true,
            'customer' => $row ? $this->customerProfileArray($row) : $this->customerProfileArrayFromObject($user),
        ]);
    }

    /**
     * Get my profile (for Flutter). Same as /me, alias for clarity.
     * GET /api/v1/profile with Authorization: Bearer {token}
     */
    public function profile(Request $request): JsonResponse
    {
        return $this->me($request);
    }

    /**
     * Fetch account of who is logged in (account information).
     * GET /api/v1/account with Authorization: Bearer {token}
     * Returns full account info: id, firstname, lastname, email, contact_no, image, image_url, status.
     */
    public function account(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }
        $row = $this->firestore->get('customers', (string) $customer->id);

        return response()->json([
            'success' => true,
            'message' => 'Account information retrieved.',
            'account' => $row ? $this->customerProfileArray($row) : $this->customerProfileArrayFromObject($customer),
        ]);
    }

    /**
     * Delete my account permanently (for Flutter).
     * DELETE /api/v1/account
     * Body: { "password": "...", "reason": "..." } (reason optional)
     */
    public function deleteAccount(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'password' => 'required|string',
            'reason' => 'nullable|string|max:500',
        ], [
            'password.required' => 'Please enter your password to continue.',
        ]);

        $row = $this->firestore->get('customers', (string) $customer->id);
        if (! $row || ! Hash::check($request->password, (string) ($row['password'] ?? ''))) {
            return response()->json([
                'success' => false,
                'message' => 'Password is incorrect.',
            ], 422);
        }

        $customerId = (string) $customer->id;
        $token = $this->getTokenFromRequest($request);

        foreach (['chat_messages', 'customer_notifications', 'customer_addresses', 'cart_items', 'favorites', 'order_messages'] as $collection) {
            try {
                $this->firestore->deleteWhere($collection, 'customer_id', $customerId);
            } catch (\Throwable $e) {
                report($e);
            }
        }

        try {
            $this->firestore->delete('customers', $customerId);
        } catch (\Throwable $e) {
            report($e);

            return response()->json(['success' => false, 'message' => 'Could not delete account.'], 500);
        }

        if ($token) {
            Cache::forget(AuthenticateApiCustomer::CACHE_PREFIX.$token);
        }
        Cache::forget(self::CHANGE_PASSWORD_VERIFIED_PREFIX.$customerId);

        return response()->json([
            'success' => true,
            'message' => 'Your account has been deleted successfully.',
        ]);
    }

    /**
     * Update address details (for Flutter).
     * PUT or POST /api/v1/address
     * Body: province, city, barangay, postal_code, street_name, label_as, reason (all optional).
     */
    public function updateAddress(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'province' => 'nullable|string|max:100',
            'city' => 'nullable|string|max:100',
            'barangay' => 'nullable|string|max:100',
            'postal_code' => 'nullable|string|max:20',
            'street_name' => 'nullable|string|max:255',
            'label_as' => 'nullable|string|max:50',
            'reason' => 'nullable|string|max:500',
        ]);

        $data = array_filter([
            'province' => $request->filled('province') ? trim($request->province) : null,
            'city' => $request->filled('city') ? trim($request->city) : null,
            'barangay' => $request->filled('barangay') ? trim($request->barangay) : null,
            'postal_code' => $request->filled('postal_code') ? trim($request->postal_code) : null,
            'street_name' => $request->filled('street_name') ? trim($request->street_name) : null,
            'label_as' => $request->filled('label_as') ? trim($request->label_as) : null,
            'reason' => $request->filled('reason') ? trim($request->reason) : null,
        ], fn ($v) => $v !== null);

        if (empty($data)) {
            return response()->json([
                'success' => false,
                'message' => 'Provide at least one address field to update.',
            ], 422);
        }

        $this->firestore->update('customers', (string) $customer->id, $data);

        $fresh = $this->firestore->get('customers', (string) $customer->id) ?? [];
        $this->notifyAdminsAddressUpdated($fresh);

        return response()->json([
            'success' => true,
            'message' => 'Address updated successfully.',
            'customer' => $this->customerProfileArray($fresh),
        ]);
    }

    /**
     * Update my profile (for Flutter).
     * POST /api/v1/profile/update
     * Body: multipart/form-data or JSON with firstname, lastname, contact_no; optional image (file or base64)
     */
    public function updateProfile(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'firstname' => 'required|string|max:50',
            'lastname' => 'required|string|max:50',
            'contact_no' => 'nullable|string|max:20|regex:/^[\d\s\-+()]+$/',
            'image' => 'nullable',
        ], [
            'firstname.required' => 'First name is required.',
            'lastname.required' => 'Last name is required.',
        ]);

        $data = [
            'firstname' => $request->firstname,
            'lastname' => $request->lastname,
            'contact_no' => $request->filled('contact_no') ? trim($request->contact_no) : null,
        ];

        if ($request->hasFile('image')) {
            $file = $request->file('image');
            $request->validate(['image' => 'image|mimes:jpeg,png,jpg,gif,webp|max:2048'], [
                'image.image' => 'The file must be an image.',
                'image.max' => 'The image may not be greater than 2MB.',
            ]);
            $dir = public_path('img/customers');
            if (! is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
            $name = 'customer_'.$customer->id.'_'.time().'.'.$file->getClientOriginalExtension();
            $file->move($dir, $name);
            $data['image'] = 'img/customers/'.$name;
        } elseif ($request->filled('image') && preg_match('/^data:image\/(\w+);base64,/', $request->image, $m)) {
            $ext = $m[1] === 'jpeg' ? 'jpg' : $m[1];
            $base64 = substr($request->image, strpos($request->image, ',') + 1);
            $decoded = base64_decode($base64, true);
            if ($decoded !== false) {
                $dir = public_path('img/customers');
                if (! is_dir($dir)) {
                    mkdir($dir, 0755, true);
                }
                $name = 'customer_'.$customer->id.'_'.time().'.'.$ext;
                if (file_put_contents($dir.DIRECTORY_SEPARATOR.$name, $decoded) !== false) {
                    $data['image'] = 'img/customers/'.$name;
                }
            }
        }

        $this->firestore->update('customers', (string) $customer->id, $data);

        $fresh = $this->firestore->get('customers', (string) $customer->id) ?? [];
        $this->notifyAdminsProfileUpdated($fresh, 'Profile');

        return response()->json([
            'success' => true,
            'message' => 'Profile updated successfully.',
            'customer' => $this->customerProfileArray($fresh),
        ]);
    }

    /**
     * Build customer array for API responses (profile, me, login).
     */
    private function customerProfileArray(array $customer): array
    {
        $imagePath = $customer['image'] ?? 'img/default-user.png';
        $imageUrl = $imagePath ? url($imagePath) : null;

        $parts = array_filter([
            $customer['street_name'] ?? null,
            $customer['barangay'] ?? null,
            ! empty($customer['city']) ? $customer['city'].' City' : null,
            $customer['province'] ?? null,
            $customer['postal_code'] ?? null,
        ]);
        $fullAddress = implode(', ', $parts) ?: null;

        return [
            'id' => $customer['id'] ?? null,
            'firstname' => $customer['firstname'] ?? null,
            'lastname' => $customer['lastname'] ?? null,
            'email' => $customer['email'] ?? null,
            'contact_no' => $customer['contact_no'] ?? null,
            'image' => $imagePath,
            'image_url' => $imageUrl,
            'status' => $customer['status'] ?? 'active',
            'province' => $customer['province'] ?? null,
            'city' => $customer['city'] ?? null,
            'barangay' => $customer['barangay'] ?? null,
            'postal_code' => $customer['postal_code'] ?? null,
            'street_name' => $customer['street_name'] ?? null,
            'label_as' => $customer['label_as'] ?? null,
            'reason' => $customer['reason'] ?? null,
            'full_address' => $fullAddress,
        ];
    }

    private function customerProfileArrayFromObject(object $customer): array
    {
        return $this->customerProfileArray([
            'id' => $customer->id ?? null,
            'firstname' => $customer->firstname ?? null,
            'lastname' => $customer->lastname ?? null,
            'email' => $customer->email ?? null,
            'contact_no' => $customer->contact_no ?? null,
            'image' => $customer->image ?? null,
            'status' => $customer->status ?? 'active',
            'province' => $customer->province ?? null,
            'city' => $customer->city ?? null,
            'barangay' => $customer->barangay ?? null,
            'postal_code' => $customer->postal_code ?? null,
            'street_name' => $customer->street_name ?? null,
            'label_as' => $customer->label_as ?? null,
            'reason' => $customer->reason ?? null,
        ]);
    }

    private function isAuthenticatedCustomer(mixed $customer): bool
    {
        return is_object($customer) && isset($customer->id) && $customer->id !== '';
    }

    private function notifyAdminsProfileUpdated(array $c, string $highlight = 'Profile'): void
    {
        $name = trim(($c['firstname'] ?? '').' '.($c['lastname'] ?? '')) ?: ($c['email'] ?? 'Customer');
        $this->broadcastAdminNotifications(
            AdminNotification::TYPE_PROFILE_UPDATE,
            $name,
            $c['image'] ?? null,
            (string) ($c['id'] ?? ''),
            ['subtitle' => 'updated their', 'highlight' => $highlight]
        );
    }

    private function notifyAdminsAddressUpdated(array $c): void
    {
        $name = trim(($c['firstname'] ?? '').' '.($c['lastname'] ?? '')) ?: ($c['email'] ?? 'Customer');
        $this->broadcastAdminNotifications(
            AdminNotification::TYPE_ADDRESS_UPDATE,
            $name,
            $c['image'] ?? null,
            (string) ($c['id'] ?? ''),
            ['subtitle' => 'updated their', 'highlight' => 'Address']
        );
    }

    private function broadcastAdminNotifications(string $type, string $title, ?string $imageUrl, string $relatedId, array $data = []): void
    {
        $admins = $this->firestore->all('admins');
        foreach ($admins as $admin) {
            if (empty($admin['id'])) {
                continue;
            }
            $this->firestore->add('admin_notifications', [
                'user_id' => (string) $admin['id'],
                'type' => $type,
                'title' => $title,
                'message' => null,
                'image_url' => $imageUrl,
                'related_type' => 'Customer',
                'related_id' => $relatedId,
                'data' => $data,
                'read_at' => null,
            ]);
        }
        try {
            $this->firebase->touchAdminNotificationsUpdated();
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Forgot password: send OTP to email (for Flutter).
     * POST /api/v1/forgot-password { "email": "user@example.com" }
     */
    public function forgotPassword(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        $customer = $this->firestore->firstWhere('customers', 'email', $email);
        if (! $customer) {
            return response()->json([
                'success' => false,
                'message' => 'No account found with this email address.',
            ], 404);
        }

        $otp = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $id = (string) $customer['id'];
        $this->firestore->update('customers', $id, [
            'otp' => $otp,
            'otp_expires_at' => now()->addMinutes(10)->toIso8601String(),
        ]);

        try {
            Mail::to($email)->send(new OtpVerificationMail($otp, $email));
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'success' => false,
                'message' => 'Could not send the verification code. Please try again later.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'A 4-digit code has been sent to your email. Use POST /api/v1/forgot-password/verify-otp with email and otp.',
            'email' => $email,
        ]);
    }

    /**
     * Forgot password: resend OTP (for Flutter).
     * POST /api/v1/forgot-password/resend-otp { "email": "user@example.com" }
     */
    public function resendForgotPasswordOtp(Request $request): JsonResponse
    {
        return $this->forgotPassword($request);
    }

    /**
     * Forgot password: verify OTP and get a short-lived reset token (for Flutter).
     * POST /api/v1/forgot-password/verify-otp { "email": "user@example.com", "otp": "1234" }
     * Returns reset_token; use it in POST /api/v1/forgot-password/reset-password.
     */
    public function verifyForgotPasswordOtp(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'otp' => 'required|string|size:4|regex:/^\d{4}$/',
        ], [
            'otp.required' => 'Please enter the 4-digit code.',
            'otp.size' => 'The code must be 4 digits.',
            'otp.regex' => 'The code must be 4 digits only.',
        ]);

        $email = $this->normalizeEmail((string) $request->email);
        $customer = $this->firestore->firstWhere('customers', 'email', $email);
        if (! $customer) {
            return response()->json([
                'success' => false,
                'message' => 'Account not found.',
            ], 404);
        }

        if (($customer['otp'] ?? null) !== $request->otp) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid or expired code. Please try again.',
            ], 422);
        }

        $expires = ! empty($customer['otp_expires_at'])
            ? Carbon::parse((string) $customer['otp_expires_at'])
            : null;
        if ($expires && $expires->isPast()) {
            return response()->json([
                'success' => false,
                'message' => 'This code has expired. Request a new one with POST /api/v1/forgot-password/resend-otp.',
            ], 422);
        }

        $id = (string) $customer['id'];
        $this->firestore->update('customers', $id, ['otp' => null, 'otp_expires_at' => null]);

        $resetToken = Str::random(64);
        Cache::put('password_reset:'.$resetToken, $email, now()->addMinutes(15));

        return response()->json([
            'success' => true,
            'message' => 'Code verified. Use the reset_token in POST /api/v1/forgot-password/reset-password to set your new password.',
            'reset_token' => $resetToken,
            'expires_in_minutes' => 15,
        ]);
    }

    /**
     * Forgot password: set new password using reset_token (for Flutter).
     * POST /api/v1/forgot-password/reset-password { "reset_token": "...", "password": "newpass", "password_confirmation": "newpass" }
     */
    public function resetPassword(Request $request): JsonResponse
    {
        $request->validate([
            'reset_token' => 'required|string',
            'password' => 'required|string|confirmed|min:6',
        ], [
            'password.required' => 'Password is required.',
            'password.confirmed' => 'Passwords do not match.',
            'password.min' => 'Password must be at least 6 characters.',
        ]);

        $email = Cache::get('password_reset:'.$request->reset_token);
        if (! $email) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid or expired reset token. Please start the forgot-password flow again.',
            ], 422);
        }

        $customer = $this->firestore->firstWhere('customers', 'email', $this->normalizeEmail((string) $email));
        if (! $customer) {
            Cache::forget('password_reset:'.$request->reset_token);

            return response()->json([
                'success' => false,
                'message' => 'Account not found.',
            ], 404);
        }

        $id = (string) $customer['id'];
        $this->firestore->update('customers', $id, ['password' => Hash::make($request->password)]);
        Cache::forget('password_reset:'.$request->reset_token);

        return response()->json([
            'success' => true,
            'message' => 'Your password has been updated. You can now log in.',
        ]);
    }

    // --- Change Password (logged-in customer: email → OTP → verify → current + new password → keep logged in or re-login) ---

    private const CHANGE_PASSWORD_VERIFIED_PREFIX = 'change_password_verified:';

    private const CHANGE_PASSWORD_VERIFIED_TTL_MINUTES = 10;

    /**
     * Change password step 1: send OTP to email (for Flutter).
     * POST /api/v1/change-password/send-otp
     * Headers: Authorization: Bearer {token}
     * Body: { "email": "user@example.com" } — must match logged-in customer.
     */
    public function changePasswordSendOtp(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'email' => 'required|email',
        ], [
            'email.required' => 'Please enter your email address.',
            'email.email' => 'Please enter a valid email address.',
        ]);

        if (strcasecmp((string) $customer->email, $this->normalizeEmail((string) $request->email)) !== 0) {
            return response()->json([
                'success' => false,
                'message' => 'This email does not match your account.',
            ], 422);
        }

        $otp = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $this->firestore->update('customers', (string) $customer->id, [
            'otp' => $otp,
            'otp_expires_at' => now()->addMinutes(10)->toIso8601String(),
        ]);

        try {
            Mail::to((string) $customer->email)->send(new OtpVerificationMail($otp, (string) $customer->email));
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'success' => false,
                'message' => 'Could not send the verification code. Please try again later.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'A 4-digit code has been sent to your email. Use POST /api/v1/change-password/verify-otp with otp.',
            'email' => $customer->email,
        ]);
    }

    /**
     * Change password step 2: verify OTP (for Flutter).
     * POST /api/v1/change-password/verify-otp
     * Headers: Authorization: Bearer {token}
     * Body: { "otp": "1234" }
     */
    public function changePasswordVerifyOtp(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $request->validate([
            'otp' => 'required|string|size:4|regex:/^\d{4}$/',
        ], [
            'otp.required' => 'Please enter the 4-digit code.',
            'otp.size' => 'The code must be 4 digits.',
            'otp.regex' => 'The code must be 4 digits only.',
        ]);

        $row = $this->firestore->get('customers', (string) $customer->id);
        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Account not found.'], 404);
        }

        if (($row['otp'] ?? null) !== $request->otp) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid or expired code. Please try again.',
            ], 422);
        }

        $expires = ! empty($row['otp_expires_at'])
            ? Carbon::parse((string) $row['otp_expires_at'])
            : null;
        if ($expires && $expires->isPast()) {
            return response()->json([
                'success' => false,
                'message' => 'This code has expired. Request a new one with POST /api/v1/change-password/send-otp.',
            ], 422);
        }

        $this->firestore->update('customers', (string) $customer->id, ['otp' => null, 'otp_expires_at' => null]);
        Cache::put(self::CHANGE_PASSWORD_VERIFIED_PREFIX.$customer->id, 1, now()->addMinutes(self::CHANGE_PASSWORD_VERIFIED_TTL_MINUTES));

        return response()->json([
            'success' => true,
            'message' => 'Code verified. Use POST /api/v1/change-password/update with current_password, password, password_confirmation, and keep_logged_in.',
            'expires_in_minutes' => self::CHANGE_PASSWORD_VERIFIED_TTL_MINUTES,
        ]);
    }

    /**
     * Change password: resend OTP (for Flutter).
     * POST /api/v1/change-password/resend-otp
     * Headers: Authorization: Bearer {token}
     * Body: { "email": "user@example.com" } — must match logged-in customer.
     */
    public function changePasswordResendOtp(Request $request): JsonResponse
    {
        return $this->changePasswordSendOtp($request);
    }

    /**
     * Change password step 3: set new password (for Flutter).
     * Must have called verify-otp first (within last 10 minutes).
     * POST /api/v1/change-password/update
     * Headers: Authorization: Bearer {token}
     * Body: { "current_password": "...", "password": "newpass", "password_confirmation": "newpass", "keep_logged_in": true }
     * keep_logged_in: if true, token stays valid; if false, token is invalidated and client should log in again.
     */
    public function changePasswordUpdate(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $verified = Cache::get(self::CHANGE_PASSWORD_VERIFIED_PREFIX.$customer->id);
        if (! $verified) {
            return response()->json([
                'success' => false,
                'message' => 'Please verify the OTP first. Use POST /api/v1/change-password/send-otp then verify-otp.',
            ], 422);
        }

        $request->validate([
            'current_password' => 'required',
            'password' => 'required|string|confirmed|min:6',
        ], [
            'current_password.required' => 'Please enter your current password.',
            'password.required' => 'New password is required.',
            'password.confirmed' => 'New passwords do not match.',
            'password.min' => 'New password must be at least 6 characters.',
        ]);

        $row = $this->firestore->get('customers', (string) $customer->id);
        if (! $row || ! Hash::check($request->current_password, (string) ($row['password'] ?? ''))) {
            return response()->json([
                'success' => false,
                'message' => 'Current password is incorrect.',
            ], 422);
        }

        $this->firestore->update('customers', (string) $customer->id, ['password' => Hash::make($request->password)]);
        Cache::forget(self::CHANGE_PASSWORD_VERIFIED_PREFIX.$customer->id);

        $keepLoggedIn = $request->boolean('keep_logged_in');

        if (! $keepLoggedIn) {
            $token = $this->getTokenFromRequest($request);
            if ($token) {
                Cache::forget(AuthenticateApiCustomer::CACHE_PREFIX.$token);
            }

            return response()->json([
                'success' => true,
                'message' => 'Your password has been updated. Please log in again.',
                'logged_out' => true,
            ]);
        }

        $fresh = $this->firestore->get('customers', (string) $customer->id) ?? [];

        return response()->json([
            'success' => true,
            'message' => 'Your password has been updated. You are still logged in.',
            'customer' => $this->customerProfileArray($fresh),
            'token' => $this->getTokenFromRequest($request),
            'logged_out' => false,
        ]);
    }
}
