# Laravel backend fix – "Not authenticated" on profile/account

After login, the Flutter app calls **GET /api/v1/account** with `Authorization: Bearer {token}`. The backend returns "Not authenticated" when `$request->user()` is null. That happens when the **middleware does not set the user** on the request from the token.

## 1. Middleware: set user from token

Copy the middleware file into your Laravel project:

- **From:** `laravel_backend_fix/App/Http/Middleware/AuthenticateApiCustomer.php`
- **To:** `app/Http/Middleware/AuthenticateApiCustomer.php` (in your Laravel project)

This middleware:

- Reads the token from `Authorization: Bearer {token}` or `X-Session-Token`.
- Looks up `Cache::get(CACHE_PREFIX . $token)` to get the customer id (same as in your login).
- Loads `Customer::find($customerId)` and sets it on the request with `$request->setUserResolver(fn () => $customer)` so `$request->user()` in your controllers returns the Customer.

**Cache key:** The middleware uses `CACHE_PREFIX = 'api_customer_token:'`. Your login must use the same prefix when storing the token, e.g.:

```php
Cache::put(AuthenticateApiCustomer::CACHE_PREFIX . $token, $customer->id, now()->addMinutes(AuthenticateApiCustomer::TTL_MINUTES));
```

If your current login uses a different prefix, either change the middleware's `CACHE_PREFIX` to match, or change the login to use `AuthenticateApiCustomer::CACHE_PREFIX`.

## 2. Routes: protect account/profile with `api.customer`

In `routes/api.php` (with your `Route::prefix('v1')` or similar), ensure the account and profile routes use the `api.customer` middleware:

```php
Route::middleware('api.customer')->group(function () {
    Route::get('/account', [ApiAuthController::class, 'account']);
    Route::get('/profile', [ApiAuthController::class, 'profile']);
    Route::get('/me', [ApiAuthController::class, 'me']);
    Route::post('/logout', [ApiAuthController::class, 'logout']);
    Route::post('/profile/update', [ApiAuthController::class, 'updateProfile']);
});
```

See `routes/api_routes_example.php` for a full example.

## 3. Bootstrap: register middleware alias (you already have this)

In `bootstrap/app.php` (Laravel 11) you already have:

```php
$middleware->alias([
    'api.customer' => \App\Http\Middleware\AuthenticateApiCustomer::class,
]);
```

No change needed if this is already there.

## 4. Login response (already correct)

Your login already returns:

```json
{
  "success": true,
  "message": "Logged in successfully.",
  "customer": { ... },
  "token": "..."
}
```

The Flutter app reads `token` and sends it as `Authorization: Bearer {token}` on GET /api/v1/account. Once the middleware above is in place and the routes use `api.customer`, `$request->user()` will be set and "Not authenticated" will be fixed.

---

## Admin notifications (new orders & profile updates)

When a **customer places an order** or **updates their profile**, the admin side is notified.

### What was added

- **Model:** `App\Models\AdminNotification` – stores admin notifications with `type` (`new_order`, `profile_updated`), `title`, `message`, `image_url`, `related_type`, `related_id`, `data`, `read_at`.
- **Migration:** `database/migrations/2025_02_05_000000_create_admin_notifications_table.php` – run `php artisan migrate` to create the `admin_notifications` table.
- **Controller:** `App\Http\Controllers\Api\ApiAdminNotificationController` – list, unread count, mark read, mark all read.
- **Triggers:**
  - **Order:** In `ApiOrderController::store`, after creating the order and the customer notification, `AdminNotification::notifyNewOrder($order)` is called.
  - **Profile:** In `ApiAuthController::updateProfile`, after updating the customer, `AdminNotification::notifyProfileUpdated($customer->fresh())` is called.

### Admin API routes (add to your `routes/api.php` under prefix `v1`)

Protect these with your admin auth middleware (e.g. `auth:sanctum` + admin role check):

- `GET  /admin/notifications` – paginated list (`?page=1&per_page=20&unread_only=0`)
- `GET  /admin/notifications/unread-count` – badge count
- `POST /admin/notifications/{id}/read` – mark one as read
- `POST /admin/notifications/read-all` – mark all as read

See `routes/api_routes_example.php` for the route definitions. Copy the `AdminNotification` model, migration, and `ApiAdminNotificationController` into your main Laravel app, run the migration, and ensure your existing `ApiOrderController::store` calls `AdminNotification::notifyNewOrder($order)` after creating the order (the version in this folder already does).

---

## Admin chat with customers

Admin can view and reply to customer chat messages.

### What was added

- **Controller:** `App\Http\Controllers\Api\ApiAdminChatController` – list customers with chats, get/send messages, mark as read.

### Admin chat API routes (add to your `routes/api.php` under prefix `v1`)

Protect these with your admin auth middleware (e.g. `auth:sanctum` + admin role check):

- `GET  /admin/chat/customers` – list customers with conversations (`?page=1&per_page=20`), includes last message and unread count
- `GET  /admin/chat/customers/{customer_id}/messages` – get messages with a customer (`?page=1&per_page=50`)
- `POST /admin/chat/customers/{customer_id}/messages` – send message (body, optional image file)
- `POST /admin/chat/customers/{customer_id}/read` – mark customer's messages as read

Requires existing `ChatMessage` model and `Customer::chatMessages()` relationship.
