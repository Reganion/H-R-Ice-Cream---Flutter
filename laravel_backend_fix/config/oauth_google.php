<?php

/**
 * Google OAuth client IDs for verifying Google ID tokens (issuer accounts.google.com).
 * Values are read via config() so they work after `php artisan config:cache`.
 *
 * Use the Web client (client_type 3) and Android client from Firebase / google-services.json.
 */
return [
    'web_client_id' => env('GOOGLE_CLIENT_ID', env('GOOGLE_WEB_CLIENT_ID', '')),
    'android_client_id' => env('GOOGLE_ANDROID_CLIENT_ID', ''),
];
