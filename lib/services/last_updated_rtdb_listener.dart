import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Subscribes to a `last_updated` node (see Laravel shape `{ "value": "<ISO8601>" }`)
/// and invokes [onTick] after [debounce].
///
/// - Skips the **first** non-null value so you don’t duplicate the initial REST load.
/// - Ignores duplicate consecutive stamps.
class LastUpdatedRtdbListener {
  LastUpdatedRtdbListener({
    required this.database,
    required this.path,
    this.debounce = const Duration(milliseconds: 450),
    required this.onTick,
  });

  final FirebaseDatabase database;
  final String path;
  final Duration debounce;
  final VoidCallback onTick;

  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _debounceTimer;
  String? _lastSeen;
  bool _primed = false;

  void start() {
    dispose();
    final ref = database.ref(path);
    _sub = ref.onValue.listen(
      (DatabaseEvent event) {
        final v = _extractStamp(event.snapshot.value);
        if (v == null) return;
        if (!_primed) {
          _primed = true;
          _lastSeen = v;
          return;
        }
        if (v == _lastSeen) return;
        _lastSeen = v;
        _debounceTimer?.cancel();
        _debounceTimer = Timer(debounce, onTick);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('RTDB listen error at $path: $e');
      },
    );
  }

  /// Handles `{ "value": "..." }`, plain string, or num.
  static String? _extractStamp(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.isNotEmpty) return raw;
    if (raw is num) return raw.toString();
    if (raw is Map) {
      final v = raw['value'];
      if (v != null) return v.toString();
    }
    final s = raw.toString();
    return s.isEmpty ? null : s;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sub?.cancel();
    _sub = null;
    _lastSeen = null;
    _primed = false;
  }
}
