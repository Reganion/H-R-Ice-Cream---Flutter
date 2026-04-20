import 'dart:convert';

import 'package:ice_cream/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

int? _parsePositiveInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v > 0 ? v : null;
  final n = int.tryParse(v.toString());
  if (n == null || n <= 0) return null;
  return n;
}

/// Customer id for RTDB paths `notifications/{id}`, `chats/{id}`, etc.
Future<int?> resolveCustomerId() async {
  final cached = await Auth.getCachedCustomer();
  final fromCache = _parsePositiveInt(cached?['id'] ?? cached?['customer_id']);
  if (fromCache != null) return fromCache;
  try {
    final account = await Auth().fetchAccount();
    return _parsePositiveInt(account['id'] ?? account['customer_id']);
  } catch (_) {
    return null;
  }
}

/// Driver id for RTDB paths `driver_notifications/{id}`, etc.
Future<int?> resolveDriverId() async {
  final prefs = await SharedPreferences.getInstance();
  final json = prefs.getString('driver_profile');
  if (json == null || json.isEmpty) return null;
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return _parsePositiveInt(map['id'] ?? map['driver_id']);
  } catch (_) {
    return null;
  }
}
