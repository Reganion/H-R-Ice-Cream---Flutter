<?php

/**
 * Firebase Admin service account path (same Firebase project as the Flutter app).
 * Read via config() so token verification works after `php artisan config:cache`
 * (env() is not reliable outside config files when config is cached).
 */
return [
    'path' => env('FIREBASE_CREDENTIALS', env('GOOGLE_APPLICATION_CREDENTIALS', '')),
];
