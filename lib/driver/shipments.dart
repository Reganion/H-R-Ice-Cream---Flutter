import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/firebase_rtdb_config.dart';
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:ice_cream/services/last_updated_rtdb_listener.dart';
import 'package:ice_cream/services/rtdb_user_context.dart';
import 'package:ice_cream/driver/delivery/complete_delivery.dart';
import 'package:ice_cream/driver/delivery/confirm_delivery.dart';
import 'package:ice_cream/driver/delivery/driver_shipment_id.dart';
import 'package:ice_cream/driver/delivery/view_details.dart';
import 'package:ice_cream/driver/message/messages.dart';
import 'package:ice_cream/driver/profile/profile.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FcmPushService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shipments',
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: null,
        scaffoldBackgroundColor: const Color(0xFFF6F6F6),
      ),
      home: const ShipmentsPage(),
    );
  }
}

class ShipmentsPage extends StatefulWidget {
  const ShipmentsPage({super.key});

  @override
  State<ShipmentsPage> createState() => _ShipmentsPageState();
}

class _ShipmentsPageState extends State<ShipmentsPage> {
  static const Color kRed = Color(0xFFE3001B);
  static const Color kText = Color(0xFF111111);
  static const Color kMuted = Color(0xFF000000);
  static const Color kCard = Color(0xFFF2F2F2);
  static const Color kBlue = Color(0xFF007CFF);

  int _selectedTabIndex = 0; // 0 = Incoming, 1 = Accepted, 2 = Completed
  int _bottomNavIndex = 0; // 0 = Shipments, 1 = Messages, 2 = Profile

  String _driverName = '';
  String _driverPhone = '';
  String? _driverImageUrl;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loadingShipments = false;
  String _shipmentsError = '';
  List<Map<String, dynamic>> _shipments = [];
  int _notificationUnreadCount = 0;
  LastUpdatedRtdbListener? _driverNotifRtdb;

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
    _fetchShipments();
    _fetchNotificationUnreadCount();
    _attachDriverNotificationsRtdb();
  }

  Future<void> _fetchNotificationUnreadCount() async {
    final count = await fetchDriverNotificationUnreadCount();
    if (!mounted) return;
    setState(() => _notificationUnreadCount = count);
  }

  Future<void> _attachDriverNotificationsRtdb() async {
    final id = await resolveDriverId();
    if (!mounted || id == null) return;
    _driverNotifRtdb?.dispose();
    _driverNotifRtdb = LastUpdatedRtdbListener(
      database: firebaseRtdb(),
      path: 'driver_notifications/$id/last_updated',
      debounce: const Duration(milliseconds: 450),
      onTick: () {
        if (!mounted) return;
        _fetchNotificationUnreadCount();
      },
    )..start();
  }

  @override
  void dispose() {
    _driverNotifRtdb?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Tab sent to `GET /driver/shipments` — must be a single string so Laravel
  /// never receives `tab` as an array (which caused `mapShipmentRow` TypeError).
  String get _activeTab {
    if (_selectedTabIndex == 1) return 'accepted';
    if (_selectedTabIndex == 2) return 'completed';
    return 'incoming';
  }

  Uri _driverShipmentsListUri() {
    final q = <String, String>{
      'tab': _activeTab,
      if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
    };
    return Uri.parse('${Auth.apiBaseUrl}/driver/shipments').replace(
      queryParameters: q,
    );
  }

  String _displayAmount(Map<String, dynamic> map) {
    final raw = (map['amount_text'] ?? '').toString().trim();
    if (raw.toUpperCase().startsWith('PHP ')) {
      return '₱${raw.substring(4)}';
    }
    final amount = map['amount'];
    if (amount is num) return '₱${amount.toStringAsFixed(0)}';
    return raw.isNotEmpty ? raw : '₱0';
  }

  /// Real order status label for Accepted tab (from API status field).
  String _orderStatusBadgeLabel(String? rawStatus) {
    final s = (rawStatus ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return 'Pending';
    switch (s) {
      case 'assigned':
        return 'Assigned';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready';
      case 'out for delivery':
      case 'out_of_delivery':
        return 'Out for delivery';
      case 'completed':
        return 'Completed';
      case 'pending':
        return 'Pending';
      default:
        return s.length > 1
            ? s.substring(0, 1).toUpperCase() + s.substring(1)
            : s.toUpperCase();
    }
  }

  Color _hexToColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return fallback;
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value != null ? Color(value) : fallback;
  }

  Future<void> _loadDriverProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('driver_profile');
      if (json == null || json.isEmpty) return;
      final data = jsonDecode(json) as Map<String, dynamic>;
      setState(() {
        _driverName = (data['name'] ?? '').toString();
        _driverPhone = (data['phone'] ?? '').toString();
        final img = data['image_url'] ?? data['image'];
        _driverImageUrl = img != null ? img.toString() : null;
      });
      _fetchDriverProfileFromApi();
    } catch (_) {
      // ignore – fall back to placeholders
    }
  }

  Future<void> _fetchDriverProfileFromApi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('driver_token');
      if (token == null || token.isEmpty) return;
      final res = await http.get(
        Uri.parse('${Auth.apiBaseUrl}/driver/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final driver = data['driver'];
      if (driver is! Map<String, dynamic>) return;
      await prefs.setString('driver_profile', jsonEncode(driver));
      if (!mounted) return;
      setState(() {
        _driverName = (driver['name'] ?? '').toString();
        _driverPhone = (driver['phone'] ?? '').toString();
        final img = driver['image_url'] ?? driver['image'];
        _driverImageUrl = img != null ? img.toString() : null;
      });
      _attachDriverNotificationsRtdb();
    } catch (_) {}
  }

  Future<void> _fetchShipments({bool fromPullRefresh = false}) async {
    if (!fromPullRefresh) {
      setState(() {
        _loadingShipments = true;
        _shipmentsError = '';
      });
    } else {
      setState(() => _shipmentsError = '');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('driver_token');
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingShipments = false;
          _shipmentsError = 'Missing driver session. Please login again.';
          _shipments = [];
        });
        return;
      }
      final res = await http.get(
        _driverShipmentsListUri(),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (res.statusCode == 200 && data['success'] == true) {
        final raw = data['shipments'];
        final list = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        setState(() {
          _shipments = list;
          _loadingShipments = false;
        });
      } else {
        setState(() {
          _loadingShipments = false;
          _shipments = [];
          _shipmentsError = (data['message'] ?? 'Could not load shipments.').toString();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingShipments = false;
        _shipments = [];
        _shipmentsError = 'Could not load shipments. Check connection.';
      });
    }
  }

  Widget _buildShipmentCard({
    required String transactionId,
    required String badge,
    required Color badgeColor,
    required String productName,
    required String price,
    required String expectedOn,
    required String location,
    bool showViewDetailsButton = false,
    bool showBadge = true,
    VoidCallback? onViewDetails,
    VoidCallback? onTap,
  }) {
    Widget card = Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(
                    Symbols.deployed_code,
                    size: 20,
                    color: Color(0xFF2A2A2A),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transactionId,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Transaction ID",
                      style: TextStyle(
                        fontSize: 12,
                        color: kMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (showBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: kText,
                    ),
                  ),
                ),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              height: 1,
              color: const Color(0xFFD9D9D9),
            ),
            const SizedBox(height: 12),
            if (showViewDetailsButton)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onViewDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(221, 0, 123, 255),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    "View Details",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Expected on:",
                          style: TextStyle(
                            fontSize: 12,
                            color: kMuted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expectedOn,
                          style: const TextStyle(
                            fontSize: 14,
                            color: kText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Location:",
                          style: TextStyle(
                            fontSize: 12,
                            color: kMuted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 14,
                            color: kText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: !showViewDetailsButton && onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: card,
            )
          : card,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _bottomNavIndex,
                children: [
                  // 0: Shipments (fully scrollable when keyboard open to avoid overflow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchShipments(fromPullRefresh: true),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            // Top header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 0),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD9C1A7),
                    ),
                    child: ClipOval(
                      child: _driverImageUrl != null &&
                              _driverImageUrl!.isNotEmpty &&
                              _driverImageUrl!.startsWith('http')
                          ? Image.network(
                              _driverImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                            )
                          : Image.asset(
                              "lib/driver/profile/images/kyley.png",
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _driverName.isNotEmpty ? _driverName : "H&R Driver",
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F1F1F),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _driverPhone.isNotEmpty
                              ? _driverPhone
                              : "+63 ••• ••• ••••",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1F1F1F),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bell button with unread badge
                  InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsPage(),
                        ),
                      );
                      _fetchNotificationUnreadCount();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFE9EA),
                          ),
                          child: const Icon(Icons.notifications, color: kRed),
                        ),
                        if (_notificationUnreadCount > 0)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: const BoxDecoration(
                                color: kRed,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              alignment: Alignment.center,
                              child: Text(
                                _notificationUnreadCount > 99 ? '99+' : '$_notificationUnreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // Search (same position and look as client home_page search bar)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 50,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Color(0xFFD9D9D9), width: 1),
                ),
                child: Row(
                  children: [
                    Transform.translate(
                      offset: const Offset(15, 0),
                      child: const Icon(
                        Icons.search,
                        color: Color(0xFFAFAFAF),
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 26),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        cursorColor: Colors.black,
                        cursorHeight: 18,
                        style: const TextStyle(
                          fontSize: 14.18,
                          color: Color(0xFF848484),
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search",
                          hintStyle: TextStyle(
                            color: Color(0xFF848484),
                            fontSize: 15.76,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => _fetchShipments(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Tabs (Incoming / Accepted / Completed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    _SegmentChip(
                      label: "Incoming",
                      selected: _selectedTabIndex == 0,
                      selectedColor: kRed,
                      onTap: () {
                        setState(() => _selectedTabIndex = 0);
                        _fetchShipments();
                      },
                    ),
                    _SegmentChip(
                      label: "Accepted",
                      selected: _selectedTabIndex == 1,
                      selectedColor: kRed,
                      onTap: () {
                        setState(() => _selectedTabIndex = 1);
                        _fetchShipments();
                      },
                    ),
                    _SegmentChip(
                      label: "Completed",
                      selected: _selectedTabIndex == 2,
                      selectedColor: kRed,
                      onTap: () {
                        setState(() => _selectedTabIndex = 2);
                        _fetchShipments();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Cards (scroll with header when keyboard open)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    if (_loadingShipments)
                      const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_shipmentsError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(
                          _shipmentsError,
                          style: const TextStyle(
                            color: Color(0xFFE3001B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else if (_shipments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(
                          'No shipments found.',
                          style: TextStyle(
                            color: Color(0xFF505050),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      ..._shipments.asMap().entries.map((entry) {
                        final shipment = entry.value;
                        final isCompleted = _selectedTabIndex == 2;
                        final isAcceptedTab = _selectedTabIndex == 1;
                        final badgeLabel = isAcceptedTab
                            ? _orderStatusBadgeLabel(shipment['status']?.toString())
                            : (shipment['badge'] ?? (isCompleted ? 'Completed' : 'New')).toString();
                        final badgeColor = _hexToColor(
                          shipment['badge_color']?.toString(),
                          _selectedTabIndex == 1
                              ? const Color(0xFFFF6805)
                              : (_selectedTabIndex == 2 ? const Color(0xFF00AE2A) : kBlue),
                        );
                        return Column(
                          children: [
                            _buildShipmentCard(
                              transactionId: (shipment['transaction_label'] ??
                                      shipment['transaction_id'] ??
                                      '—')
                                  .toString(),
                              badge: badgeLabel,
                              badgeColor: badgeColor,
                              productName: (shipment['product_name'] ?? '—').toString(),
                              price: _displayAmount(shipment),
                              expectedOn: (shipment['expected_on'] ?? '—').toString(),
                              location: (shipment['location'] ?? '—').toString(),
                              showViewDetailsButton: isCompleted,
                              showBadge: !isCompleted,
                              onTap: isCompleted
                                  ? null
                                  : () {
                                      final id = driverShipmentIdFrom(shipment['id']);
                                      if (id == null) return;
                                      final status = (shipment['status'] ?? '').toString().toLowerCase();
                                      final statusDriver = (shipment['status_driver'] ?? '').toString().toLowerCase();
                                      final isOutForDelivery = status == 'out for delivery' ||
                                          status == 'out_of_delivery' ||
                                          statusDriver == 'on_route';
                                      final goToComplete = _selectedTabIndex == 1 && isOutForDelivery;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => goToComplete
                                              ? CompleteDeliveryPage(
                                                  shipmentId: id,
                                                  initialShipment: shipment,
                                                )
                                              : ConfirmDeliveryPage(
                                                  showDeliverNowOnly: _selectedTabIndex == 1,
                                                  shipmentId: id,
                                                  initialShipment: shipment,
                                                ),
                                        ),
                                      ).then((_) => _fetchShipments());
                                    },
                              onViewDetails: !isCompleted
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => DeliveryViewDetailsPage(
                                            shipmentId: driverShipmentIdFrom(shipment['id']),
                                            initialShipment: shipment,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                            if (entry.key < _shipments.length - 1) const SizedBox(height: 10),
                          ],
                        );
                      }),
                    const SizedBox(height: 16),
                    SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                  ],
                ),
                  ],
                ),
                ),
              ),
            ),
                    ],
                  ),
                  // 1: Messages / Chat — fetch when tab is shown (IndexedStack keeps this off-screen first)
                  messagesPage(isMessagesTabActive: _bottomNavIndex == 1),
                  // 2: Profile
                  const Center(
                    child: Text(
                      'Profile',
                      style: TextStyle(fontSize: 16, color: Color(0xFF747474)),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Nav (same padding & style as client home_page)
            Card(
              margin: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 0,
              child: SizedBox(
                height: 65,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BottomItem(
                      icon: Symbols.deployed_code,
                      label: "Shipments",
                      selected: _bottomNavIndex == 0,
                      onTap: () => setState(() => _bottomNavIndex = 0),
                    ),
                    _BottomItem(
                      icon: Symbols.chat_bubble,
                      label: "Messages",
                      selected: _bottomNavIndex == 1,
                      onTap: () => setState(() => _bottomNavIndex = 1),
                    ),
                    _BottomItem(
                      icon: Symbols.account_circle,
                      label: "Profile",
                      selected: _bottomNavIndex == 2,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProfilePage(),
                          ),
                        );
                      },
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

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: selected ? Colors.white  : const Color(0xFF171717),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const Color _activeColor = Color(0xFFE3001B);
  static const Color _inactiveColor = Color(0xFF9D9D9D);

  @override
  Widget build(BuildContext context) {
    final color = selected ? _activeColor : _inactiveColor;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
            fill: selected ? 1 : 0,
            weight: 300,
            grade: 200,
            opticalSize: 24,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }
    return content;
  }
}

/// Driver notification item from API.
class _DriverNotificationItem {
  final int id;
  final String title;
  final String message;
  final DateTime? createdAt;
  final DateTime? readAt;
  final String? relatedType;
  final String? relatedId;

  const _DriverNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    this.createdAt,
    this.readAt,
    this.relatedType,
    this.relatedId,
  });

  bool get isRead => readAt != null;
}

DateTime? _parseDriverNotifDateTime(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

Future<List<_DriverNotificationItem>> fetchDriverNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('driver_token');
  if (token == null || token.isEmpty) return [];
  try {
    final uri = Uri.parse('${Auth.apiBaseUrl}/driver/notifications')
        .replace(queryParameters: {'per_page': '50'});
    final res = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    if (data == null || data['success'] != true) return [];
    final list = data['data'] as List<dynamic>? ?? [];
    final items = <_DriverNotificationItem>[];
    for (final raw in list.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final idRaw = item['id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
      if (id == null || id <= 0) continue;
      final title = (item['title'] ?? '').toString().trim();
      final message = (item['message'] ?? '').toString().trim();
      if (title.isEmpty && message.isEmpty) continue;
      final relatedIdRaw = item['related_id'];
      final relatedIdStr = relatedIdRaw?.toString().trim();
      final relatedId =
          (relatedIdStr != null && relatedIdStr.isNotEmpty) ? relatedIdStr : null;
      items.add(_DriverNotificationItem(
        id: id,
        title: title,
        message: message,
        createdAt: _parseDriverNotifDateTime(item['created_at']),
        readAt: _parseDriverNotifDateTime(item['read_at']),
        relatedType: item['related_type']?.toString(),
        relatedId: relatedId,
      ));
    }
    items.sort((a, b) {
      final aAt = a.createdAt;
      final bAt = b.createdAt;
      if (aAt == null && bAt == null) return b.id.compareTo(a.id);
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });
    return items;
  } catch (e) {
    throw Exception('Failed to load notifications: $e');
  }
}

Future<int> fetchDriverNotificationUnreadCount() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('driver_token');
  if (token == null || token.isEmpty) return 0;
  try {
    final res = await http.get(
      Uri.parse('${Auth.apiBaseUrl}/driver/notifications/unread-count'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return 0;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    if (data == null || data['success'] != true) return 0;
    final raw = data['unread_count'];
    return raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<bool> deleteAllDriverNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('driver_token');
  if (token == null || token.isEmpty) return false;
  try {
    final res = await http.delete(
      Uri.parse('${Auth.apiBaseUrl}/driver/notifications'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return false;
  }
}

Future<bool> markDriverNotificationRead({required int notificationId}) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('driver_token');
  if (token == null || token.isEmpty) return false;
  try {
    final res = await http.post(
      Uri.parse('${Auth.apiBaseUrl}/driver/notifications/$notificationId/read'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return data != null && data['success'] == true;
  } catch (_) {
    return false;
  }
}

String _formatDriverNotifTimeAgo(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}hrs ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${dt.month}/${dt.day}/${dt.year}';
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  String _error = '';
  List<_DriverNotificationItem> _notifications = [];
  LastUpdatedRtdbListener? _driverNotifRtdb;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _attachDriverNotificationsRtdb();
  }

  @override
  void dispose() {
    _driverNotifRtdb?.dispose();
    super.dispose();
  }

  Future<void> _attachDriverNotificationsRtdb() async {
    final id = await resolveDriverId();
    if (!mounted || id == null) return;
    _driverNotifRtdb?.dispose();
    _driverNotifRtdb = LastUpdatedRtdbListener(
      database: firebaseRtdb(),
      path: 'driver_notifications/$id/last_updated',
      debounce: const Duration(milliseconds: 450),
      onTick: () {
        if (!mounted) return;
        _refreshNotificationsSilent();
      },
    )..start();
  }

  Future<void> _refreshNotificationsSilent() async {
    try {
      final list = await fetchDriverNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _error = '';
      });
    } catch (_) {}
  }

  Future<void> _loadNotifications({bool fromRefresh = false}) async {
    if (!fromRefresh) {
      setState(() {
        _loading = true;
        _error = '';
      });
    } else {
      setState(() => _error = '');
    }
    try {
      final list = await fetchDriverNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _loading = false;
        _error = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications. Check connection.';
      });
    }
  }

  void _showDeleteAllModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
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
              const Text(
                "Delete all notifications?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "You can't undo this later.",
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await deleteAllDriverNotifications();
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
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3001B),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    "Delete All",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 5),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onNotificationTap(_DriverNotificationItem item) async {
    if (!item.isRead) {
      await markDriverNotificationRead(notificationId: item.id);
    }
    if (!mounted) return;
    final relatedType = (item.relatedType ?? '').toString().toLowerCase();
    final relatedId = item.relatedId;
    if ((relatedType == 'shipment' || relatedType == 'order') &&
        relatedId != null &&
        relatedId.isNotEmpty) {
      final titleMsg = '${item.title} ${item.message}'.toLowerCase();
      final isDeliveredSuccess = titleMsg.contains('delivered');
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => isDeliveredSuccess
              ? DeliveryViewDetailsPage(
                  shipmentId: relatedId,
                )
              : ConfirmDeliveryPage(
                  shipmentId: relatedId,
                  initialShipment: null,
                ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF2F2F2),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 21,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    "Notifications",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _notifications.isEmpty ? null : () => _showDeleteAllModal(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Icon(
                        Symbols.delete,
                        size: 22,
                        color: _notifications.isEmpty ? Colors.grey : Colors.black,
                        fill: 0,
                        weight: 600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Notifications list
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
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
                                  onPressed: _loadNotifications,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _notifications.isEmpty
                          ? const Center(
                              child: Text(
                                'No notifications yet.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF747474),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                          onRefresh: () => _loadNotifications(fromRefresh: true),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ..._notifications.asMap().entries.map((entry) {
                                  final item = entry.value;
                                  final title = item.title.isNotEmpty ? item.title : 'Notification';
                                  final message = item.message;
                                  final time = item.createdAt != null
                                      ? _formatDriverNotifTimeAgo(item.createdAt!)
                                      : '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: GestureDetector(
                                      onTap: () => _onNotificationTap(item),
                                      child: _NotificationCard(
                                        showIndicator: !item.isRead,
                                        indicatorColor: item.isRead
                                            ? const Color(0xFFCFCFCF)
                                            : const Color(0xFFE21B2D),
                                        title: title,
                                        message: message,
                                        time: time,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final bool showIndicator;
  final Color indicatorColor;
  final String title;
  final String message;
  final String time;

  const _NotificationCard({
    this.showIndicator = true,
    required this.indicatorColor,
    required this.title,
    required this.message,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Color(0x1A000000),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Prominent red vertical bar (full left edge, like the photo)
            if (showIndicator)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(showIndicator ? 16 : 18, 12, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F1F1F),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7C7C7C),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF424242),
                        fontWeight: FontWeight.w400,
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
