import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/firebase_rtdb_config.dart';
import 'package:ice_cream/services/last_updated_rtdb_listener.dart';
import 'package:ice_cream/services/rtdb_user_context.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ice_cream/client/favorite/favorite.dart';
import 'package:ice_cream/client/home_page.dart';
import 'package:ice_cream/client/order/all.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

// --- Chat API (Customer ↔ Admin) ---
/// Matches Laravel ApiChatController / Firestore `chat_messages`.

const String _senderCustomer = 'customer';
const String _senderAdmin = 'admin';

Map<String, String> _customerChatApiHeaders(String token) {
  return {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    'X-Session-Token': token,
  };
}

class ChatMessageItem {
  /// Firestore / API returns string ids (e.g. YmdHis + random).
  final String id;
  final String senderType;
  final String? body;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  ChatMessageItem({
    required this.id,
    required this.senderType,
    this.body,
    this.imageUrl,
    required this.createdAt,
    this.readAt,
  });

  bool get isFromCustomer => senderType == _senderCustomer;
  bool get isFromAdmin => senderType == _senderAdmin;

  static ChatMessageItem fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final idStr = idRaw == null ? '' : idRaw.toString().trim();
    final senderRaw = (json['sender_type'] ?? '').toString().toLowerCase().trim();
    final sender = senderRaw.isEmpty ? _senderCustomer : senderRaw;
    final createdRaw = json['created_at']?.toString();
    final readRaw = json['read_at'];
    return ChatMessageItem(
      id: idStr,
      senderType: sender,
      body: json['body'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.tryParse(createdRaw ?? '')?.toLocal() ?? DateTime.now(),
      readAt: readRaw == null ? null : DateTime.tryParse(readRaw.toString())?.toLocal(),
    );
  }
}

class ChatSummary {
  final ChatMessageItem? lastMessage;
  final int unreadCount;

  ChatSummary({this.lastMessage, this.unreadCount = 0});

  static ChatSummary fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return ChatSummary();
    final lastMsg = data['last_message'] as Map<String, dynamic>?;
    return ChatSummary(
      lastMessage: lastMsg != null ? ChatMessageItem.fromJson(lastMsg) : null,
      unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

Future<ChatSummary?> fetchChatSummary() async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  final uri = Uri.parse('${Auth.apiBaseUrl}/chat');
  final res = await http.get(
    uri,
    headers: _customerChatApiHeaders(token),
  );
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (data == null || data['success'] != true) return null;
  return ChatSummary.fromJson(data);
}

Future<List<ChatMessageItem>?> fetchChatMessages({int page = 1, int perPage = 50}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  final uri = Uri.parse('${Auth.apiBaseUrl}/chat/messages').replace(
    queryParameters: {'page': '$page', 'per_page': '$perPage'},
  );
  final res = await http.get(
    uri,
    headers: _customerChatApiHeaders(token),
  );
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (data == null || data['success'] != true) return null;
  final list = data['data'] as List<dynamic>?;
  if (list == null) return [];
  return list.map((e) => ChatMessageItem.fromJson(e as Map<String, dynamic>)).toList();
}

Future<ChatMessageItem?> sendChatMessage({required String body, String? imagePath}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  if (imagePath != null) {
    final uri = Uri.parse('${Auth.apiBaseUrl}/chat/messages');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_customerChatApiHeaders(token));
    if (body.trim().isNotEmpty) request.fields['body'] = body.trim();
    request.files.add(await http.MultipartFile.fromPath('image', imagePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    if (data == null || data['success'] != true) return null;
    final msg = data['data'] as Map<String, dynamic>?;
    return msg != null ? ChatMessageItem.fromJson(msg) : null;
  }
  final uri = Uri.parse('${Auth.apiBaseUrl}/chat/messages');
  final res = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ..._customerChatApiHeaders(token),
    },
    body: jsonEncode({'body': body.trim()}),
  );
  if (res.statusCode != 200 && res.statusCode != 201) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (data == null || data['success'] != true) return null;
  final msg = data['data'] as Map<String, dynamic>?;
  return msg != null ? ChatMessageItem.fromJson(msg) : null;
}

Future<bool> markChatRead() async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final uri = Uri.parse('${Auth.apiBaseUrl}/chat/read');
  final res = await http.post(
    uri,
    headers: _customerChatApiHeaders(token),
  );
  if (res.statusCode != 200 && res.statusCode != 201) return false;
  try {
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return res.statusCode == 200;
  }
}

// --- Order Message API (Customer <-> Driver) ---

class DriverOrderThread {
  final String orderId;
  final List<String> relatedOrderIds;
  final String driverName;
  final String driverContact;
  final String transactionId;
  final String orderLabel;
  final String? preview;
  final DateTime? lastAt;
  final int unreadCount;

  const DriverOrderThread({
    required this.orderId,
    this.relatedOrderIds = const [],
    required this.driverName,
    this.driverContact = '',
    required this.transactionId,
    required this.orderLabel,
    this.preview,
    this.lastAt,
    this.unreadCount = 0,
  });

  DriverOrderThread copyWith({
    String? orderId,
    List<String>? relatedOrderIds,
    String? driverName,
    String? driverContact,
    String? transactionId,
    String? orderLabel,
    String? preview,
    DateTime? lastAt,
    int? unreadCount,
  }) {
    return DriverOrderThread(
      orderId: orderId ?? this.orderId,
      relatedOrderIds: relatedOrderIds ?? this.relatedOrderIds,
      driverName: driverName ?? this.driverName,
      driverContact: driverContact ?? this.driverContact,
      transactionId: transactionId ?? this.transactionId,
      orderLabel: orderLabel ?? this.orderLabel,
      preview: preview ?? this.preview,
      lastAt: lastAt ?? this.lastAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class OrderMessageItem {
  final int id;
  final String orderId;
  final String senderType;
  final String message;
  final bool isMine;
  final DateTime? createdAt;

  const OrderMessageItem({
    required this.id,
    required this.orderId,
    required this.senderType,
    required this.message,
    required this.isMine,
    required this.createdAt,
  });

  factory OrderMessageItem.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final orderIdRaw = json['order_id'];
    final createdAtRaw = json['created_at']?.toString();
    return OrderMessageItem(
      id: idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '') ?? 0,
      orderId: (orderIdRaw ?? '').toString().trim(),
      senderType: (json['sender_type'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      isMine: json['is_mine'] == true,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw)?.toLocal(),
    );
  }
}

class CustomerOrderNotificationItem {
  final int id;
  final String? _title;
  final String? _message;
  final DateTime? createdAt;
  final DateTime? readAt;
  final String? relatedType;
  /// Order id from `related_id` (Firestore string ids supported).
  final String? relatedOrderId;

  String get title => (_title ?? '').trim();
  String get message => (_message ?? '').trim();
  bool get isRead => readAt != null;

  const CustomerOrderNotificationItem({
    required this.id,
    String? title,
    String? message,
    required this.createdAt,
    this.readAt,
    this.relatedType,
    this.relatedOrderId,
  })  : _title = title,
        _message = message;

  CustomerOrderNotificationItem copyWith({
    DateTime? readAt,
  }) {
    return CustomerOrderNotificationItem(
      id: id,
      title: title,
      message: message,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      relatedType: relatedType,
      relatedOrderId: relatedOrderId,
    );
  }
}

class CustomerNotificationsResult {
  final List<CustomerOrderNotificationItem> items;
  final int unreadCount;

  const CustomerNotificationsResult({
    required this.items,
    required this.unreadCount,
  });
}

int? _parseIntLoose(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

/// Fetches customer notifications from GET /api/v1/notifications (paginated on the server).
/// Matches [ApiNotificationController]: `data` is a list, `meta` has pages, `unread_count` at root.
/// IDs may be negative (PHP `crc32` fallback when the Firestore doc id has no digits).
Future<CustomerNotificationsResult?> fetchCustomerOrderNotifications() async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  const perPage = 50;
  final headers = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  final notifications = <CustomerOrderNotificationItem>[];
  int? unreadCount;
  try {
    var page = 1;
    while (true) {
      final uri = Uri.parse('${Auth.apiBaseUrl}/notifications').replace(
        queryParameters: {
          'per_page': '$perPage',
          'page': '$page',
        },
      );
      final res = await http.get(uri, headers: headers);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      if (data['success'] != true) return null;

      if (unreadCount == null) {
        final u = data['unread_count'];
        if (u is int) {
          unreadCount = u;
        } else if (u is num) {
          unreadCount = u.toInt();
        } else {
          unreadCount = int.tryParse(u?.toString().trim() ?? '');
        }
      }

      final rawList = data['data'];
      final list = rawList is List<dynamic> ? rawList : <dynamic>[];

      for (final raw in list) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = _parseIntLoose(item['id']);
        if (id == null) continue;

        var title = (item['title'] ?? '').toString().trim();
        var message = (item['message'] ?? '').toString().trim();
        if (title.isEmpty && message.isEmpty) {
          final type = (item['type'] ?? '').toString().trim();
          title = type.isNotEmpty ? type : 'Notification';
        }

        final relatedIdRaw = item['related_id'];
        String? relatedOrderId;
        if (relatedIdRaw != null) {
          final s = relatedIdRaw.toString().trim();
          relatedOrderId = s.isEmpty ? null : s;
        }

        notifications.add(
          CustomerOrderNotificationItem(
            id: id,
            title: title,
            message: message,
            createdAt: _parseDateTimeMaybe(item['created_at']),
            readAt: _parseDateTimeMaybe(item['read_at']),
            relatedType: item['related_type']?.toString(),
            relatedOrderId: relatedOrderId,
          ),
        );
      }

      final meta = data['meta'];
      int lastPage = page;
      if (meta is Map) {
        final m = Map<String, dynamic>.from(meta);
        final lp = m['last_page'];
        if (lp is int) {
          lastPage = lp;
        } else if (lp is num) {
          lastPage = lp.toInt();
        } else {
          lastPage = int.tryParse(lp?.toString() ?? '') ?? page;
        }
      }
      if (page >= lastPage || list.length < perPage) break;
      page++;
    }
  } catch (_) {
    return null;
  }

  notifications.sort((a, b) {
    final aAt = a.createdAt;
    final bAt = b.createdAt;
    if (aAt == null && bAt == null) return b.id.compareTo(a.id);
    if (aAt == null) return 1;
    if (bAt == null) return -1;
    return bAt.compareTo(aAt);
  });
  final resolvedUnread = unreadCount ?? notifications.where((n) => !n.isRead).length;
  return CustomerNotificationsResult(items: notifications, unreadCount: resolvedUnread);
}

Future<bool> deleteAllCustomerNotifications() async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final res = await http.delete(
    Uri.parse('${Auth.apiBaseUrl}/notifications'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return false;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  return data != null && data['success'] == true;
}

Future<bool> markCustomerNotificationRead({required int notificationId}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final res = await http.post(
    Uri.parse('${Auth.apiBaseUrl}/notifications/$notificationId/read'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return false;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  return data != null && data['success'] == true;
}

/// DELETE /api/v1/notifications/{id}
Future<bool> deleteCustomerNotification({required int notificationId}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final res = await http.delete(
    Uri.parse('${Auth.apiBaseUrl}/notifications/$notificationId'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return false;
  try {
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return false;
  }
}

class OrderDetailsData {
  final String id;
  final String transactionId;
  final String productName;
  final String status;
  final String deliveryDate;
  final String deliveryTime;
  final String deliveryAddress;
  final String amountFormatted;
  final int quantity;
  final String paymentMethod;

  const OrderDetailsData({
    required this.id,
    required this.transactionId,
    required this.productName,
    required this.status,
    required this.deliveryDate,
    required this.deliveryTime,
    required this.deliveryAddress,
    required this.amountFormatted,
    required this.quantity,
    required this.paymentMethod,
  });

  factory OrderDetailsData.fromJson(Map<String, dynamic> json) {
    final amountRaw = (json['amount_formatted'] ?? '').toString().trim();
    final amount = amountRaw.isNotEmpty ? amountRaw : '₱${(json['amount'] ?? 0).toString()}';
    final qtyRaw = json['quantity'];
    final qty = qtyRaw is int ? qtyRaw : int.tryParse(qtyRaw?.toString() ?? '') ?? 1;
    return OrderDetailsData(
      id: json['id']?.toString().trim() ?? '',
      transactionId: (json['transaction_id'] ?? '').toString(),
      productName: (json['product_name'] ?? 'Order').toString(),
      status: (json['status'] ?? '').toString(),
      deliveryDate: (json['delivery_date'] ?? '').toString(),
      deliveryTime: (json['delivery_time'] ?? '').toString(),
      deliveryAddress: (json['delivery_address'] ?? '').toString(),
      amountFormatted: amount,
      quantity: qty,
      paymentMethod: (json['payment_method'] ?? '').toString(),
    );
  }
}

Future<OrderDetailsData?> fetchOrderDetailsById(String orderId) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  final res = await http.get(
    Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (data == null || data['success'] != true) return null;
  final order = data['data'] as Map<String, dynamic>?;
  return order == null ? null : OrderDetailsData.fromJson(order);
}

Future<List<OrderMessageItem>?> fetchOrderMessages({
  required String orderId,
  int perPage = 100,
}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  final uri = Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages')
      .replace(queryParameters: {'per_page': '$perPage'});
  final res = await http.get(
    uri,
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (res.statusCode != 200 || data == null || data['success'] != true) return null;
  final list = data['data'] as List<dynamic>?;
  if (list == null) return [];
  return list
      .whereType<Map>()
      .map((e) => OrderMessageItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

Future<OrderMessageItem?> sendOrderMessage({
  required String orderId,
  required String message,
}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return null;
  final res = await http.post(
    Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages'),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'message': message.trim()}),
  );
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (data == null || data['success'] != true) return null;
  final item = data['data'] as Map<String, dynamic>?;
  return item == null ? null : OrderMessageItem.fromJson(item);
}

Future<bool> markOrderMessagesRead({required String orderId}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final res = await http.post(
    Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages/read'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  return res.statusCode == 200;
}

/// Customer: archive all messages in this order thread (soft-delete; order_message.customer_status → archive).
Future<bool> archiveOrderMessages({required String orderId}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final uri = Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages/archive');
  final res = await http.post(
    uri,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode(<String, dynamic>{}),
  );
  if (res.statusCode != 200 && res.statusCode != 201) return false;
  try {
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return false;
  }
}

/// Customer: archive only the selected messages (order_message.customer_status → archive).
/// POST /api/v1/orders/{id}/messages/archive-selected with body: { "message_ids": [1, 2, 3] }
Future<bool> archiveSelectedOrderMessages({
  required String orderId,
  required List<int> messageIds,
}) async {
  if (messageIds.isEmpty) return true;
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final uri = Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages/archive-selected');
  final res = await http.post(
    uri,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'message_ids': messageIds}),
  );
  if (res.statusCode != 200 && res.statusCode != 201) return false;
  try {
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return false;
  }
}

/// Customer: restore archived messages in this order thread.
Future<bool> unarchiveOrderMessages({required String orderId}) async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return false;
  final res = await http.post(
    Uri.parse('${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/messages/unarchive'),
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  return res.statusCode == 200;
}

DateTime? _parseDateTimeMaybe(dynamic value) {
  final s = value?.toString();
  if (s == null || s.trim().isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String _pickFirstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = (v ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

String _extractDriverNameFromOrder(Map<String, dynamic> order) {
  String fullFromParts(Map<String, dynamic> src) {
    final first = _pickFirstNonEmpty([
      src['firstname'],
      src['first_name'],
      src['given_name'],
      src['driver_first_name'],
      src['assigned_driver_first_name'],
      src['rider_first_name'],
    ]);
    final last = _pickFirstNonEmpty([
      src['lastname'],
      src['last_name'],
      src['family_name'],
      src['driver_last_name'],
      src['assigned_driver_last_name'],
      src['rider_last_name'],
    ]);
    final full = '$first $last'.trim();
    return full;
  }

  final direct = _pickFirstNonEmpty([
    order['driver_name'],
    order['assigned_driver_name'],
    order['rider_name'],
    order['driver_full_name'],
    order['driver_display_name'],
  ]);
  if (direct.isNotEmpty) return direct;

  final nestedDriverRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
  if (nestedDriverRaw is Map) {
    final nested = Map<String, dynamic>.from(nestedDriverRaw);
    final nestedDirect = _pickFirstNonEmpty([
      nested['name'],
      nested['full_name'],
      nested['driver_name'],
      nested['display_name'],
    ]);
    if (nestedDirect.isNotEmpty) return nestedDirect;
    final fromParts = fullFromParts(nested);
    if (fromParts.isNotEmpty) return fromParts;
  }

  final fromTopParts = fullFromParts(order);
  if (fromTopParts.isNotEmpty) return fromTopParts;

  return '';
}

String _extractDriverContactFromOrder(Map<String, dynamic> order) {
  final direct = _pickFirstNonEmpty([
    order['driver_phone'],
    order['driver_contact'],
    order['assigned_driver_phone'],
    order['assigned_driver_contact'],
    order['rider_phone'],
    order['rider_contact'],
  ]);
  if (direct.isNotEmpty) return direct;

  final nestedDriverRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
  if (nestedDriverRaw is Map) {
    final nested = Map<String, dynamic>.from(nestedDriverRaw);
    final nestedContact = _pickFirstNonEmpty([
      nested['contact_no'],
      nested['contact_number'],
      nested['phone'],
      nested['mobile'],
      nested['mobile_number'],
    ]);
    if (nestedContact.isNotEmpty) return nestedContact;
  }

  return '';
}

String _extractDriverGroupKeyFromOrder(Map<String, dynamic> order, String fallbackName) {
  final directId = _pickFirstNonEmpty([
    order['driver_id'],
    order['assigned_driver_id'],
    order['rider_id'],
  ]);
  if (directId.isNotEmpty) return 'id:$directId';

  final nestedDriverRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
  if (nestedDriverRaw is Map) {
    final nested = Map<String, dynamic>.from(nestedDriverRaw);
    final nestedId = _pickFirstNonEmpty([
      nested['id'],
      nested['driver_id'],
      nested['user_id'],
      nested['account_id'],
    ]);
    if (nestedId.isNotEmpty) return 'id:$nestedId';
    final nestedPhone = _pickFirstNonEmpty([
      nested['phone'],
      nested['mobile'],
      nested['contact_number'],
    ]);
    if (nestedPhone.isNotEmpty) return 'phone:$nestedPhone';
  }

  final fallback = fallbackName.trim().toLowerCase();
  if (fallback.isNotEmpty) return 'name:$fallback';
  return 'order:${order['id'] ?? ''}';
}

/// Fetches driver chat threads. Only includes orders that have at least one active message
/// (customer_status = active). Threads with no active messages or all archived are hidden.
Future<List<DriverOrderThread>> fetchDriverOrderThreads() async {
  final token = await Auth.getApiToken();
  if (token == null || token.isEmpty) return [];
  final uri = Uri.parse('${Auth.apiBaseUrl}/orders').replace(
    queryParameters: {
      'status': 'all',
      'for_driver_chats': '1', // backend: only orders with ≥1 active message (or no messages)
    },
  );
  final res = await http.get(
    uri,
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );
  final data = jsonDecode(res.body) as Map<String, dynamic>?;
  if (res.statusCode != 200 || data == null) return [];
  final list = data['data'] as List<dynamic>? ?? [];
  final grouped = <String, DriverOrderThread>{};

  for (final raw in list.whereType<Map>()) {
    final order = Map<String, dynamic>.from(raw);
    final rawDriverId = (order['driver_id'] ?? '').toString().trim();
    if (rawDriverId.isEmpty || rawDriverId == '0' || rawDriverId == 'null') {
      // Skip orders without an assigned driver; they usually show generic "Driver".
      continue;
    }
    final orderId = (order['id'] ?? '').toString().trim();
    if (orderId.isEmpty) continue;

    var driverName = _extractDriverNameFromOrder(order);
    if (driverName.isEmpty) driverName = 'Driver';
    final driverContact = _extractDriverContactFromOrder(order);
    final transactionId = (order['transaction_id'] ?? 'Order #$orderId').toString();
    final orderLabel = (order['product_name'] ?? order['product_type'] ?? 'Order').toString();
    // Prefer newest active order message from API (`latest_message`) for preview + time,
    // falling back to order timestamps and legacy preview fields.
    String latestText = '';
    DateTime? latestAt;
    final latestRaw = order['latest_message'];
    if (latestRaw is Map) {
      final latestMap = Map<String, dynamic>.from(latestRaw);
      latestText = (latestMap['message'] ?? '').toString().trim();
      latestAt = _parseDateTimeMaybe(latestMap['created_at']);
    }
    final fallbackLastAt = _parseDateTimeMaybe(order['updated_at']) ??
        _parseDateTimeMaybe(order['created_at']) ??
        _parseDateTimeMaybe(order['delivery_date']);
    final lastAt = latestAt ?? fallbackLastAt;
    final preview = latestText.isNotEmpty
        ? latestText
        : _pickFirstNonEmpty([
            order['last_message'],
            order['last_message_text'],
            order['message_preview'],
          ]);
    final effectivePreview = preview.isNotEmpty ? preview : '';
    final key = _extractDriverGroupKeyFromOrder(order, driverName);
    final existing = grouped[key];
    if (existing == null) {
      grouped[key] = DriverOrderThread(
        orderId: orderId,
        relatedOrderIds: [orderId],
        driverName: driverName,
        driverContact: driverContact,
        transactionId: transactionId,
        orderLabel: orderLabel,
        preview: effectivePreview,
        lastAt: lastAt,
      );
      continue;
    }

    final mergedIds = <String>{...existing.relatedOrderIds, existing.orderId, orderId}.toList();
    final existingAt = existing.lastAt;
    final takeNewer = existingAt == null || (lastAt != null && lastAt.isAfter(existingAt));
    grouped[key] = DriverOrderThread(
      orderId: takeNewer ? orderId : existing.orderId,
      relatedOrderIds: mergedIds,
      driverName: existing.driverName.isNotEmpty ? existing.driverName : driverName,
      driverContact: existing.driverContact.isNotEmpty ? existing.driverContact : driverContact,
      transactionId: takeNewer ? transactionId : existing.transactionId,
      orderLabel: takeNewer ? orderLabel : existing.orderLabel,
      preview: takeNewer ? effectivePreview : existing.preview,
      lastAt: takeNewer ? lastAt : existing.lastAt,
    );
  }

  var threads = grouped.values.toList();
  threads.sort((a, b) {
    final aAt = a.lastAt;
    final bAt = b.lastAt;
    if (aAt == null && bAt == null) return b.orderId.compareTo(a.orderId);
    if (aAt == null) return 1;
    if (bAt == null) return -1;
    return bAt.compareTo(aAt);
  });

  // Hide threads with no active messages (all archived or empty).
  // Keep thread when API returns null (don't hide on network/auth error). Only hide when we
  // get a successful empty response (no active messages).
  final withActive = await Future.wait(
    threads.map((t) => fetchOrderMessages(orderId: t.orderId, perPage: 1)),
  );
  threads = [
    for (var i = 0; i < threads.length; i++)
      if (withActive[i] == null || withActive[i]!.isNotEmpty) threads[i],
  ];

  return threads;
}

String formatMessageTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(dt.year, dt.month, dt.day);
  if (msgDate == today) {
    return DateFormat.jm().format(dt);
  }
  final yesterday = today.subtract(const Duration(days: 1));
  if (msgDate == yesterday) {
    return 'Yesterday ${DateFormat.jm().format(dt)}';
  }
  return DateFormat.yMMMd().add_jm().format(dt);
}

String formatMessageTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat.yMMMd().format(dt);
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int selectedTab = 0; // 0 = Chats, 1 = Notifications
  ChatSummary? _chatSummary;
  bool _chatLoading = true;
  String? _chatError;
  List<DriverOrderThread> _driverThreads = [];
  bool _driverLoading = true;
  String? _driverError;
  bool _chatRefreshInFlight = false;
  bool _driverRefreshInFlight = false;
  List<CustomerOrderNotificationItem> _notifications = [];
  int _notifUnreadCount = 0;
  bool _notifLoading = true;
  String? _notifError;
  bool _notifRefreshInFlight = false;
  /// Selection mode for driver chats: long-press to select threads for delete (archive).
  bool _driverSelectionMode = false;
  final Set<String> _selectedDriverOrderIds = {};
  bool _notifSelectionMode = false;
  final Set<int> _selectedNotificationIds = {};

  LastUpdatedRtdbListener? _customerNotifRtdb;
  LastUpdatedRtdbListener? _customerChatRtdb;
  final Map<String, LastUpdatedRtdbListener> _orderMsgsRtdb = {};
  int? _rtdbCustomerId;

  @override
  void initState() {
    super.initState();
    _loadChatSummary();
    _loadDriverThreads();
    _loadNotifications();
    _attachCustomerRtdbListeners();
  }

  @override
  void dispose() {
    _customerNotifRtdb?.dispose();
    _customerChatRtdb?.dispose();
    for (final l in _orderMsgsRtdb.values) {
      l.dispose();
    }
    _orderMsgsRtdb.clear();
    super.dispose();
  }

  Future<void> _attachCustomerRtdbListeners() async {
    final id = await resolveCustomerId();
    if (!mounted || id == null) return;
    _rtdbCustomerId = id;
    final db = firebaseRtdb();

    _customerNotifRtdb?.dispose();
    _customerNotifRtdb = LastUpdatedRtdbListener(
      database: db,
      path: 'notifications/$id/last_updated',
      debounce: const Duration(milliseconds: 450),
      onTick: () {
        if (!mounted) return;
        _refreshNotificationsSilent();
      },
    )..start();

    _customerChatRtdb?.dispose();
    _customerChatRtdb = LastUpdatedRtdbListener(
      database: db,
      path: 'chats/$id/last_updated',
      debounce: const Duration(milliseconds: 450),
      onTick: () {
        if (!mounted) return;
        _refreshChatSummarySilent();
      },
    )..start();

    _syncOrderMessageRtdbListeners();
  }

  void _syncOrderMessageRtdbListeners() {
    if (_rtdbCustomerId == null || _rtdbCustomerId! <= 0) return;
    final db = firebaseRtdb();
    final ids = _driverThreads.map((t) => t.orderId).where((id) => id.isNotEmpty).take(30).toSet();
    for (final oid in _orderMsgsRtdb.keys.toList()) {
      if (!ids.contains(oid)) {
        _orderMsgsRtdb.remove(oid)?.dispose();
      }
    }
    for (final oid in ids) {
      if (_orderMsgsRtdb.containsKey(oid)) continue;
      _orderMsgsRtdb[oid] = LastUpdatedRtdbListener(
        database: db,
        path: 'order_messages/$oid/last_updated',
        debounce: const Duration(milliseconds: 500),
        onTick: () {
          if (!mounted) return;
          _refreshDriverThreadsSilent();
          _hydrateDriverThreadLatestMessages();
        },
      )..start();
    }
  }

  bool _isSameSummary(ChatSummary? a, ChatSummary? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.unreadCount != b.unreadCount) return false;
    final aLast = a.lastMessage;
    final bLast = b.lastMessage;
    if (aLast == null && bLast == null) return true;
    if (aLast == null || bLast == null) return false;
    return aLast.id == bLast.id &&
        aLast.body == bLast.body &&
        aLast.imageUrl == bLast.imageUrl &&
        aLast.createdAt == bLast.createdAt;
  }

  bool _isSameDriverThreads(List<DriverOrderThread> a, List<DriverOrderThread> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.orderId != y.orderId ||
          x.driverName != y.driverName ||
          x.transactionId != y.transactionId ||
          x.orderLabel != y.orderLabel ||
          x.preview != y.preview ||
          x.lastAt != y.lastAt ||
          x.unreadCount != y.unreadCount) {
        return false;
      }
    }
    return true;
  }

  bool _isSameNotifications(
    List<CustomerOrderNotificationItem> a,
    List<CustomerOrderNotificationItem> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.title != y.title ||
          x.message != y.message ||
          x.createdAt != y.createdAt ||
          x.readAt != y.readAt) {
        return false;
      }
    }
    return true;
  }

  /// Delete: Chats — at least one driver thread selected; Notifications — selected items in selection mode, else delete-all when list non-empty.
  bool get _isDeleteEnabled {
    if (selectedTab == 0) return _selectedDriverOrderIds.isNotEmpty;
    if (_notifSelectionMode) return _selectedNotificationIds.isNotEmpty;
    return _notifications.isNotEmpty;
  }

  /// Number of conversations (chats) with unread messages, for the Chats tab badge.
  int get _chatUnreadCount {
    int count = 0;
    if ((_chatSummary?.unreadCount ?? 0) > 0) count += 1;
    for (final t in _driverThreads) {
      if (t.unreadCount > 0) count += 1;
    }
    return count;
  }

  void _exitDriverSelectionMode() {
    setState(() {
      _driverSelectionMode = false;
      _selectedDriverOrderIds.clear();
    });
  }

  void _exitNotifSelectionMode() {
    setState(() {
      _notifSelectionMode = false;
      _selectedNotificationIds.clear();
    });
  }

  void _onNotificationLongPress(CustomerOrderNotificationItem item) {
    setState(() {
      _notifSelectionMode = true;
      _selectedNotificationIds.add(item.id);
    });
  }

  void _onNotificationTap(CustomerOrderNotificationItem item) {
    if (_notifSelectionMode) {
      setState(() {
        if (_selectedNotificationIds.contains(item.id)) {
          _selectedNotificationIds.remove(item.id);
          if (_selectedNotificationIds.isEmpty) _notifSelectionMode = false;
        } else {
          _selectedNotificationIds.add(item.id);
        }
      });
      return;
    }
    _openNotificationOrder(item);
  }

  Future<bool> _deleteSelectedNotifications() async {
    final ids = _selectedNotificationIds.toList();
    var allOk = true;
    for (final id in ids) {
      final ok = await deleteCustomerNotification(notificationId: id);
      if (!ok) allOk = false;
    }
    if (mounted) {
      _exitNotifSelectionMode();
      await _loadNotifications();
    }
    return allOk;
  }

  void _onDriverThreadLongPress(DriverOrderThread thread) {
    setState(() {
      _driverSelectionMode = true;
      _selectedDriverOrderIds.add(thread.orderId);
    });
  }

  void _onDriverThreadTap(DriverOrderThread thread) {
    if (_driverSelectionMode) {
      setState(() {
        if (_selectedDriverOrderIds.contains(thread.orderId)) {
          _selectedDriverOrderIds.remove(thread.orderId);
          if (_selectedDriverOrderIds.isEmpty) _driverSelectionMode = false;
        } else {
          _selectedDriverOrderIds.add(thread.orderId);
        }
      });
      return;
    }
    // Normal tap: open chat
    _openDriverChat(thread);
  }

  Future<void> _openDriverChat(DriverOrderThread thread) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverOrderChatPage(
          orderId: thread.orderId,
          relatedOrderIds: thread.relatedOrderIds,
          driverName: thread.driverName,
          driverContact: thread.driverContact,
          orderLabel: thread.orderLabel,
        ),
      ),
    );
    if (mounted) _refreshDriverThreadsSilent();
  }

  Future<void> _archiveSelectedDriverThreads() async {
    final orderIds = _selectedDriverOrderIds.toList();
    for (final orderId in orderIds) {
      await archiveOrderMessages(orderId: orderId);
    }
    if (mounted) {
      _exitDriverSelectionMode();
      await _loadDriverThreads();
    }
  }

  /// Initial load: shows loading indicator.
  Future<void> _loadChatSummary() async {
    if (_chatRefreshInFlight) return;
    _chatRefreshInFlight = true;
    setState(() {
      _chatLoading = true;
      _chatError = null;
    });
    try {
      final summary = await fetchChatSummary();
      if (mounted) {
        final changed = !_isSameSummary(_chatSummary, summary);
        if (changed || _chatLoading || _chatError != null) {
          setState(() {
            _chatSummary = summary;
            _chatLoading = false;
            _chatError = null;
          });
        } else {
          _chatLoading = false;
          _chatError = null;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatLoading = false;
          _chatError = e.toString();
        });
      }
    } finally {
      _chatRefreshInFlight = false;
    }
  }

  /// Subtitle under "Chat with H&R Ice Cream" — always shown so users can open support.
  String _supportChatSubtitle() {
    final last = _chatSummary?.lastMessage;
    if (last != null) {
      final body = last.body?.trim();
      if (body != null && body.isNotEmpty) return body;
      final img = last.imageUrl?.trim();
      if (img != null && img.isNotEmpty) return 'Photo';
    }
    if ((_chatSummary?.unreadCount ?? 0) > 0) {
      return 'You have new messages.';
    }
    return 'Tap to start a conversation';
  }

  /// Real-time background refresh: no loading spinner, only updates data when changed.
  Future<void> _refreshChatSummarySilent() async {
    if (_chatRefreshInFlight) return;
    _chatRefreshInFlight = true;
    try {
      final summary = await fetchChatSummary();
      if (mounted) {
        final changed = !_isSameSummary(_chatSummary, summary);
        if (changed || _chatError != null) {
          setState(() {
            _chatSummary = summary;
            _chatError = null;
          });
        }
      }
    } catch (_) {
      // Keep previous state on silent refresh failure
    } finally {
      _chatRefreshInFlight = false;
    }
  }

  Future<void> _loadDriverThreads() async {
    if (_driverRefreshInFlight) return;
    _driverRefreshInFlight = true;
    setState(() {
      _driverLoading = true;
      _driverError = null;
    });
    try {
      final threads = await fetchDriverOrderThreads();
      if (mounted) {
        final changed = !_isSameDriverThreads(_driverThreads, threads);
        if (changed || _driverLoading || _driverError != null) {
          setState(() {
            _driverThreads = threads;
            _driverLoading = false;
            _driverError = null;
          });
        } else {
          _driverLoading = false;
          _driverError = null;
        }
      }
      _hydrateDriverThreadLatestMessages();
      _syncOrderMessageRtdbListeners();
    } catch (e) {
      if (mounted) {
        setState(() {
          _driverLoading = false;
          _driverError = e.toString();
        });
      }
    } finally {
      _driverRefreshInFlight = false;
    }
  }

  int _computeDriverThreadUnread(List<OrderMessageItem> messages) {
    if (messages.isEmpty) return 0;
    int lastCustomerIdx = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].isMine) lastCustomerIdx = i;
    }
    int unread = 0;
    for (var i = lastCustomerIdx + 1; i < messages.length; i++) {
      if (!messages[i].isMine) unread++;
    }
    return unread;
  }

  Future<void> _hydrateDriverThreadLatestMessages() async {
    if (!mounted) return;
    final current = List<DriverOrderThread>.from(_driverThreads);
    if (current.isEmpty) return;

    // Limit calls to keep the page responsive on large lists.
    final targets = current.where((t) => t.orderId.isNotEmpty).take(10).toList();
    if (targets.isEmpty) return;
    final latestByOrder = <String, OrderMessageItem>{};
    final unreadByOrder = <String, int>{};

    await Future.wait(targets.map((t) async {
      final list = await fetchOrderMessages(orderId: t.orderId, perPage: 100);
      if (list != null && list.isNotEmpty) {
        latestByOrder[t.orderId] = list.last;
        unreadByOrder[t.orderId] = _computeDriverThreadUnread(list);
      }
    }));

    if (!mounted) return;
    final updated = current.map((t) {
      final latest = latestByOrder[t.orderId];
      final unread = unreadByOrder[t.orderId] ?? 0;
      if (latest == null && unread == 0) return t;
      final msg = latest?.message.trim() ?? '';
      return t.copyWith(
        preview: msg.isNotEmpty ? msg : (t.preview ?? ''),
        lastAt: latest?.createdAt ?? t.lastAt,
        unreadCount: unread,
      );
    }).toList();

    final changed = !_isSameDriverThreads(_driverThreads, updated);
    if (changed && mounted) {
      setState(() => _driverThreads = updated);
    }
  }

  Future<void> _refreshDriverThreadsSilent() async {
    if (_driverRefreshInFlight) return;
    _driverRefreshInFlight = true;
    try {
      final threads = await fetchDriverOrderThreads();
      if (mounted) {
        final changed = !_isSameDriverThreads(_driverThreads, threads);
        if (changed || _driverError != null) {
          setState(() {
            _driverThreads = threads;
            _driverError = null;
          });
        }
        // Hydrate previews (latest message text) when returning from a chat
        _hydrateDriverThreadLatestMessages();
        _syncOrderMessageRtdbListeners();
      }
    } catch (_) {
    } finally {
      _driverRefreshInFlight = false;
    }
  }

  Future<void> _loadNotifications() async {
    if (_notifRefreshInFlight) return;
    _notifRefreshInFlight = true;
    setState(() {
      _notifLoading = true;
      _notifError = null;
    });
    try {
      final result = await fetchCustomerOrderNotifications();
      if (mounted) {
        final next = result?.items ?? <CustomerOrderNotificationItem>[];
        final unread = result?.unreadCount ?? next.where((n) => !n.isRead).length;
        final changed = !_isSameNotifications(_notifications, next);
        setState(() {
          if (changed || _notifLoading || _notifError != null) {
            _notifications = next;
          }
          _notifUnreadCount = unread;
          _notifLoading = false;
          _notifError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notifLoading = false;
          _notifError = e.toString();
        });
      }
    } finally {
      _notifRefreshInFlight = false;
    }
  }

  /// Background refresh when RTDB `notifications/{customerId}/last_updated` changes.
  Future<void> _refreshNotificationsSilent() async {
    if (_notifRefreshInFlight) return;
    _notifRefreshInFlight = true;
    try {
      final result = await fetchCustomerOrderNotifications();
      if (!mounted) return;
      final next = result?.items ?? <CustomerOrderNotificationItem>[];
      final unread = result?.unreadCount ?? next.where((n) => !n.isRead).length;
      final changed = !_isSameNotifications(_notifications, next);
      if (changed || _notifError != null) {
        setState(() {
          _notifications = next;
          _notifUnreadCount = unread;
          _notifError = null;
        });
      } else {
        setState(() => _notifUnreadCount = unread);
      }
    } catch (_) {
      // keep existing list on silent failure
    } finally {
      _notifRefreshInFlight = false;
    }
  }

  Future<void> _openNotificationOrder(CustomerOrderNotificationItem item) async {
    if (!item.isRead) {
      final ok = await markCustomerNotificationRead(notificationId: item.id);
      if (ok && mounted) {
        setState(() {
          _notifications = _notifications.map((n) {
            if (n.id == item.id) return n.copyWith(readAt: DateTime.now());
            return n;
          }).toList();
          _notifUnreadCount = (_notifUnreadCount - 1).clamp(0, 999999);
        });
      }
    }

    final relatedType = (item.relatedType ?? '').toLowerCase();
    final orderId = item.relatedOrderId;
    if (relatedType != 'order' || orderId == null || orderId.isEmpty) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationOrderDetailsPage(orderId: orderId),
      ),
    );
    if (mounted) await _loadNotifications();
  }

  Widget _buildNotificationsUnreadBadge() {
    if (_notifUnreadCount <= 0) return const SizedBox.shrink();
    final text = _notifUnreadCount > 99 ? '99+' : '$_notifUnreadCount';
    final isWide = text.length >= 3;
    final isNotificationsActive = selectedTab == 1;
    final badgeBg = isNotificationsActive ? Colors.white : const Color(0xFFE3001B);
    final textColor = isNotificationsActive ? const Color(0xFFE3001B) : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 6 : 5,
        vertical: 1,
      ),
      constraints: BoxConstraints(
        minWidth: isWide ? 22 : 18,
        minHeight: 18,
      ),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isNotificationsActive ? const Color(0xFFE3001B) : const Color(0xFFFFD0D6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildChatsUnreadBadge() {
    final count = _chatUnreadCount;
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    final isWide = text.length >= 3;
    final isChatsActive = selectedTab == 0;
    final badgeBg = isChatsActive ? Colors.white : const Color(0xFFE3001B);
    final textColor = isChatsActive ? const Color(0xFFE3001B) : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 6 : 5,
        vertical: 1,
      ),
      constraints: BoxConstraints(
        minWidth: isWide ? 22 : 18,
        minHeight: 18,
      ),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isChatsActive ? const Color(0xFFE3001B) : const Color(0xFFFFD0D6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      bottomNavigationBar: _bottomNavBar(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),
            // ---------------- TOP BAR ----------------
   Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      (_driverSelectionMode || _notifSelectionMode)
          ? TextButton(
              onPressed: () {
                if (_driverSelectionMode) _exitDriverSelectionMode();
                if (_notifSelectionMode) _exitNotifSelectionMode();
              },
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFE3001B))),
            )
          : const Text(
              "Messages",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
            ),
      IconButton(
        icon: Icon(
          Symbols.delete,
          size: 25,
          color: _isDeleteEnabled ? Colors.black : Colors.black38,
          fill: 0,
          weight: 200,
          grade: 200,
          opticalSize: 24,
        ),
        onPressed: _isDeleteEnabled ? _showDeleteAllModal : null,
      ),
    ],
  ),
),

            const SizedBox(height: 10),

            // ---------------- TABS ----------------
            Row(
              children: [
                const SizedBox(width: 20),

                // Chats tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      selectedTab = 0;
                      _notifSelectionMode = false;
                      _selectedNotificationIds.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selectedTab == 0
                            ? const Color(0xFFE3001B)
                            : const Color(0xFFFCE8E9), // inactive bg
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Text(
                              "Chats",
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedTab == 0
                                    ? Colors.white
                                    : const Color(0xFF1C1B1F), // inactive text
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          if (_chatUnreadCount > 0)
                            Positioned(
                              top: -4,
                              right: 6,
                              child: _buildChatsUnreadBadge(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Notifications tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      selectedTab = 1;
                      _driverSelectionMode = false;
                      _selectedDriverOrderIds.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ), // add horizontal padding
                      decoration: BoxDecoration(
                        color: selectedTab == 1
                            ? const Color(0xFFE3001B)
                            : const Color(0xFFFCE8E9),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Slightly left-shifted Text
                          Align(
                            alignment: Alignment.center,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: 10,
                              ), // moves text a bit to the left
                              child: Text(
                                "Notifications",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: selectedTab == 1
                                      ? Colors.white
                                      : const Color(0xFF1C1B1F),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                          if (_notifUnreadCount > 0)
                            Positioned(
                              top: -4,
                              right: 6,
                              child: _buildNotificationsUnreadBadge(),
                            ),

                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 20),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (selectedTab == 0) {
                    await Future.wait<void>([
                      _loadChatSummary(),
                      _loadDriverThreads(),
                    ]);
                  } else {
                    await _loadNotifications();
                  }
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (selectedTab == 0) ...[
                      // One centered loader while admin chat or driver threads loads (avoid stacked spinners).
                      if (_chatLoading || _driverLoading)
                        Builder(
                          builder: (context) {
                            final screenH = MediaQuery.sizeOf(context).height;
                            final loaderHeight =
                                (screenH - 260.0).clamp(240.0, 560.0);
                            return SizedBox(
                              height: loaderHeight,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                        )
                      else ...[
                        // ----------------- CHATS (real API: single Admin chat) -----------------
                        if (_chatError != null)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  _chatError!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _loadChatSummary,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ChatPage(),
                                ),
                              );
                              if (mounted) _refreshChatSummarySilent();
                            },
                            child: messageCard(
                              icon: Icons.support_agent,
                              name: 'Chat with H&R Ice Cream',
                              message: _supportChatSubtitle(),
                              time: _chatSummary?.lastMessage != null
                                  ? formatMessageTimeAgo(
                                      _chatSummary!.lastMessage!.createdAt,
                                    )
                                  : '',
                              unreadCount: _chatSummary?.unreadCount ?? 0,
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (_driverError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Text(
                                  _driverError!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _loadDriverThreads,
                                  child: const Text('Retry Driver Chats'),
                                ),
                              ],
                            ),
                          )
                        else if (_driverThreads.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Driver Chats',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1B1F),
                                ),
                              ),
                            ),
                          ),
                          ..._driverThreads.map((thread) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onLongPress: () => _onDriverThreadLongPress(thread),
                                        onTap: () => _onDriverThreadTap(thread),
                                        child: messageCard(
                                          icon: Icons.person,
                                          name: thread.driverName,
                                          message: thread.preview ?? '',
                                          time: thread.lastAt != null
                                              ? formatMessageTimeAgo(thread.lastAt!)
                                              : '',
                                          isSelectionMode: _driverSelectionMode,
                                          isSelected: _selectedDriverOrderIds.contains(thread.orderId),
                                          unreadCount: thread.unreadCount,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                        const SizedBox(height: 10),
                      ],
                    ] else ...[
                      if (_notifLoading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_notifError != null)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                _notifError!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loadNotifications,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      else if (_notifications.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              'Notifications will appear here.',
                              style: TextStyle(color: Color(0xFF747474)),
                            ),
                          ),
                        )
                      else ...[
                        ..._notifications.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final notifText = item.title.isNotEmpty
                              ? '${item.title}: ${item.message}'
                              : item.message;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 13),
                            child: GestureDetector(
                              onLongPress: () => _onNotificationLongPress(item),
                              onTap: () => _onNotificationTap(item),
                              child: notificationCard(
                                message: notifText,
                                time: item.createdAt != null
                                    ? formatMessageTimeAgo(item.createdAt!)
                                    : '',
                                isFirst: index == 0,
                                isUnread: !item.isRead,
                                isSelectionMode: _notifSelectionMode,
                                isSelected: _selectedNotificationIds.contains(item.id),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Blocks interaction with a loading indicator until [job] completes (success or failure).
  Future<void> _runWithDeletingOverlay(Future<void> Function() job) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text(
                  'Deleting…',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1B1F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await job();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _showDeleteAllModal() {
    final driverCount = _selectedDriverOrderIds.length;
    final bool driverSingle = driverCount == 1;
    final int notifSel = _selectedNotificationIds.length;

    late final String title;
    late final String deleteButtonLabel;
    if (selectedTab == 0) {
      title = driverSingle ? "Delete selected message?" : "Delete all messages?";
      deleteButtonLabel = driverSingle ? "Delete" : "Delete All";
    } else if (_notifSelectionMode && notifSel > 0) {
      title = notifSel == 1
          ? "Delete this notification?"
          : "Delete $notifSel notifications?";
      deleteButtonLabel = "Delete";
    } else {
      title = "Delete all notifications?";
      deleteButtonLabel = "Delete All";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(35),
              topRight: Radius.circular(35),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1B1F),
                ),
              ),

              const SizedBox(height: 5),

              // Subtitle
              const Text(
                "You can't undo this later.",
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 30),

              // DELETE / DELETE ALL button
              GestureDetector(
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _runWithDeletingOverlay(() async {
                    if (selectedTab == 0 && _selectedDriverOrderIds.isNotEmpty) {
                      await _archiveSelectedDriverThreads();
                    }
                    if (selectedTab == 1) {
                      if (_notifSelectionMode && _selectedNotificationIds.isNotEmpty) {
                        final ok = await _deleteSelectedNotifications();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Notification(s) deleted successfully.'
                                  : 'Some notifications could not be deleted.',
                            ),
                          ),
                        );
                      } else {
                        final ok = await deleteAllCustomerNotifications();
                        if (!mounted) return;
                        if (ok) {
                          await _loadNotifications();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('All notifications deleted successfully.')),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to delete notifications.')),
                          );
                        }
                      }
                    }
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3001B),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    deleteButtonLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // KEEP THEM button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    "Keep Them",
                    style: TextStyle(
                      color: Color(0xFF414141),
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ---------------- BOTTOM NAV BAR ----------------
  Widget _bottomNavBar(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      elevation: 0,
      child: SizedBox(
        height: 65,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomIcon(
              icon: Symbols.home,
              label: "Home",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                );
              },
            ),
            _BottomIcon(
              icon: Symbols.local_mall,
              label: "Order",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderHistoryPage()),
                );
              },
            ),
            _BottomIcon(
              icon: Symbols.favorite,
              label: "Favorite",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FavoritePage()),
                );
              },
            ),
            _BottomIcon(
              icon: Symbols.chat,
              label: "Messages",
              active: true,
              onTap: () {},
              fillColor: const Color(0xFFE3001B),
            ),
          ],
        ),
      ),
    );
  }

  Widget messageCard({
    required IconData icon,
    required String name,
    required String message,
    required String time,
    bool isSelectionMode = false,
    bool isSelected = false,
    int unreadCount = 0,
  })

{
  // Determine icon, size, fill, and padding based on passed icon
  IconData displayedIcon;
  double iconSize;
  double containerPadding;

  // Material Symbols variations
  double iconFill;
  double iconWeight;
  double iconGrade;
  double iconOpticalSize;

  if (icon == Icons.person) {
    // ✅ Person in Material Symbols style (FILL 1, wght 700, GRAD 200, opsz 24)
    displayedIcon = Symbols.person;
    iconSize = 22;
    containerPadding = 14;

    iconFill = 1;
    iconWeight = 600;
    iconGrade = 200;
    iconOpticalSize = 24;
  } else {
    displayedIcon = Symbols.nest_mini;
    iconSize = 24;
    containerPadding = 12;

    // keep your other icon style (adjust if you want)
    iconFill = 1;
    iconWeight = 600;
    iconGrade = 0;
    iconOpticalSize = 24;
  }

  return Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(11),
          border: isSelectionMode && isSelected
              ? Border.all(color: const Color(0xFFE3001B), width: 2)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSelectionMode) ...[
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  isSelected ? Symbols.check_circle : Symbols.radio_button_unchecked,
                  size: 24,
                  color: isSelected ? const Color(0xFFE3001B) : Colors.grey,
                  fill: isSelected ? 1 : 0,
                ),
              ),
            ],
            Transform.translate(
              offset: const Offset(-4, 0),
              child: Container(
                padding: EdgeInsets.all(containerPadding),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE7EA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  displayedIcon,
                  size: iconSize,
                  color: const Color(0xFFE3001B),

                  // ✅ Material Symbols variations (matches your CSS)
                  fill: iconFill,
                  weight: iconWeight,
                  grade: iconGrade,
                  opticalSize: iconOpticalSize,
                ),
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1C1B1F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        time,
                        style: const TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (unreadCount > 0)
        Positioned(
          top: 4,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE3001B),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            alignment: Alignment.center,
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}

  Widget notificationCard({
    required String message,
    required String time,
    bool isFirst = false,
    bool isUnread = false,
    bool isSelectionMode = false,
    bool isSelected = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isUnread && !isSelectionMode ? const Color(0xFFFFF6F6) : Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: isSelectionMode && isSelected
            ? Border.all(color: const Color(0xFFE3001B), width: 2)
            : null,
        boxShadow: isFirst
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (isSelectionMode) ...[
      Padding(
        padding: const EdgeInsets.only(right: 10, top: 2),
        child: Icon(
          isSelected ? Symbols.check_circle : Symbols.radio_button_unchecked,
          size: 24,
          color: isSelected ? const Color(0xFFE3001B) : Colors.grey,
          fill: isSelected ? 1 : 0,
        ),
      ),
    ],
    Transform.translate(
      offset: const Offset(-4, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: Color(0xFFFFE7EA),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Symbols.notifications_active,
          size: 22,
          color: Color(0xFFE3001B),

          // ✅ matches your CSS
          fill: 1,
          weight: 600,
          grade: 0,
          opticalSize: 24,
        ),
      ),
    ),

    const SizedBox(width: 10),

    Expanded(
      child: SizedBox(
        height: 52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF1C1B1F),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ],
),
    );
  }
}

class _BottomIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? fillColor; // New parameter for custom fill color

  const _BottomIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.fillColor, // Allow fillColor to be passed
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = active ? Color(0xFFE3001B) : const Color(0xFF969696);
    final double fillValue = (active && fillColor != null) ? 1 : 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 21,
              color: fillColor != null && active ? fillColor : iconColor,
              fill: fillValue,
              weight: 100,
              grade: 200,
              opticalSize: 24,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: iconColor,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationOrderDetailsPage extends StatefulWidget {
  final String orderId;

  const NotificationOrderDetailsPage({
    super.key,
    required this.orderId,
  });

  @override
  State<NotificationOrderDetailsPage> createState() => _NotificationOrderDetailsPageState();
}

class _NotificationOrderDetailsPageState extends State<NotificationOrderDetailsPage> {
  bool _loading = true;
  String? _error;
  OrderDetailsData? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await fetchOrderDetailsById(widget.orderId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _loading = false;
          _error = 'Order details not found.';
        });
        return;
      }
      setState(() {
        _order = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _label(String raw) {
    final s = raw.replaceAll('_', ' ').trim();
    if (s.isEmpty) return '—';
    return s[0].toUpperCase() + s.substring(1);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF747474),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: const TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F8F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _order == null
                  ? const Center(child: Text('Order details not found.'))
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Order ID', '#${_order!.id}'),
                              _row('Transaction', _order!.transactionId),
                              _row('Product', _order!.productName),
                              _row('Status', _label(_order!.status)),
                              _row('Quantity', _order!.quantity.toString()),
                              _row('Amount', _order!.amountFormatted),
                              _row('Payment', _order!.paymentMethod),
                              _row('Delivery date', _order!.deliveryDate),
                              _row('Delivery time', _order!.deliveryTime),
                              _row('Delivery address', _order!.deliveryAddress),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const double avatarRadius = 22;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessageItem> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  LastUpdatedRtdbListener? _supportChatRtdb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages();
    markChatRead();
    _attachSupportChatRtdb();
  }

  @override
  void dispose() {
    _supportChatRtdb?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _attachSupportChatRtdb() async {
    final id = await resolveCustomerId();
    if (!mounted || id == null) return;
    _supportChatRtdb?.dispose();
    _supportChatRtdb = LastUpdatedRtdbListener(
      database: firebaseRtdb(),
      path: 'chats/$id/last_updated',
      debounce: const Duration(milliseconds: 450),
      onTick: () {
        if (!mounted) return;
        _loadMessages(silent: true);
      },
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await fetchChatMessages(perPage: 100);
      if (mounted) {
        setState(() {
          _messages = list ?? [];
          _loading = false;
          _error = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        if (silent) {
          setState(() => _loading = false);
        } else {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      final sent = await sendChatMessage(body: text);
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else {
        if (mounted) setState(() => _sending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_sending) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final path = file.path;
    if (path.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sent = await sendChatMessage(body: '', imagePath: path);
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else {
        if (mounted) setState(() => _sending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: IconButton(
                      icon: const Icon(
                        Symbols.arrow_back_ios,
                        size: 22,
                        weight: 400,
                        color: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 0),
                  const CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Color(0xFFFFE5E5),
                    child: Icon(
                      Symbols.support_agent,
                      color: Color(0xFFE3001B),
                      size: 21,
                      fill: 1,
                      weight: 700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chat with H&R Ice Cream',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Support',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  children: [
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _error!,
                                        style: const TextStyle(color: Colors.red),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: _loadMessages,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    await _loadMessages();
                                  },
                                  child: ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    controller: _scrollController,
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      final m = _messages[index];
                                      return _buildMessageBubble(m);
                                    },
                                  ),
                                ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 0, left: 0, right: 0, bottom: 3),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _sending ? null : _pickAndSendImage,
                            icon: const Icon(
                              Symbols.attach_file,
                              size: 26,
                              color: Color(0xFFE3001B),
                              fill: 0,
                              weight: 400,
                              opticalSize: 24,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Message',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF464646),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF1F1F1),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _sending ? null : _sendMessage,
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: _sending
                                  ? Colors.grey
                                  : const Color(0xFFE3001B),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Symbols.send,
                                      color: Colors.white,
                                      size: 22,
                                      weight: 600,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessageItem m) {
    final isCustomer = m.isFromCustomer;
    final timeStr = formatMessageTime(m.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Align(
        alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isCustomer) ...[
                  const CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Color(0xFFFFE5E5),
                    child: Icon(
                      Symbols.support_agent,
                      color: Color(0xFFE3001B),
                      size: 21,
                      fill: 1,
                      weight: 700,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCustomer
                          ? const Color(0xFFE3001B)
                          : const Color(0xFFEAEAEA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Image.network(
                              m.imageUrl!,
                              width: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                            ),
                          ),
                        if (m.body != null && m.body!.isNotEmpty)
                          Text(
                            m.body!,
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: isCustomer ? Colors.white : Colors.black,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (isCustomer) ...[
                  const SizedBox(width: 10),
                  const CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Color(0xFFFFE5E5),
                    child: Icon(
                      Symbols.person,
                      color: Color(0xFFE3001B),
                      size: 21,
                      fill: 1,
                      weight: 700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(
                left: isCustomer ? 0 : (avatarRadius * 2) + 10,
                right: isCustomer ? (avatarRadius * 2) + 10 : 0,
              ),
              child: Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1C1B1F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverOrderChatPage extends StatefulWidget {
  final String orderId;
  final List<String>? relatedOrderIds;
  final String driverName;
  final String driverContact;
  final String orderLabel;

  const DriverOrderChatPage({
    super.key,
    required this.orderId,
    this.relatedOrderIds,
    required this.driverName,
    this.driverContact = '',
    required this.orderLabel,
  });

  @override
  State<DriverOrderChatPage> createState() => _DriverOrderChatPageState();
}

class _DriverOrderChatPageState extends State<DriverOrderChatPage>
    with WidgetsBindingObserver {
  static const double avatarRadius = 22;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<OrderMessageItem> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  String _activeOrderId = '';
  /// Long-press to select messages, then Delete archives the thread.
  bool _selectionMode = false;
  final Set<int> _selectedMessageIds = {};
  bool _archiving = false;
  final Map<String, LastUpdatedRtdbListener> _orderMsgsRtdb = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeOrderId = widget.orderId;
    _loadMessages();
    _markAllRelatedMessagesRead();
    _attachOrderMessagesRtdb();
  }

  @override
  void dispose() {
    for (final l in _orderMsgsRtdb.values) {
      l.dispose();
    }
    _orderMsgsRtdb.clear();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _attachOrderMessagesRtdb() {
    final db = firebaseRtdb();
    final ids = _orderIds.toSet();
    for (final k in _orderMsgsRtdb.keys.toList()) {
      if (!ids.contains(k)) {
        _orderMsgsRtdb.remove(k)?.dispose();
      }
    }
    for (final oid in ids) {
      if (_orderMsgsRtdb.containsKey(oid)) continue;
      _orderMsgsRtdb[oid] = LastUpdatedRtdbListener(
        database: db,
        path: 'order_messages/$oid/last_updated',
        debounce: const Duration(milliseconds: 450),
        onTick: () {
          if (!mounted) return;
          _loadMessages(silent: true);
        },
      )..start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
      _attachOrderMessagesRtdb();
    }
  }

  List<String> get _orderIds {
    final raw = widget.relatedOrderIds ?? <String>[widget.orderId];
    final set = <String>{};
    for (final id in raw) {
      if (id.isNotEmpty) set.add(id);
    }
    if (set.isEmpty) set.add(widget.orderId);
    return set.toList();
  }

  Future<void> _markAllRelatedMessagesRead() async {
    for (final id in _orderIds) {
      await markOrderMessagesRead(orderId: id);
    }
  }

  Future<List<OrderMessageItem>> _fetchMessagesForOrder(String orderId) async {
    final list = await fetchOrderMessages(orderId: orderId, perPage: 100);
    return list ?? <OrderMessageItem>[];
  }

  List<OrderMessageItem> _sortMergedMessages(List<OrderMessageItem> input) {
    input.sort((a, b) {
      final aAt = a.createdAt;
      final bAt = b.createdAt;
      if (aAt == null && bAt == null) return a.id.compareTo(b.id);
      if (aAt == null) return -1;
      if (bAt == null) return 1;
      final cmp = aAt.compareTo(bAt);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
    return input;
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final merged = <OrderMessageItem>[];
      for (final id in _orderIds) {
        merged.addAll(await _fetchMessagesForOrder(id));
      }
      final list = _sortMergedMessages(merged);
      if (mounted) {
        setState(() {
          _messages = list;
          if (list.isNotEmpty) {
            final latest = list.last;
            _activeOrderId = latest.orderId.isNotEmpty ? latest.orderId : widget.orderId;
          }
          _loading = false;
          _error = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        if (silent) {
          setState(() => _loading = false);
        } else {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      final sendOrderId = _activeOrderId.isNotEmpty ? _activeOrderId : widget.orderId;
      final sent = await sendOrderMessage(orderId: sendOrderId, message: text);
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else {
        if (mounted) setState(() => _sending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _onMessageLongPress(OrderMessageItem m) {
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.add(m.id);
    });
  }

  void _onMessageTap(OrderMessageItem m) {
    if (!_selectionMode) return;
    setState(() {
      if (_selectedMessageIds.contains(m.id)) {
        _selectedMessageIds.remove(m.id);
        if (_selectedMessageIds.isEmpty) _selectionMode = false;
      } else {
        _selectedMessageIds.add(m.id);
      }
    });
  }

  /// Archive selected messages (customer_status → archive) or whole thread if none selected.
  Future<void> _archiveThread() async {
    if (_archiving) return;
    setState(() => _archiving = true);
    try {
      final ids = _selectedMessageIds.toList();
      final ok = ids.isNotEmpty
          ? await archiveSelectedOrderMessages(orderId: widget.orderId, messageIds: ids)
          : await archiveOrderMessages(orderId: widget.orderId);
      if (mounted) {
        _exitSelectionMode();
        if (ok) {
          if (ids.isNotEmpty) {
            setState(() {
              _messages = _messages.where((m) => !ids.contains(m.id)).toList();
            });
          } else {
            setState(() {
              _messages = [];
              _loading = false;
            });
          }
          await _loadMessages();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Messages deleted successfully.')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to archive.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Widget _buildMessageBubble(OrderMessageItem m, {bool isSelectionMode = false, bool isSelected = false}) {
    final isCustomer = m.isMine || m.senderType == _senderCustomer;
    final timeStr = formatMessageTime(m.createdAt ?? DateTime.now());

    Widget bubble = Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Align(
        alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isCustomer) ...[
                  const CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Color(0xFFFFE5E5),
                    child: Icon(
                      Symbols.person,
                      color: Color(0xFFE3001B),
                      size: 21,
                      fill: 1,
                      weight: 700,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCustomer ? const Color(0xFFE3001B) : const Color(0xFFEAEAEA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      m.message,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: isCustomer ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
                if (isCustomer) ...[
                  const SizedBox(width: 10),
                  const CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: Color(0xFFFFE5E5),
                    child: Icon(
                      Symbols.person,
                      color: Color(0xFFE3001B),
                      size: 21,
                      fill: 1,
                      weight: 700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(
                left: isCustomer ? 0 : (avatarRadius * 2) + 10,
                right: isCustomer ? (avatarRadius * 2) + 10 : 0,
              ),
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 11, color: Color(0xFF1C1B1F)),
              ),
            ),
          ],
        ),
      ),
    );

    if (isSelectionMode) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 8),
            child: Icon(
              isSelected ? Symbols.check_circle : Symbols.radio_button_unchecked,
              size: 22,
              color: isSelected ? const Color(0xFFE3001B) : Colors.grey,
              fill: isSelected ? 1 : 0,
            ),
          ),
          Expanded(child: bubble),
        ],
      );
    }
    return bubble;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: IconButton(
                      icon: Icon(
                        _selectionMode ? Symbols.close : Symbols.arrow_back_ios,
                        size: 22,
                        weight: 400,
                        color: Colors.black,
                      ),
                      onPressed: _selectionMode ? _exitSelectionMode : () => Navigator.pop(context),
                    ),
                  ),
                  if (!_selectionMode) ...[
                    const CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: Color(0xFFFFE5E5),
                      child: Icon(
                        Symbols.person,
                        color: Color(0xFFE3001B),
                        size: 21,
                        fill: 1,
                        weight: 700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.driverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.driverContact.isNotEmpty
                                ? widget.driverContact
                                : widget.orderLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: Text(
                        '${_selectedMessageIds.length} selected',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      onPressed: _archiving ? null : _archiveThread,
                      child: _archiving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Delete', style: TextStyle(color: Color(0xFFE3001B), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  children: [
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _error!,
                                        style: const TextStyle(color: Colors.red),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: _loadMessages,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    await _loadMessages();
                                  },
                                  child: ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    controller: _scrollController,
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      final m = _messages[index];
                                      return GestureDetector(
                                        onLongPress: () => _onMessageLongPress(m),
                                        onTap: () => _onMessageTap(m),
                                        child: _buildMessageBubble(
                                          m,
                                          isSelectionMode: _selectionMode,
                                          isSelected: _selectedMessageIds.contains(m.id),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: const TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Message',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF464646),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF1F1F1),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _sending ? null : _sendMessage,
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: _sending
                                  ? Colors.grey
                                  : const Color(0xFFE3001B),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Symbols.send,
                                      color: Colors.white,
                                      size: 22,
                                      weight: 600,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

