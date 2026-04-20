import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// H&R brand styling for connectivity / server alerts (matches landing page dialogs).
abstract final class HrConnectivityDialog {
  static const Color _brand = Color(0xFFE3001B);
  static const Color _text = Color(0xFF313131);

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    Color? iconAccent,
    Color? iconBackground,
  }) {
    final accent = iconAccent ?? _brand;
    final bg = iconBackground ?? _brand.withOpacity(0.12);

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: accent),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    color: _text.withOpacity(0.72),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// HTTP 5xx or similar — server-side failure.
  static Future<void> showServerUnavailable(BuildContext context) {
    return show(
      context,
      title: 'Server unavailable',
      message:
          'The server is temporarily unavailable. Please try again in a moment.',
      icon: Icons.cloud_off_rounded,
      iconAccent: const Color(0xFFC62828),
      iconBackground: const Color(0xFFFFEBEE),
    );
  }

  /// No route to host / DNS / TLS — typical [http.ClientException].
  static Future<void> showNoConnection(BuildContext context) {
    return show(
      context,
      title: 'No connection',
      message:
          "You don't have an internet connection, or the server could not be reached. "
          'Please check your network and try again.',
      icon: Icons.wifi_off_rounded,
    );
  }

  /// Request exceeded time budget ([TimeoutException]).
  static Future<void> showRequestTimedOut(BuildContext context) {
    return show(
      context,
      title: 'Connection problem',
      message:
          'The request timed out. Check your internet connection and try again.',
      icon: Icons.schedule_rounded,
      iconAccent: const Color(0xFFE65100),
      iconBackground: const Color(0xFFFFF3E0),
    );
  }

  /// Maps network-layer errors to the appropriate professional dialog.
  static Future<void> showForError(BuildContext context, Object error) {
    if (error is TimeoutException) {
      return showRequestTimedOut(context);
    }
    if (error is http.ClientException) {
      return showNoConnection(context);
    }
    return show(
      context,
      title: 'No connection',
      message:
          "We couldn't reach the server. Check your internet connection and try again.",
      icon: Icons.signal_wifi_off_rounded,
    );
  }
}
