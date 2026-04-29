  import 'dart:convert';

  import 'package:flutter/material.dart';
  import 'package:http/http.dart' as http;
  import 'package:ice_cream/auth.dart';
  import 'package:ice_cream/driver/delivery/driver_shipment_id.dart';
  import 'package:ice_cream/firebase_rtdb_config.dart';
  import 'package:ice_cream/services/last_updated_rtdb_listener.dart';
  import 'package:material_symbols_icons/material_symbols_icons.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  import 'package:ice_cream/driver/message/no_messages_empty_state.dart';

  import 'archive_messages.dart';

  bool _driverApiJsonSuccess(dynamic v) {
    if (v == true) return true;
    if (v == 1) return true;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1';
    }
    return false;
  }

  List<dynamic> _driverApiJsonDataList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v;
    return [];
  }

  class messagesPage extends StatefulWidget {
    final String? initialShipmentId;
    final String? initialCustomerName;
    final String? initialCustomerPhone;

    /// When false (e.g. inside [IndexedStack] before the tab is shown), loading is deferred until the tab becomes active.
    final bool isMessagesTabActive;

    const messagesPage({
      super.key,
      this.initialShipmentId,
      this.initialCustomerName,
      this.initialCustomerPhone,
      this.isMessagesTabActive = true,
    });

    @override
    State<messagesPage> createState() => _messagesPageState();
  }

  class _messagesPageState extends State<messagesPage> {
    bool _loading = true;
    String _error = '';
    List<Map<String, dynamic>> _threads = [];
    final Map<String, LastUpdatedRtdbListener> _shipmentOrderRtdb = {};

    @override
    void initState() {
      super.initState();
      if (!widget.isMessagesTabActive) {
        _loading = false;
      }
      if (widget.isMessagesTabActive) {
        _fetchThreads();
      }
    }

    @override
    void didUpdateWidget(covariant messagesPage oldWidget) {
      super.didUpdateWidget(oldWidget);
      if (widget.isMessagesTabActive && !oldWidget.isMessagesTabActive) {
        _fetchThreads(silent: _threads.isNotEmpty);
      }
    }

    @override
    void dispose() {
      for (final l in _shipmentOrderRtdb.values) {
        l.dispose();
      }
      _shipmentOrderRtdb.clear();
      super.dispose();
    }

    void _syncShipmentOrderRtdbListeners() {
      final db = firebaseRtdb();
      final ids = <String>{};
      for (final t in _threads) {
        if (t['is_admin_thread'] == true) continue;
        final raw = t['shipment_ids'] as List?;
        if (raw != null) {
          for (final e in raw) {
            final id = driverShipmentIdFrom(e);
            if (id != null && id.isNotEmpty) ids.add(id);
          }
        }
        final mainId = driverShipmentIdFrom(t['shipment_id']);
        if (mainId != null && mainId.isNotEmpty) ids.add(mainId);
      }
      final capped = ids.take(35).toSet();
      for (final k in _shipmentOrderRtdb.keys.toList()) {
        if (!capped.contains(k)) {
          _shipmentOrderRtdb.remove(k)?.dispose();
        }
      }
      for (final sid in capped) {
        if (_shipmentOrderRtdb.containsKey(sid)) continue;
        _shipmentOrderRtdb[sid] = LastUpdatedRtdbListener(
          database: db,
          path: 'order_messages/$sid/last_updated',
          debounce: const Duration(milliseconds: 500),
          onTick: () {
            if (!mounted) return;
            _fetchThreads(silent: true);
          },
        )..start();
      }
    }

    Future<String?> _token() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('driver_token');
    }

    static const Duration _apiTimeout = Duration(seconds: 12);

    Future<List<Map<String, dynamic>>> _fetchShipmentsTab(
      String tab,
      String token,
    ) async {
      try {
        final uri = Uri.parse('${Auth.apiBaseUrl}/driver/shipments')
            .replace(queryParameters: {'tab': tab});
        final res = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_apiTimeout);
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode != 200 || !_driverApiJsonSuccess(data['success'])) return [];
        final raw = data['shipments'];
        if (raw is! List) return [];
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        return [];
      }
    }

    DateTime? _parseDateTime(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.trim().isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    int _computeUnreadCount(List<dynamic> list) {
      if (list.isEmpty) return 0;
      int lastDriverIdx = -1;
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        if (m is Map && (m['is_mine'] == true)) lastDriverIdx = i;
      }
      int unread = 0;
      for (var i = lastDriverIdx + 1; i < list.length; i++) {
        final m = list[i];
        if (m is Map && (m['is_mine'] != true)) unread++;
      }
      return unread;
    }

    Future<Map<String, dynamic>?> _fetchLastMessagePreview({
      required String shipmentId,
      required String token,
    }) async {
      try {
        final uri = Uri.parse(
          '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(shipmentId)}/messages',
        )
            .replace(queryParameters: const {'status': 'active'});
        final res = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_apiTimeout);
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['data'];
        if (res.statusCode != 200 || !_driverApiJsonSuccess(data['success']) || list is! List || list.isEmpty) {
          return null;
        }
        final latest = list.last;
        if (latest is! Map) return null;
        final msg = (latest['message'] ?? '').toString().trim();
        if (msg.isEmpty) return null;
        final unreadCount = _computeUnreadCount(list);
        return {
          'message': msg,
          'created_at': latest['created_at'],
          'unread_count': unreadCount,
        };
      } catch (_) {
        return null;
      }
    }

    Future<List<Map<String, dynamic>>> _fetchDriverAdminChatThreads(String token) async {
      try {
        final uri = Uri.parse('${Auth.apiBaseUrl}/driver/admin-chat/threads');
        final res = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_apiTimeout);
        final decoded = jsonDecode(res.body);
        if (decoded is! Map) return [];
        final data = Map<String, dynamic>.from(decoded);
        if (res.statusCode != 200 || !_driverApiJsonSuccess(data['success'])) return [];
        final out = <Map<String, dynamic>>[];
        for (final e in _driverApiJsonDataList(data['data'])) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
        return out;
      } catch (_) {
        return [];
      }
    }

    Map<String, dynamic> _driverAdminThreadFromApi(Map<String, dynamic> row) {
      int unread(dynamic v) {
        if (v is int) return v;
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      return {
        'thread_id': (row['thread_id'] ?? 'admin_support').toString(),
        'is_admin_thread': true,
        'shipment_id': '',
        'shipment_ids': <String>[],
        'customer_name': (row['title'] ?? 'Support').toString(),
        'customer_phone': '',
        'delivery_address': (row['subtitle'] ?? '').toString(),
        'last_message': (row['last_message'] ?? '').toString(),
        'last_message_at': row['last_message_at'],
        'unread_count': unread(row['unread_count']),
      };
    }

    String _threadSortKey(Map<String, dynamic> t) {
      final sid = (t['shipment_id'] ?? '').toString();
      if (sid.isNotEmpty) return sid;
      return (t['thread_id'] ?? '').toString();
    }

    int _compareMessageThreads(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aId = _threadSortKey(a);
      final bId = _threadSortKey(b);
      final aAt = _parseDateTime(a['last_message_at']);
      final bAt = _parseDateTime(b['last_message_at']);

      if (widget.initialShipmentId != null) {
        final init = widget.initialShipmentId!;
        final aIds = List<String>.from(
          (a['shipment_ids'] as List?)?.map((e) => e.toString()) ?? const [],
        );
        final bIds = List<String>.from(
          (b['shipment_ids'] as List?)?.map((e) => e.toString()) ?? const [],
        );
        if (aIds.contains(init) || aId == init) {
          return -1;
        }
        if (bIds.contains(init) || bId == init) {
          return 1;
        }
      }

      if (aAt == null && bAt == null) return bId.compareTo(aId);
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    }

    Future<void> _fetchThreads({bool silent = false}) async {
      final hadThreads = _threads.isNotEmpty;
      if (!silent) {
        setState(() {
          if (!hadThreads) {
            _loading = true;
            _error = '';
          } else {
            _error = '';
          }
        });
      }
      try {
        final token = await _token();
        if (token == null || token.isEmpty) {
          if (!mounted) return;
          if (silent) {
            return;
          }
          setState(() {
            _loading = false;
            _error = 'Missing driver session. Please login again.';
            _threads = [];
          });
          return;
        }

        final tabs = ['incoming', 'accepted', 'completed'];
        final tabResults = await Future.wait(
          tabs.map((tab) => _fetchShipmentsTab(tab, token)),
        );
        final all = <Map<String, dynamic>>[];
        for (final list in tabResults) all.addAll(list);

        final byId = <String, Map<String, dynamic>>{};
        for (final shipment in all) {
          final id = driverShipmentIdFrom(shipment['id']);
          if (id == null) continue;
          byId[id] = shipment;
        }

        final list = byId.entries.map((e) {
          final shipment = e.value;
          final cidRaw = shipment['customer_id'];
          final customerId = cidRaw is int ? cidRaw : int.tryParse(cidRaw?.toString() ?? '');
          return <String, dynamic>{
            'shipment_id': e.key,
            'customer_id': customerId,
            'customer_name': (shipment['customer_name'] ?? 'Customer').toString(),
            'customer_phone': (shipment['customer_phone'] ?? '').toString(),
            'delivery_address': (shipment['delivery_address'] ?? shipment['location'] ?? '').toString(),
            'expected_on': (shipment['expected_on'] ?? '').toString(),
            'status_driver': (shipment['status_driver'] ?? '').toString(),
          };
        }).toList();

        final previews = await Future.wait(
          list.map((item) => _fetchLastMessagePreview(
            shipmentId: item['shipment_id'] as String,
            token: token,
          )),
        );
        final filtered = <Map<String, dynamic>>[];
        for (var i = 0; i < list.length; i++) {
          final preview = previews[i];
          if (preview == null) continue;
          final item = Map<String, dynamic>.from(list[i]);
          item['last_message'] = (preview['message'] ?? '').toString();
          item['last_message_at'] = preview['created_at'];
          item['unread_count'] = (preview['unread_count'] as int?) ?? 0;
          filtered.add(item);
        }

        // Merge threads by same customer (use customer_id to avoid duplication when names/phones match).
        final grouped = <String, Map<String, dynamic>>{};
        for (final item in filtered) {
          final customerId = item['customer_id'] is int ? item['customer_id'] as int? : int.tryParse((item['customer_id'] ?? '').toString());
          final phone = (item['customer_phone'] ?? '').toString().trim();
          final name = (item['customer_name'] ?? 'Customer').toString().trim().toLowerCase();
          final key = (customerId != null && customerId > 0)
              ? 'c:$customerId'
              : (phone.isNotEmpty ? 'p:$phone' : 'n:$name');
          final itemShipmentId = item['shipment_id'] as String;
          final itemAt = _parseDateTime(item['last_message_at']);

          if (!grouped.containsKey(key)) {
            grouped[key] = {
              ...item,
              'shipment_ids': <String>[itemShipmentId],
              'unread_count': (item['unread_count'] as int?) ?? 0,
            };
            continue;
          }

          final current = grouped[key]!;
          final currentAt = _parseDateTime(current['last_message_at']);
          final currentIds = List<String>.from(
            (current['shipment_ids'] as List?)?.map((e) => e.toString()) ?? const [],
          );
          if (!currentIds.contains(itemShipmentId)) currentIds.add(itemShipmentId);
          current['shipment_ids'] = currentIds;
          current['unread_count'] = ((current['unread_count'] as int?) ?? 0) +
              ((item['unread_count'] as int?) ?? 0);

          final takeNewer = currentAt == null ||
              (itemAt != null && itemAt.isAfter(currentAt));
          if (takeNewer) {
            current['shipment_id'] = itemShipmentId;
            current['delivery_address'] = item['delivery_address'];
            current['expected_on'] = item['expected_on'];
            current['status_driver'] = item['status_driver'];
            current['last_message'] = item['last_message'];
            current['last_message_at'] = item['last_message_at'];
          }
        }

        final merged = grouped.values.toList();
        merged.sort(_compareMessageThreads);

        final adminRows = await _fetchDriverAdminChatThreads(token);
        final combined = <Map<String, dynamic>>[
          ...adminRows.map(_driverAdminThreadFromApi),
          ...merged,
        ];
        combined.sort(_compareMessageThreads);

        if (!mounted) return;
        setState(() {
          _threads = combined;
          _loading = false;
        });
        _syncShipmentOrderRtdbListeners();
      } catch (_) {
        if (!mounted) return;
        if (silent) {
          return;
        }
        setState(() {
          _loading = false;
          _threads = [];
          _error = 'Could not load messages. Check connection.';
        });
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFFAFAFA),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    const Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1B1F),
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (value) {
                        if (value == 'refresh') _fetchThreads();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 20, color: Color(0xFF1C1B1F)),
                              SizedBox(width: 10),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Icon(
                          Symbols.more_vert,
                          size: 22,
                          color: Color(0xFF1C1B1F),
                          fill: 0,
                          weight: 600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ArchiveMessagesPage(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Symbols.archive,
                          size: 22,
                          color: Color(0xFF1C1B1F),
                          fill: 0,
                          weight: 600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _error.isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFFE3001B)),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: _fetchThreads,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _threads.isEmpty
                            ? RefreshIndicator(
                                onRefresh: () => _fetchThreads(silent: true),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: NoMessagesEmptyState(),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _fetchThreads(silent: true),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: _threads.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, index) {
                                    final thread = _threads[index];
                                    final isAdmin = thread['is_admin_thread'] == true;
                                    final shipmentId = (thread['shipment_id'] ?? '').toString();
                                    final shipmentIds = (thread['shipment_ids'] as List?)
                                            ?.map((e) => e.toString())
                                            .where((e) => e.isNotEmpty)
                                            .toList() ??
                                        (shipmentId.isNotEmpty ? <String>[shipmentId] : <String>[]);
                                    final name = (thread['customer_name'] ?? 'Customer').toString();
                                    final phone = (thread['customer_phone'] ?? '').toString();
                                    var rawPreview = (thread['last_message'] ?? '').toString();
                                    if (isAdmin && rawPreview.trim().isEmpty) {
                                      rawPreview = 'Tap to message HQ';
                                    }
                                    const previewMax = 36;
                                    final preview = rawPreview.length > previewMax
                                        ? '${rawPreview.substring(0, previewMax - 1)}…'
                                        : rawPreview;
                                    final rawAddr = (thread['delivery_address'] ?? '').toString().trim();
                                    const addrMax = 42;
                                    final subtitle = rawAddr.length > addrMax
                                        ? '${rawAddr.substring(0, addrMax - 1)}…'
                                        : rawAddr;
                                    final unreadCount = (thread['unread_count'] as int?) ?? 0;
                                    return GestureDetector(
                                      onTap: () async {
                                        if (isAdmin) {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const DriverAdminSupportChatPage(),
                                            ),
                                          );
                                        } else {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ChatPage(
                                                shipmentId: shipmentId,
                                                relatedShipmentIds: shipmentIds,
                                                customerName: name,
                                                customerPhone: phone,
                                              ),
                                            ),
                                          );
                                        }
                                        _fetchThreads();
                                      },
                                      child: _MessageCard(
                                        icon: isAdmin ? Symbols.support_agent : Symbols.person,
                                        name: name,
                                        message: preview,
                                        time: subtitle.isNotEmpty
                                            ? subtitle
                                            : (!isAdmin && shipmentId.isNotEmpty
                                                ? 'Order #${shipmentId.length > 12 ? '${shipmentId.substring(0, 11)}…' : shipmentId}'
                                                : (isAdmin ? 'Direct line to HQ' : '')),
                                        unreadCount: unreadCount,
                                      ),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      );
    }
  }

  class _MessageCard extends StatelessWidget {
    const _MessageCard({
      required this.icon,
      required this.name,
      required this.message,
      required this.time,
      this.unreadCount = 0,
    });

    final IconData icon;
    final String name;
    final String message;
    final String time;
    final int unreadCount;

    @override
    Widget build(BuildContext context) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE7EA),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: const Color(0xFFE3001B),
                      fill: 1,
                      weight: 600,
                      grade: 200,
                      opticalSize: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1C1B1F),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
                      ),
                    ],
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
  }

  class DriverAdminSupportChatPage extends StatefulWidget {
    const DriverAdminSupportChatPage({super.key});

    @override
    State<DriverAdminSupportChatPage> createState() => _DriverAdminSupportChatPageState();
  }

  class _DriverAdminSupportChatPageState extends State<DriverAdminSupportChatPage> {
    final TextEditingController _messageCtrl = TextEditingController();
    final ScrollController _scrollCtrl = ScrollController();

    bool _hasLoadedOnce = false;
    bool _sending = false;
    String _error = '';
    List<_AdminDmMessage> _messages = [];

    static const Duration _requestTimeout = Duration(seconds: 15);

    @override
    void initState() {
      super.initState();
      Future(() async {
        await _loadMessages(showLoader: false);
        if (!mounted) return;
        await _markRead();
      });
    }

    @override
    void dispose() {
      _messageCtrl.dispose();
      _scrollCtrl.dispose();
      super.dispose();
    }

    Future<String?> _token() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('driver_token');
    }

    String _formatTime(DateTime? dt) {
      if (dt == null) return '';
      final hour24 = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = hour24 >= 12 ? 'pm' : 'am';
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      return '$hour12:$minute $suffix';
    }

    Future<void> _loadMessages({bool showLoader = true, bool silent = false}) async {
      if (showLoader && !silent) {
        setState(() => _error = '');
      }
      try {
        final token = await _token();
        if (token == null || token.isEmpty) {
          if (!mounted) return;
          setState(() {
            _hasLoadedOnce = true;
            _error = 'Missing driver session. Please login again.';
            _messages = [];
          });
          return;
        }
        final uri = Uri.parse('${Auth.apiBaseUrl}/driver/admin-chat/messages');
        final res = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_requestTimeout);
        Map<String, dynamic> data;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is! Map) {
            if (!mounted) return;
            setState(() {
              _messages = [];
              _hasLoadedOnce = true;
              _error = silent ? _error : 'Invalid response from server.';
            });
            return;
          }
          data = Map<String, dynamic>.from(decoded);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _messages = [];
            _hasLoadedOnce = true;
            _error = silent ? _error : 'Could not load messages.';
          });
          return;
        }

        if (res.statusCode != 200 || !_driverApiJsonSuccess(data['success'])) {
          if (!mounted) return;
          final msg = (data['message'] ?? 'Could not load messages.').toString();
          setState(() {
            _messages = [];
            _hasLoadedOnce = true;
            _error = silent ? _error : msg;
          });
          return;
        }

        final merged = <_AdminDmMessage>[];
        for (final item in _driverApiJsonDataList(data['data'])) {
          if (item is! Map) continue;
          merged.add(_AdminDmMessage.fromMap(Map<String, dynamic>.from(item)));
        }
        merged.sort((a, b) {
          final aAt = a.createdAt;
          final bAt = b.createdAt;
          if (aAt == null && bAt == null) return a.id.compareTo(b.id);
          if (aAt == null) return -1;
          if (bAt == null) return 1;
          final c = aAt.compareTo(bAt);
          if (c != 0) return c;
          return a.id.compareTo(b.id);
        });
        if (!mounted) return;
        setState(() {
          _messages = merged;
          _hasLoadedOnce = true;
          _error = '';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollCtrl.hasClients) return;
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        });
      } catch (_) {
        if (!mounted) return;
        if (silent) {
          setState(() => _hasLoadedOnce = true);
          return;
        }
        setState(() {
          _hasLoadedOnce = true;
          _error = 'Could not load messages. Check connection.';
        });
      }
    }

    Future<void> _markRead() async {
      try {
        final token = await _token();
        if (token == null || token.isEmpty) return;
        await http.post(
          Uri.parse('${Auth.apiBaseUrl}/driver/admin-chat/read'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {}
    }

    Future<void> _sendMessage() async {
      final text = _messageCtrl.text.trim();
      if (text.isEmpty || _sending) return;
      setState(() => _sending = true);
      try {
        final token = await _token();
        if (token == null || token.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Missing driver session. Please login again.')),
            );
          }
          return;
        }
        final res = await http.post(
          Uri.parse('${Auth.apiBaseUrl}/driver/admin-chat/messages'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'message': text}),
        );
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        if ((res.statusCode == 201 || res.statusCode == 200) && _driverApiJsonSuccess(data['success'])) {
          _messageCtrl.clear();
          await _loadMessages(showLoader: false);
        } else {
          final msg = (data['message'] ?? 'Could not send message.').toString();
          final shortMsg = msg.length > 60 ? '${msg.substring(0, 57)}...' : msg;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(shortMsg)),
          );
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Check connection.')),
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Symbols.arrow_back_ios,
                        size: 22,
                        weight: 400,
                        color: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const CircleAvatar(
                      radius: ChatPage.avatarRadius,
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Support',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Messages from HQ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFFE3001B)),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () => _loadMessages(showLoader: false),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !_hasLoadedOnce && _messages.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _messages.isEmpty
                            ? const Center(
                                child: Text(
                                  'No messages yet.',
                                  style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _loadMessages(showLoader: false),
                                child: ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final item = _messages[index];
                                    final mine = item.isMine;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Align(
                                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Column(
                                          crossAxisAlignment: mine
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              constraints: const BoxConstraints(maxWidth: 280),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 15,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: mine
                                                    ? const Color(0xFFE3001B)
                                                    : const Color(0xFFEAEAEA),
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Text(
                                                item.message,
                                                maxLines: 15,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: mine ? Colors.white : const Color(0xFF1C1B1F),
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatTime(item.createdAt),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
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
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sending ? null : _sendMessage,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: _sending
                            ? const Color(0xFFB56973)
                            : const Color(0xFFE3001B),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
      );
    }
  }

  class _AdminDmMessage {
    final String id;
    final String message;
    final bool isMine;
    final DateTime? createdAt;

    const _AdminDmMessage({
      required this.id,
      required this.message,
      required this.isMine,
      required this.createdAt,
    });

    factory _AdminDmMessage.fromMap(Map<String, dynamic> json) {
      final idRaw = json['id'];
      final createdAtRaw = json['created_at']?.toString();
      final sender = (json['sender_type'] ?? '').toString().toLowerCase().trim();
      final isMineFlag = json['is_mine'];
      final isMine = isMineFlag == true ||
          isMineFlag == 1 ||
          isMineFlag == '1' ||
          sender == 'driver';

      return _AdminDmMessage(
        id: idRaw?.toString() ?? '',
        message: (json['message'] ?? '').toString(),
        isMine: isMine,
        createdAt: createdAtRaw == null || createdAtRaw.isEmpty
            ? null
            : DateTime.tryParse(createdAtRaw)?.toLocal(),
      );
    }
  }

  class ChatPage extends StatefulWidget {
    final String shipmentId;
    final List<String>? relatedShipmentIds;
    final String customerName;
    final String? customerPhone;

    const ChatPage({
      super.key,
      required this.shipmentId,
      this.relatedShipmentIds,
      required this.customerName,
      this.customerPhone,
    });

    static const double avatarRadius = 22;

    @override
    State<ChatPage> createState() => _ChatPageState();
  }

  class _ChatPageState extends State<ChatPage> {
    final TextEditingController _messageCtrl = TextEditingController();
    final ScrollController _scrollCtrl = ScrollController();

    bool _hasLoadedOnce = false;
    bool _sending = false;
    String _error = '';
    List<_OrderMessage> _messages = [];
    String _activeShipmentId = '';
    final Map<String, LastUpdatedRtdbListener> _orderMsgsRtdb = {};

    @override
    void initState() {
      super.initState();
      _activeShipmentId = widget.shipmentId;
      _loadMessages(showLoader: false);
      _markRead();
      _attachOrderMessagesRtdb();
    }

    @override
    void dispose() {
      for (final l in _orderMsgsRtdb.values) {
        l.dispose();
      }
      _orderMsgsRtdb.clear();
      _messageCtrl.dispose();
      _scrollCtrl.dispose();
      super.dispose();
    }

    void _attachOrderMessagesRtdb() {
      final db = firebaseRtdb();
      final ids = _shipmentIds.toSet();
      for (final k in _orderMsgsRtdb.keys.toList()) {
        if (!ids.contains(k)) {
          _orderMsgsRtdb.remove(k)?.dispose();
        }
      }
      for (final sid in ids) {
        if (_orderMsgsRtdb.containsKey(sid)) continue;
        _orderMsgsRtdb[sid] = LastUpdatedRtdbListener(
          database: db,
          path: 'order_messages/$sid/last_updated',
          debounce: const Duration(milliseconds: 450),
          onTick: () {
            if (!mounted) return;
            _loadMessages(showLoader: false, silent: true);
          },
        )..start();
      }
    }

    Future<String?> _token() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('driver_token');
    }

    String _formatTime(DateTime? dt) {
      if (dt == null) return '';
      final hour24 = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = hour24 >= 12 ? 'pm' : 'am';
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      return '$hour12:$minute $suffix';
    }

    List<String> get _shipmentIds {
      final raw = widget.relatedShipmentIds ?? <String>[widget.shipmentId];
      final set = <String>{};
      for (final id in raw) {
        if (id.isNotEmpty) set.add(id);
      }
      if (set.isEmpty) set.add(widget.shipmentId);
      return set.toList();
    }

    static const Duration _messagesRequestTimeout = Duration(seconds: 15);

    Future<List<_OrderMessage>> _fetchMessagesForShipment({
      required String shipmentId,
      required String token,
    }) async {
      try {
        final uri = Uri.parse(
          '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(shipmentId)}/messages',
        ).replace(queryParameters: const {'status': 'active'});
        final res = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_messagesRequestTimeout);
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode != 200 || !_driverApiJsonSuccess(data['success']) || data['data'] is! List) {
          return <_OrderMessage>[];
        }
        return (data['data'] as List)
            .whereType<Map>()
            .map((raw) => _OrderMessage.fromMap(Map<String, dynamic>.from(raw)))
            .toList();
      } catch (_) {
        return <_OrderMessage>[];
      }
    }

    Future<void> _loadMessages({bool showLoader = true, bool silent = false}) async {
      if (showLoader && !silent) {
        setState(() => _error = '');
      }
      try {
        final token = await _token();
        if (token == null || token.isEmpty) {
          if (!mounted) return;
          setState(() {
            _hasLoadedOnce = true;
            _error = 'Missing driver session. Please login again.';
            _messages = [];
          });
          return;
        }
        final shipmentIds = _shipmentIds;
        final results = await Future.wait(
          shipmentIds.map((id) => _fetchMessagesForShipment(shipmentId: id, token: token)),
        );
        final merged = <_OrderMessage>[];
        for (final list in results) {
          merged.addAll(list);
        }
        if (!mounted) return;
        if (merged.isNotEmpty) {
          merged.sort((a, b) {
            final aAt = a.createdAt;
            final bAt = b.createdAt;
            if (aAt == null && bAt == null) return a.id.compareTo(b.id);
            if (aAt == null) return -1;
            if (bAt == null) return 1;
            final timeCmp = aAt.compareTo(bAt);
            if (timeCmp != 0) return timeCmp;
            return a.id.compareTo(b.id);
          });
          final latest = merged.last;
          setState(() {
            _messages = merged;
            _activeShipmentId = latest.orderId.isNotEmpty ? latest.orderId : widget.shipmentId;
            _hasLoadedOnce = true;
            _error = '';
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollCtrl.hasClients) return;
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          });
        } else {
          setState(() {
            _messages = [];
            _hasLoadedOnce = true;
            _error = '';
          });
        }
      } catch (_) {
        if (!mounted) return;
        if (silent) {
          setState(() => _hasLoadedOnce = true);
          return;
        }
        setState(() {
          _hasLoadedOnce = true;
          _error = 'Could not load messages. Check connection.';
        });
      } finally {
        if (mounted) {
          setState(() => _hasLoadedOnce = true);
        }
      }
    }

    Future<void> _markRead() async {
      try {
        final token = await _token();
        if (token == null || token.isEmpty) return;
        for (final id in _shipmentIds) {
          await http.post(
            Uri.parse(
              '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(id)}/messages/read',
            ),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        }
      } catch (_) {}
    }

    Future<void> _sendMessage() async {
      final text = _messageCtrl.text.trim();
      if (text.isEmpty || _sending) return;
      setState(() => _sending = true);
      try {
        final token = await _token();
        if (token == null || token.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Missing driver session. Please login again.')),
            );
          }
          return;
        }
        final sendShipmentId =
            _activeShipmentId.isNotEmpty ? _activeShipmentId : widget.shipmentId;
        final res = await http.post(
          Uri.parse(
            '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(sendShipmentId)}/messages',
          ),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'message': text}),
        );
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        if ((res.statusCode == 201 || res.statusCode == 200) && _driverApiJsonSuccess(data['success'])) {
          _messageCtrl.clear();
          await _loadMessages(showLoader: false);
        } else {
          final msg = (data['message'] ?? 'Could not send message.').toString();
          final shortMsg = msg.length > 60 ? '${msg.substring(0, 57)}...' : msg;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(shortMsg)),
          );
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Check connection.')),
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Symbols.arrow_back_ios,
                        size: 22,
                        weight: 400,
                        color: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const CircleAvatar(
                      radius: ChatPage.avatarRadius,
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
                            widget.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            (widget.customerPhone ?? '').isEmpty
                                ? 'Order #${widget.shipmentId}'
                                : widget.customerPhone!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFFE3001B)),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () => _loadMessages(showLoader: false),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !_hasLoadedOnce && _messages.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _messages.isEmpty
                            ? const Center(
                                child: Text(
                                  'No messages yet.',
                                  style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _loadMessages(showLoader: false),
                                child: ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final item = _messages[index];
                                    final mine = item.isMine;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Align(
                                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Column(
                                          crossAxisAlignment: mine
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              constraints: const BoxConstraints(maxWidth: 280),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 15,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: mine
                                                    ? const Color(0xFFE3001B)
                                                    : const Color(0xFFEAEAEA),
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Text(
                                                item.message,
                                                maxLines: 15,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: mine ? Colors.white : const Color(0xFF1C1B1F),
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatTime(item.createdAt),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
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
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sending ? null : _sendMessage,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: _sending
                            ? const Color(0xFFB56973)
                            : const Color(0xFFE3001B),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
      );
    }
  }

  class _OrderMessage {
    final int id;
    final String orderId;
    final String senderType;
    final String message;
    final bool isMine;
    final DateTime? createdAt;

    const _OrderMessage({
      required this.id,
      required this.orderId,
      required this.senderType,
      required this.message,
      required this.isMine,
      required this.createdAt,
    });

    factory _OrderMessage.fromMap(Map<String, dynamic> json) {
      final idRaw = json['id'];
      final orderIdRaw = json['order_id'];
      final createdAtRaw = json['created_at']?.toString();
      return _OrderMessage(
        id: idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '') ?? 0,
        orderId: (orderIdRaw ?? '').toString(),
        senderType: (json['sender_type'] ?? '').toString(),
        message: (json['message'] ?? '').toString(),
        isMine: json['is_mine'] == true,
        createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw)?.toLocal(),
      );
    }
  }
