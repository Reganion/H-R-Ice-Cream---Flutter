<?php

/**
 * Copy the protected routes below into your Laravel routes/api.php.
 * Ensure these routes use the 'api.customer' middleware so $request->user() is set.
 * Admin notification routes: protect with your admin auth middleware (e.g. auth:sanctum + admin check).
 */

use App\Http\Controllers\Api\ApiAdminChatController;
use App\Http\Controllers\Api\ApiAdminNotificationController;
use App\Http\Controllers\Api\ApiAuthController;
use App\Http\Controllers\Api\ApiOrderController;
use Illuminate\Support\Facades\Route;

// Public routes (no auth)
Route::post('/login', [ApiAuthController::class, 'login']);
Route::post('/register', [ApiAuthController::class, 'register']);
Route::post('/verify-otp', [ApiAuthController::class, 'verifyOtp']);
Route::post('/resend-otp', [ApiAuthController::class, 'resendOtp']);
// Forgot password (public)
Route::post('/forgot-password', [ApiAuthController::class, 'forgotPassword']);
Route::post('/forgot-password/resend-otp', [ApiAuthController::class, 'resendForgotPasswordOtp']);
Route::post('/forgot-password/verify-otp', [ApiAuthController::class, 'verifyForgotPasswordOtp']);
Route::post('/forgot-password/reset-password', [ApiAuthController::class, 'resetPassword']);

// Protected routes (require Bearer token – Flutter sends Authorization: Bearer {token})
Route::middleware('api.customer')->group(function () {
    Route::post('/logout', [ApiAuthController::class, 'logout']);
    Route::get('/me', [ApiAuthController::class, 'me']);
    Route::get('/profile', [ApiAuthController::class, 'profile']);
    Route::get('/account', [ApiAuthController::class, 'account']);
    Route::post('/profile/update', [ApiAuthController::class, 'updateProfile']);
    // Change password: send OTP → verify OTP → update (current + new password, keep_logged_in)
    Route::post('/change-password/send-otp', [ApiAuthController::class, 'changePasswordSendOtp']);
    Route::post('/change-password/verify-otp', [ApiAuthController::class, 'changePasswordVerifyOtp']);
    Route::post('/change-password/resend-otp', [ApiAuthController::class, 'changePasswordResendOtp']);
    Route::post('/change-password/update', [ApiAuthController::class, 'changePasswordUpdate']);
    Route::get('/orders', [ApiOrderController::class, 'index']);
    Route::post('/orders', [ApiOrderController::class, 'store']);
    Route::get('/orders/{id}', [ApiOrderController::class, 'show']);
});

// Admin (protect with admin middleware in your app, e.g. Route::middleware(['auth:sanctum', 'admin']))
Route::prefix('admin')->group(function () {
    // Admin notifications
    Route::get('/notifications', [ApiAdminNotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [ApiAdminNotificationController::class, 'unreadCount']);
    Route::post('/notifications/{id}/read', [ApiAdminNotificationController::class, 'markRead']);
    Route::post('/notifications/read-all', [ApiAdminNotificationController::class, 'markAllRead']);

    // Admin chat with customers
    Route::get('/chat/customers', [ApiAdminChatController::class, 'customers']);
    Route::get('/chat/customers/{customer_id}/messages', [ApiAdminChatController::class, 'messages']);
    Route::post('/chat/customers/{customer_id}/messages', [ApiAdminChatController::class, 'store']);
    Route::post('/chat/customers/{customer_id}/read', [ApiAdminChatController::class, 'markRead']);
});
