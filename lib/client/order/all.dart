import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/favorite/favorite.dart';
import 'package:ice_cream/client/home_page.dart';
import 'package:ice_cream/client/messages/messages.dart';
import 'package:ice_cream/client/order/deliverTracker.dart';
import 'package:ice_cream/client/order/menu.dart';
import 'package:ice_cream/client/order/order_detail.dart';
import 'package:ice_cream/client/order/order_record.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// Laravel `api.customer` middleware (Bearer + X-Session-Token).
Map<String, String> _orderHistoryAuthHeaders(String token) {
  return {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    'X-Session-Token': token,
  };
}

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  int selectedTab = 0;
  final tabs = ["All", "Completed", "Processing", "Cancelled"];
  List<OrderRecord> _orders = [];
  bool _loading = true;
  String? _error;

  static const List<String> _statusQuery = ['all', 'completed', 'processing', 'cancelled'];
  static const Set<String> _completedStatuses = {
    'completed',
    'delivered',
    'walk-in',
    'walk_in',
    'walk in',
    'walkin',
  };
  static const Set<String> _processingStatuses = {
    'pending',
    'preparing',
    'assigned',
    'ready',
    'out of delivery',
    'out for delivery',
  };
  // Only these statuses show "Rate"; must be Completed (API only accepts rating for completed).
  static const Set<String> _rateableStatuses = {
    'completed',
  };
  static const Set<String> _cancelledStatuses = {
    'cancelled',
    'canceled',
  };
  // Still in Processing tab, but only "Details" and "Track Order" (no Cancel).
  static const Set<String> _nonCancellableStatuses = {
    'preparing',
    'ready',
    'out of delivery',
    'out for delivery',
  };

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please log in to view order history.';
          _orders = [];
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final status = _statusQuery[selectedTab.clamp(0, 3)];
    final customer = await Auth.getCachedCustomer();
    final cid = customer?['id']?.toString().trim();
    final qp = <String, String>{'status': status};
    if (cid != null && cid.isNotEmpty) {
      qp['customer_id'] = cid;
    }
    final uri = Uri.parse('${Auth.apiBaseUrl}/orders').replace(queryParameters: qp);
    try {
      final res = await http.get(
        uri,
        headers: _orderHistoryAuthHeaders(token),
      );
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode != 200 || body?['success'] == false) {
        setState(() {
          _loading = false;
          _error = body?['message'] as String? ?? 'Could not load orders.';
          _orders = [];
        });
        return;
      }
      final list = body?['data'] as List<dynamic>? ?? [];
      final fetched = list
          .map((e) => OrderRecord.fromJson(e as Map<String, dynamic>))
          .where((o) => o.id.isNotEmpty)
          .toList();
      final filtered = _applyTabStatusFilter(fetched, selectedTab);
      setState(() {
        _orders = filtered;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connection error. Please try again.';
          _orders = [];
        });
      }
    }
  }

  List<OrderRecord> _applyTabStatusFilter(List<OrderRecord> orders, int tabIndex) {
    if (tabIndex <= 0) return orders;

    return orders.where((order) {
      final status = _normalizeStatus(order.status);
      switch (tabIndex) {
        case 1:
          return _completedStatuses.contains(status);
        case 2:
          return _processingStatuses.contains(status);
        case 3:
          return _cancelledStatuses.contains(status);
        default:
          return true;
      }
    }).toList();
  }

  String _normalizeStatus(String value) {
    return value.trim().toLowerCase().replaceAll('_', ' ');
  }

  bool _isCompletedStatus(String status) {
    final normalized = _normalizeStatus(status);
    return _completedStatuses.contains(normalized);
  }

  bool _isProcessingStatus(String status) {
    final normalized = _normalizeStatus(status);
    return _processingStatuses.contains(normalized);
  }

  bool _isCancelledStatus(String status) {
    final normalized = _normalizeStatus(status);
    return _cancelledStatuses.contains(normalized);
  }

  bool _isCancellable(OrderRecord order) {
    return !_nonCancellableStatuses.contains(_normalizeStatus(order.status));
  }

  bool _isRateable(OrderRecord order) {
    return _rateableStatuses.contains(_normalizeStatus(order.status));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _bottomNavBar(context),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                "Order History",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: List.generate(tabs.length, (index) {
                    final isActive = selectedTab == index;
                    Color activeColor;
                    switch (tabs[index]) {
                      case "Completed":
                        activeColor = const Color(0xFF22B345);
                        break;
                      case "Processing":
                        activeColor = const Color(0xFFFF6805);
                        break;
                      case "Cancelled":
                        activeColor = const Color(0xFFE3001B);
                        break;
                      default: // All
                        activeColor = const Color(0xFF007CFF);
                    }

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => selectedTab = index);
                          _fetchOrders();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isActive ? activeColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              tabs[index],
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFFFAFAFA)
                                    : const Color(0xFF1C1B1F),
                                fontWeight: FontWeight.w500,
                                fontSize: 11.85,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const AppLoadingCenter()
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5B5B5B))),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: _fetchOrders,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _orders.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Text(
                                  'No orders in this tab.',
                                  style: TextStyle(color: Color(0xFF5B5B5B), fontSize: 14),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              itemCount: _orders.length,
                              itemBuilder: (context, index) {
                                final order = _orders[index];

                                return orderCard(
                                  order: order,
                                  isCompletedTab: selectedTab == 1 || (selectedTab == 0 && _isCompletedStatus(order.status)),
                                  isProcessingTab: selectedTab == 2 || (selectedTab == 0 && _isProcessingStatus(order.status)),
                                  isCancelledTab: selectedTab == 3 || (selectedTab == 0 && _isCancelledStatus(order.status)),
                                  onOrderCancelled: _fetchOrders,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  /// ---------------- ORDER CARD ----------------
  Widget orderCard({
    required OrderRecord order,
    bool isCompletedTab = false,
    bool isProcessingTab = false,
    bool isCancelledTab = false,
    VoidCallback? onOrderCancelled,
  }) {
    final name = order.productName;
    final size = order.gallonSize;
    final price = order.amountFormatted;
    final qty = order.quantity.toString();
    final imgUrl = order.productImageUrl;
    final isNetworkImage = imgUrl.startsWith('http');
    const placeholderAsset = 'lib/client/order/images/mg.png';

    String leftText;
    Color leftBgColor;
    Color leftTextColor;
    Color leftBorderColor = Colors.transparent;

    bool showRightBtn = true;
    String rightText = "Buy Again";
    Color rightColor = const Color(0xFFF2F2F2);
    Color rightTextColor = Colors.black87;

    if (isCompletedTab) {
      if (_isRateable(order)) {
        leftText = "Rate";
        leftBgColor = const Color(0xFFFFD900);
        leftTextColor = Colors.black;
      } else {
        leftText = "Details";
        leftBgColor = const Color(0xFFF2F2F2);
        leftTextColor = Colors.black87;
      }
      rightText = "Buy Again";
      rightColor = const Color(0xFFF2F2F2);
      rightTextColor = Colors.black87;
      showRightBtn = true;
    } else if (isProcessingTab) {
      if (_isCancellable(order)) {
        leftText = "Cancel";
        leftBgColor = Colors.white;
        leftTextColor = const Color(0xFFE3001B);
        leftBorderColor = const Color(0xFFE3001B);
      } else {
        leftText = "Details";
        leftBgColor = const Color(0xFFF2F2F2);
        leftTextColor = Colors.black87;
      }
      rightText = "Track Order";
      rightColor = const Color(0xFF007CFF);
      rightTextColor = Colors.white;
      showRightBtn = true;
    } else if (isCancelledTab) {
      leftText = "Details";
      leftBgColor = const Color(0xFFF2F2F2);
      leftTextColor = Colors.black87;
      rightText = "Buy Again";
      rightColor = const Color(0xFF007CFF);
      rightTextColor = const Color(0xFFFFFFFF);
      showRightBtn = true;
    } else {
      if (order.isProcessing) {
        if (_isCancellable(order)) {
          leftText = "Cancel";
          leftBgColor = const Color(0xFFFCE8E9);
          leftTextColor = const Color(0xFFE3001B);
          leftBorderColor = const Color(0xFFE3001B);
        } else {
          leftText = "Details";
          leftBgColor = const Color(0xFFF2F2F2);
          leftTextColor = Colors.black87;
        }
        showRightBtn = true;
        rightText = "Track Order";
        rightColor = const Color(0xFF007CFF);
        rightTextColor = Colors.white;
      } else if (order.isCancelled) {
        leftText = "Details";
        leftBgColor = const Color(0xFFF2F2F2);
        leftTextColor = Colors.black87;
        rightText = "Buy Again";
        rightColor = const Color(0xFF007CFF);
        rightTextColor = const Color(0xFFFFFFFF);
        showRightBtn = true;
      } else {
        if (_isRateable(order)) {
          leftText = "Rate";
          leftBgColor = const Color(0xFFFFD900);
          leftTextColor = Colors.black;
        } else {
          leftText = "Details";
          leftBgColor = const Color(0xFFF2F2F2);
          leftTextColor = Colors.black87;
        }
        rightText = "Buy Again";
        rightColor = const Color(0xFFF2F2F2);
        rightTextColor = Colors.black87;
        showRightBtn = true;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isNetworkImage
                ? Image.network(
                    imgUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(placeholderAsset, width: 60, height: 60, fit: BoxFit.cover),
                  )
                : Image.asset(placeholderAsset, width: 60, height: 60, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13.64,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "Quantity: $qty",
                      style: const TextStyle(
                        fontSize: 12.79,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          size,
                          style: const TextStyle(
                            fontSize: 11.96,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 11.96,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE3001B),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isProcessingTab && leftText == "Cancel") {
                              showCancelOrderDialog(
                                context,
                                orderId: order.id,
                                productName: order.productName,
                                onCancelled: onOrderCancelled,
                              );
                              return;
                            }
                            if (leftText == "Rate") {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RateOrderPage(
                                    orderId: order.id,
                                    imageAsset: imgUrl,
                                    itemName: name,
                                    status: _formatRateStatusLabel(order.status),
                                    price: price,
                                    dateTimeLabel: order.createdAtFormatted ?? '—',
                                  ),
                                ),
                              ).then((_) => _fetchOrders());
                            }
                            if (leftText == "Details") {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailPage(order: order),
                                ),
                              );
                            }
                          },
                          child: Container(
                            height: 32,
                            width: 81,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: leftBgColor,
                              border: Border.all(
                                color: leftBorderColor,
                                width: 1.3,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                leftText,
                                style: TextStyle(
                                  color: leftTextColor,
                                  fontSize: 11.96,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showRightBtn) ...[
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: () {
                              if (rightText == "Track Order") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DeliveryTrackerPage(order: order),
                                  ),
                                );
                              }
                              if (rightText == "Buy Again") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MenuPage(),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              height: 32,
                              width: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: rightColor,
                              ),
                              child: Center(
                                child: Text(
                                  rightText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11.96,
                                    color: rightTextColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRateStatusLabel(String status) {
    final normalized = _normalizeStatus(status);
    if (normalized == 'walk in' || normalized == 'walkin' || normalized == 'walk-in') {
      return 'Walk-in';
    }
    return 'Delivered';
  }

  // ---------------- BOTTOM NAV ----------------
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
              active: true,
              onTap: () {},
              fillColor: const Color(0xFFE3001B),
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessagesPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- RATE ORDER PAGE ----------------
}

class RateOrderPage extends StatefulWidget {
  const RateOrderPage({
    super.key,
    required this.orderId,
    required this.imageAsset,
    required this.itemName,
    required this.price,
    this.status = 'Delivered',
    this.dateTimeLabel = 'Today, 12:30 PM',
  });

  final String orderId;
  final String imageAsset;
  final String itemName;
  final String price;
  final String status;
  final String dateTimeLabel;

  @override
  State<RateOrderPage> createState() => _RateOrderPageState();
}

class _RateOrderPageState extends State<RateOrderPage> {
  int _rating = 0; // start with no selection (all gray)
  final TextEditingController _messageController = TextEditingController();
  bool _submittingFeedback = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // The continue button is now pushed even closer to the absolute bottom
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFF3F3F3),
                          ),
                          child: const Icon(Icons.close, color: Colors.black),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Rate your order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40), // keep title centered
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 28),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: widget.imageAsset.startsWith('http')
                                    ? Image.network(
                                        widget.imageAsset,
                                        width: 54,
                                        height: 54,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Image.asset(
                                          'lib/client/order/images/mg.png',
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Image.asset(
                                        widget.imageAsset,
                                        width: 54,
                                        height: 54,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.dateTimeLabel,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5B5B5B),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.itemName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  widget.status,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5B5B5B),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.price,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Divider(height: 1, thickness: 1.3, color: Color(0xFFD2D2D2)),
                        const SizedBox(height: 22),
                        const Text(
                          'How was the ice cream?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700, 
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Please rate the store.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF5B5B5B),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              final value = index + 1;
                              double availableWidth = constraints.maxWidth - 36; // account for padding
                              double starSize = (availableWidth / 5).clamp(34.0, 58.0);

                              Color starColor;
                              IconData starIcon;

                              if (_rating == 0) {
                                starIcon = Icons.star_rate;
                                starColor = const Color(0xFFD9D9D9);
                              } else {
                                if (value <= _rating) {
                                  starIcon = Icons.star_rate;
                                  starColor = const Color(0xFFFFD900);
                                } else {
                                  starIcon = Icons.star_rate;
                                  starColor = const Color(0xFFD9D9D9);
                                }
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () => setState(() => _rating = value),
                                  child: Icon(
                                    starIcon,
                                    size: starSize,
                                    color: starColor,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 38),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFC7C7C7)),
                          ),
                          child: TextField(
                            controller: _messageController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Message here',
                              hintStyle: TextStyle(
                                color: Color(0xFF8C8C8C),
                                fontSize: 14,
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        // The continue button is no longer here!
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        // Reduce the minimum padding to move the button even closer to the very bottom.
        minimum: EdgeInsets.zero,
        // Remove internal padding, only leave spacing at the left/right, and minimal bottom.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12), // less space at bottom/top
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_rating == 0 || _submittingFeedback)
                  ? null
                  : () async {
                      setState(() => _submittingFeedback = true);
                      final token = await Auth.getApiToken();
                      if (token == null) {
                        if (mounted) setState(() => _submittingFeedback = false);
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                      try {
                        await http.post(
                          Uri.parse(
                            '${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(widget.orderId)}/feedback',
                          ),
                          headers: {
                            'Accept': 'application/json',
                            'Content-Type': 'application/json',
                            ..._orderHistoryAuthHeaders(token),
                          },
                          body: jsonEncode({
                            'rating': _rating,
                            'message': _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
                          }),
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) setState(() => _submittingFeedback = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE3001B),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                elevation: 0,
                padding: EdgeInsets.zero,
              ),
              child: _submittingFeedback
                  ? const AppLoadingOnBrand()
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? fillColor;

  const _BottomIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = active ? const Color(0xFFE3001B) : const Color(0xFF969696);
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

Future<void> showCancelOrderDialog(
  BuildContext context, {
  required String orderId,
  String? productName,
  VoidCallback? onCancelled,
}) {
  final otherReasonController = TextEditingController();
  // Use page context for success dialog and refresh after dialog is closed
  final parentContext = context;

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      String? selectedReason;
      bool cancellingOrder = false;

      final reasons = <String>[
        'Changed my mind',
        'Ordered by mistake',
        'Want to update or change my order',
        'Payment issue (e.g., failed)',
        'Others (Please specify)',
      ];

      // Height of each default reason tile (for uniformity)
      const double defaultOptionHeight = 45;

      Widget reasonTile(String text, void Function(void Function()) setState) {
        final isSelected = selectedReason == text;
        // Special handling for "Others (Please specify)"
        if (text == 'Others (Please specify)') {
          return InkWell(
            onTap: () => setState(() => selectedReason = text),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: !isSelected ? defaultOptionHeight : null,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F3), // #F3F3F3
                borderRadius: BorderRadius.circular(10),
                // NO border here for "Others" box
              ),
              child: !isSelected
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF2F80ED)
                                  : const Color(0xFF828282),
                              width: 1,
                            ),
                          ),
                          child: isSelected
                              ? Center(
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF2F80ED),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            textAlign: TextAlign.start,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5B5B5B),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF2F80ED)
                                      : const Color(0xFF828282),
                                  width: 1,
                                ),
                              ),
                              child: isSelected
                                  ? Center(
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF2F80ED),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5B5B5B),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9E9E9), // New background color for box
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFC4C4C4)), // New border color
                            ),
                            child: TextField(
                              controller: otherReasonController,
                              maxLines: 4,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(12),
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: 'Write your message here',
                                hintStyle: TextStyle(
                                  color: Color(0xFF5B5B5B),
                                  fontSize: 11,
                                ),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF434343),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        }
        // All other reasons (default)
        return InkWell(
          onTap: () => setState(() => selectedReason = text),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: defaultOptionHeight,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF2F80ED)
                          : const Color(0xFF828282),
                      width: 1,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF2F80ED),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B5B5B),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.23),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top icon (cancel X, filled) on red circle
                      Padding(
                        padding: const EdgeInsets.all(1),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE3001B),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Symbols.close,
                            size: 26,
                            color: Colors.white,
                            fill: 1,
                            weight: 700,
                            grade: 0,
                            opticalSize: 24,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        "Cancel Order?",
                        style: TextStyle(
                          fontSize: 19.85,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "Are you sure you want to cancel this order?",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.23,
                          color: Color(0xFF5B5B5B),
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Reason options
                      ...reasons.expand((r) sync* {
                        yield reasonTile(r, setState);
                        yield const SizedBox(height: 10);
                      }),

                      // Reason required: disable Confirm until a reason is selected (and "Others" has text)
                      Builder(
                        builder: (_) {
                          final isOthers = selectedReason == 'Others (Please specify)';
                          final otherText = otherReasonController.text.trim();
                          final isReasonValid = selectedReason != null &&
                              selectedReason!.isNotEmpty &&
                              (!isOthers || otherText.isNotEmpty);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 118.75,
                                height: 43.43,
                                child: OutlinedButton(
                                  onPressed: cancellingOrder ? null : () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF969696)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    "No, cancel",
                                    style: TextStyle(
                                      fontSize: 14.26,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF434343),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 118.75,
                                height: 43.43,
                                child: ElevatedButton(
                                  onPressed: (isReasonValid && !cancellingOrder)
                                      ? () async {
                                          final reason = selectedReason;
                                          final reasonDetail = otherReasonController.text.trim();
                                          if (reason == null || reason.isEmpty) {
                                            ScaffoldMessenger.of(parentContext).showSnackBar(
                                              const SnackBar(
                                                content: Text('Please select a reason for cancellation.'),
                                                backgroundColor: Color(0xFFE3001B),
                                              ),
                                            );
                                            return;
                                          }
                                          if (reason == 'Others (Please specify)' && reasonDetail.isEmpty) {
                                            ScaffoldMessenger.of(parentContext).showSnackBar(
                                              const SnackBar(
                                                content: Text('Please specify your reason.'),
                                                backgroundColor: Color(0xFFE3001B),
                                              ),
                                            );
                                            return;
                                          }
                                          setState(() => cancellingOrder = true);
                                          final token = await Auth.getApiToken();
                                          if (token == null) {
                                            setState(() => cancellingOrder = false);
                                            return;
                                          }
                                          try {
                                            final body = <String, dynamic>{
                                              'reason': reason,
                                            };
                                            if (reason == 'Others (Please specify)' && reasonDetail.isNotEmpty) {
                                              body['reason_detail'] = reasonDetail;
                                            }
                                            final res = await http.patch(
                                              Uri.parse(
                                                '${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(orderId)}/cancel',
                                              ),
                                              headers: {
                                                'Accept': 'application/json',
                                                'Content-Type': 'application/json',
                                                ..._orderHistoryAuthHeaders(token),
                                              },
                                              body: jsonEncode(body),
                                            );
                                            if (!parentContext.mounted) return;
                                            if (res.statusCode == 200) {
                                              Navigator.pop(dialogContext);
                                              onCancelled?.call();
                                              showSuccessDialog(parentContext, productName: productName);
                                            } else {
                                              final data = jsonDecode(res.body) as Map<String, dynamic>?;
                                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    data?['message'] as String? ?? 'Failed to cancel order.',
                                                  ),
                                                  backgroundColor: const Color(0xFFE3001B),
                                                ),
                                              );
                                            }
                                          } catch (_) {
                                            if (parentContext.mounted) {
                                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Connection error. Please try again.'),
                                                  backgroundColor: Color(0xFFE3001B),
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (dialogContext.mounted) {
                                              setState(() => cancellingOrder = false);
                                            }
                                          }
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE3001B),
                                    disabledBackgroundColor: Colors.grey.shade300,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Center(
                                    child: cancellingOrder
                                        ? const AppLoadingOnBrand(size: 20, strokeWidth: 2)
                                        : const Text(
                                            "Yes, I'm sure",
                                            softWrap: false,
                                            maxLines: 1,
                                            overflow: TextOverflow.visible,
                                            style: TextStyle(
                                              fontSize: 14.26,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(otherReasonController.dispose);
}

Future<void> showSuccessDialog(BuildContext context, {String? productName}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.83),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Icon(
                Symbols.check_circle,
                size: 44,
                color: Color(0xFF22B345),
                fill: 1,
                weight: 400,
                grade: 0,
                opticalSize: 24,
              ),
              const SizedBox(height: 8),
              const Text(
                "Order Cancelled",
                style: TextStyle(fontSize: 19.85, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                productName != null && productName.isNotEmpty
                    ? "Your order ($productName) has been successfully cancelled."
                    : "Your order has been successfully cancelled.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.23,
                  color: Color(0xFF5B5B5B),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22B345),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text("OK"),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

