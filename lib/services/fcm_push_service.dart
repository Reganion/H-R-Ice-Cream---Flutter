import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required so background isolates can use Firebase plugins.
  await Firebase.initializeApp();
}

class FcmPushService {
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Foreground listeners, permissions, token sync — not the background isolate.
  /// Call [FirebaseMessaging.onBackgroundMessage] once in [main] before this.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (!kIsWeb) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
    });

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        await _syncForExistingSession(tokenOverride: token);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('FCM token refresh error: $e');
      },
    );

    unawaited(_syncForExistingSessionSafe());
  }

  static Future<void> syncCustomerToken() async {
    final apiToken = await Auth.getApiToken();
    if (apiToken == null || apiToken.isEmpty) return;
    final fcmToken = await _safeGetToken();
    if (fcmToken == null || fcmToken.isEmpty) return;
    await _postToken(
      endpoint: '/push/token',
      apiToken: apiToken,
      fcmToken: fcmToken,
    );
  }

  static Future<void> clearCustomerToken() async {
    final apiToken = await Auth.getApiToken();
    if (apiToken == null || apiToken.isEmpty) return;
    await _deleteToken(
      endpoint: '/push/token',
      apiToken: apiToken,
    );
  }

  static Future<void> syncDriverToken() async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = prefs.getString('driver_token');
    if (apiToken == null || apiToken.isEmpty) return;
    final fcmToken = await _safeGetToken();
    if (fcmToken == null || fcmToken.isEmpty) return;
    await _postToken(
      endpoint: '/driver/push/token',
      apiToken: apiToken,
      fcmToken: fcmToken,
    );
  }

  static Future<void> clearDriverToken() async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = prefs.getString('driver_token');
    if (apiToken == null || apiToken.isEmpty) return;
    await _deleteToken(
      endpoint: '/driver/push/token',
      apiToken: apiToken,
    );
  }

  static Future<void> _syncForExistingSession({String? tokenOverride}) async {
    final prefs = await SharedPreferences.getInstance();
    final driverToken = prefs.getString('driver_token');
    final customerToken = await Auth.getApiToken();
    final fcmToken = tokenOverride ?? await _safeGetToken();
    if (fcmToken == null || fcmToken.isEmpty) return;

    if (driverToken != null && driverToken.isNotEmpty) {
      await _postToken(
        endpoint: '/driver/push/token',
        apiToken: driverToken,
        fcmToken: fcmToken,
      );
      return;
    }

    if (customerToken != null && customerToken.isNotEmpty) {
      await _postToken(
        endpoint: '/push/token',
        apiToken: customerToken,
        fcmToken: fcmToken,
      );
    }
  }

  static Future<void> _syncForExistingSessionSafe({String? tokenOverride}) async {
    try {
      await _syncForExistingSession(tokenOverride: tokenOverride);
    } catch (e, st) {
      // Startup should never crash if Play services is temporarily unavailable.
      debugPrint('FCM initial sync skipped: $e');
      debugPrint('$st');
    }
  }

  static Future<String?> _safeGetToken() async {
    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (e) {
        // Common transient error on emulator/unstable network:
        // [firebase_messaging/unknown] ... SERVICE_NOT_AVAILABLE
        debugPrint('FCM getToken attempt $attempt failed: $e');
      }

      // Short backoff so background sync (after login, etc.) does not run for many seconds.
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    return null;
  }

  static Future<void> _postToken({
    required String endpoint,
    required String apiToken,
    required String fcmToken,
  }) async {
    final uri = Uri.parse('${Auth.apiBaseUrl}$endpoint');
    final payload = <String, dynamic>{
      'token': fcmToken,
      'platform': _platformValue(),
    };
    try {
      final response = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('FCM token sync rejected at $endpoint: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('FCM token sync failed at $endpoint: $e');
    }
  }

  static Future<void> _deleteToken({
    required String endpoint,
    required String apiToken,
  }) async {
    final uri = Uri.parse('${Auth.apiBaseUrl}$endpoint');
    try {
      await http.delete(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
      );
    } catch (e) {
      debugPrint('FCM token clear failed at $endpoint: $e');
    }
  }

  static String _platformValue() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 'ios';
      default:
        return 'android';
    }
  }
}

