import 'dart:convert';

Map<String, dynamic> safeDecode(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return <String, dynamic>{};
  }
}

String extractApiMessage(Map<String, dynamic> data) {
  final errors = data['errors'];
  if (errors is Map<String, dynamic>) {
    for (final entry in errors.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty && value.first is String) {
        return value.first as String;
      }
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
  }

  final message = data['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message;
  }

  return 'Request failed. Please try again.';
}
