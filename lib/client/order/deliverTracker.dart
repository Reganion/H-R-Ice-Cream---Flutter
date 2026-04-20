import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ice_cream/client/messages/messages.dart';
import 'package:ice_cream/client/order/order_record.dart';
import 'package:ice_cream/auth.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryTrackerPage extends StatefulWidget {
  const DeliveryTrackerPage({super.key, required this.order});

  final OrderRecord order;

  @override
  State<DeliveryTrackerPage> createState() => _DeliveryTrackerPageState();
}

class _DeliveryTrackerPageState extends State<DeliveryTrackerPage> {
  late OrderRecord _order = widget.order;
  int? _driverId;
  String _driverName = '—';
  String _driverPhone = '';
  String _customerContact = '—';
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshOrder();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refreshOrder() async {
    final token = await Auth.getToken();
    if (!mounted || token == null || token.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      final uri = Uri.parse(
        '${Auth.apiBaseUrl}/orders/${Uri.encodeComponent(widget.order.id)}',
      );
      final res = await http.get(
        uri,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 200) {
        final data = body?['data'] as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            _order = OrderRecord.fromJson(data);
            _driverId = _extractDriverId(data);
            _driverName = _extractDriverName(data);
            _driverPhone = _extractDriverPhone(data);
            _customerContact = _extractCustomerContact(data);
          });
        }
      }
    } catch (_) {
      // Ignore refresh errors; we still show the passed-in order data.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _pickFirstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _extractDriverName(Map<String, dynamic> order) {
    String fullNameFromParts(Map<String, dynamic> source) {
      final first = _pickFirstNonEmpty([
        source['firstname'],
        source['first_name'],
        source['driver_first_name'],
        source['assigned_driver_first_name'],
        source['rider_first_name'],
      ]);
      final last = _pickFirstNonEmpty([
        source['lastname'],
        source['last_name'],
        source['driver_last_name'],
        source['assigned_driver_last_name'],
        source['rider_last_name'],
      ]);
      return '$first $last'.trim();
    }

    final direct = _pickFirstNonEmpty([
      order['driver_name'],
      order['assigned_driver_name'],
      order['rider_name'],
      order['driver_full_name'],
      order['driver_display_name'],
    ]);
    if (direct.isNotEmpty) return direct;

    final nestedRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
    if (nestedRaw is Map) {
      final nested = Map<String, dynamic>.from(nestedRaw);
      final nestedDirect = _pickFirstNonEmpty([
        nested['name'],
        nested['full_name'],
        nested['driver_name'],
        nested['display_name'],
      ]);
      if (nestedDirect.isNotEmpty) return nestedDirect;
      final nestedParts = fullNameFromParts(nested);
      if (nestedParts.isNotEmpty) return nestedParts;
    }

    final topParts = fullNameFromParts(order);
    return topParts.isNotEmpty ? topParts : '—';
  }

  int? _extractDriverId(Map<String, dynamic> order) {
    final direct = order['driver_id'];
    if (direct is int) return direct;
    final fromDirect = int.tryParse((direct ?? '').toString());
    if (fromDirect != null && fromDirect > 0) return fromDirect;
    final nestedRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
    if (nestedRaw is Map) {
      final nested = Map<String, dynamic>.from(nestedRaw);
      final nestedId = nested['id'] ?? nested['driver_id'] ?? nested['user_id'];
      if (nestedId is int) return nestedId;
      final parsed = int.tryParse((nestedId ?? '').toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  String _extractDriverPhone(Map<String, dynamic> order) {
    final direct = _pickFirstNonEmpty([
      order['driver_phone'],
      order['driver_contact'],
      order['assigned_driver_phone'],
      order['assigned_driver_contact'],
      order['rider_phone'],
      order['rider_contact'],
    ]);
    if (direct.isNotEmpty) return direct;

    final nestedRaw = order['driver'] ?? order['assigned_driver'] ?? order['rider'];
    if (nestedRaw is Map) {
      final nested = Map<String, dynamic>.from(nestedRaw);
      final nestedPhone = _pickFirstNonEmpty([
        nested['phone'],
        nested['contact_no'],
        nested['contact_number'],
        nested['mobile'],
        nested['mobile_number'],
      ]);
      if (nestedPhone.isNotEmpty) return nestedPhone;
    }

    return '';
  }

  String _extractCustomerContact(Map<String, dynamic> order) {
    final direct = _pickFirstNonEmpty([
      order['customer_phone'],
      order['customer_contact'],
      order['contact_no'],
      order['contact_number'],
      order['phone'],
      order['mobile'],
    ]);
    if (direct.isNotEmpty) return direct;

    final customerRaw = order['customer'];
    if (customerRaw is Map) {
      final customer = Map<String, dynamic>.from(customerRaw);
      final nested = _pickFirstNonEmpty([
        customer['contact_no'],
        customer['contact_number'],
        customer['customer_phone'],
        customer['phone'],
        customer['mobile'],
      ]);
      if (nested.isNotEmpty) return nested;
    }

    return '—';
  }

  String get _normalizedStatus {
    return _order.status.trim().toLowerCase().replaceAll('_', ' ');
  }

  bool get _isOutForDelivery {
    return _normalizedStatus == 'out of delivery' ||
        _normalizedStatus == 'out for delivery' ||
        _normalizedStatus == 'driving' ||
        _normalizedStatus == 'on the way';
  }

  bool get _canMessageDriver {
    return _isOutForDelivery && _driverId != null && _driverId! > 0;
  }

  Future<void> _openDriverChat() async {
    if (!_canMessageDriver) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only chat the driver when your order is out for delivery.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverOrderChatPage(
          orderId: _order.id,
          relatedOrderIds: <String>[_order.id],
          driverName: _driverName,
          driverContact: _driverPhone,
          orderLabel: _order.productName,
        ),
      ),
    );
  }

  Future<void> _callDriver() async {
    if (!_isOutForDelivery) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver call is available once your order is out for delivery.'),
        ),
      );
      return;
    }
    final phone = _driverPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver phone number is not available yet.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open phone dialer.')),
      );
    }
  }

  String get _etaLabel {
    final date = _order.deliveryDate;
    final time = _order.deliveryTime;
    if ((date == null || date.isEmpty) && (time == null || time.isEmpty)) return 'Estimated on: —';
    if (date == null || date.isEmpty) return 'Estimated on: —, $time';
    if (time == null || time.isEmpty) return 'Estimated on: $date';
    return 'Estimated on: $date, $time';
  }

  String get _statusLabel {
    switch (_order.status) {
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'driving':
      case 'on_the_way':
        return 'Driving';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'walk_in':
        return 'Walk-in';
      default:
        final s = _order.status.trim();
        if (s.isEmpty) return '—';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  Color get _statusColor {
    switch (_order.status) {
      case 'delivered':
      case 'walk_in':
        return const Color(0xFF22B345);
      case 'cancelled':
        return const Color(0xFFE3001B);
      case 'pending':
      case 'assigned':
        return const Color(0xFFFF6805);
      default:
        return const Color(0xFF7051C7);
    }
  }

  int get _trackerStepIndex {
    final status = _normalizedStatus;
    if (status == 'completed' || status == 'delivered' || status == 'walk in' || status == 'walk-in') {
      return 4;
    }
    if (status == 'out of delivery' ||
        status == 'out for delivery' ||
        status == 'driving' ||
        status == 'on the way') {
      return 3;
    }
    if (status == 'ready') return 2;
    if (status == 'preparing') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenWidth < 380 || screenHeight < 760;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Color(0xFF1C1B1F)),
        ),
        title: const Text(
          'Track Order',
          style: TextStyle(
            color: Color(0xFF1C1B1F),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 10 : 14,
                isCompact ? 6 : 8,
                isCompact ? 10 : 14,
                isCompact ? 6 : 8,
              ),
              child: _CustomerOrderStatusTracker(
                currentStepIndex: _trackerStepIndex,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 10 : 14,
                  0,
                  isCompact ? 10 : 14,
                  isCompact ? 6 : 8,
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 10 : 14,
                    isCompact ? 10 : 12,
                    isCompact ? 10 : 14,
                    isCompact ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 12,
                        color: Color(0x12000000),
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _etaLabel,
                            style: TextStyle(
                              fontSize: isCompact ? 14.5 : 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_refreshing) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: isCompact ? 0 : 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF2F2F2),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Symbols.deployed_code,
                                    size: 18,
                                    color: Color(0xFF1C1B1F),
                                  ),
                                ),
                              ],
                            ),
                                SizedBox(width: isCompact ? 8 : 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${_order.transactionId.isEmpty ? '—' : _order.transactionId}',
                                  style: TextStyle(
                                        fontSize: isCompact ? 12.5 : 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Transaction ID',
                                  style: TextStyle(
                                    fontSize: isCompact ? 11 : 12,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF575757),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _statusColor,
                                minimumSize: Size(isCompact ? 78 : 88, isCompact ? 26 : 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _statusLabel,
                            style: TextStyle(
                              fontSize: isCompact ? 10.5 : 11.5,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(height: isCompact ? 8 : 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                              'Driver',
                              style: TextStyle(
                                fontSize: isCompact ? 11 : 12,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF1C1B1F),
                              ),
                            ),
                              const SizedBox(height: 2),
                              Text(
                              _driverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isCompact ? 11.5 : 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Order Cost',
                                style: TextStyle(
                                  fontSize: isCompact ? 11 : 12,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF1C1B1F),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _order.amountFormatted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isCompact ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Created',
                                style: TextStyle(
                                  fontSize: isCompact ? 11 : 12,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF1C1B1F),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _order.createdAtFormatted ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isCompact ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isCompact ? 4 : 6),
                    Container(
                      padding: EdgeInsets.all(isCompact ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('Quantity:', '${_order.quantity}'),
                          const SizedBox(height: 3),
                          _detailRow('Size:', _order.gallonSize),
                          SizedBox(height: isCompact ? 6 : 8),
                          _detailRow('Flavor:', _order.productName),
                          const SizedBox(height: 3),
                          _detailRow('Type:', _order.productType.isEmpty ? '—' : _order.productType),
                          const SizedBox(height: 3),
                          _detailRow('Payment method:', _order.paymentMethod ?? '—'),
                          const SizedBox(height: 3),
                          _detailRow('Delivery address:', _order.deliveryAddress ?? '—', valueMaxLines: 2),
                          const SizedBox(height: 3),
                          _DetailRow(
                            label: 'Contact number:',
                            value: _customerContact,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isCompact ? 6 : 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _openDriverChat,
                            child: Container(
                              height: isCompact ? 46 : 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(35),
                                border: Border.all(color: const Color(0xFF8B8B8B)),
                              ),
                              child: Center(
                                child: Text(
                                  "Message Driver",
                                  style: TextStyle(
                                    color: _canMessageDriver
                                        ? const Color(0xFF494949)
                                        : const Color(0xFF9A9A9A),
                                    fontSize: isCompact ? 13.5 : 14.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: isCompact ? 8 : 10),
                        GestureDetector(
                          onTap: _callDriver,
                          child: Container(
                            height: isCompact ? 46 : 50,
                            width: isCompact ? 46 : 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFF8B8B8B)),
                            ),
                            child: Icon(
                              Icons.call,
                              color: _isOutForDelivery
                                  ? const Color(0xFF494949)
                                  : const Color(0xFF9A9A9A),
                              size: isCompact ? 22 : 24,
                            ),
                          ),
                        ),
                      ],
                    ),
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

Widget _detailRow(String label, String value, {int valueMaxLines = 1}) {
  return _DetailRow(label: label, value: value, valueMaxLines: valueMaxLines);
}

class _CustomerOrderStatusTracker extends StatelessWidget {
  final int currentStepIndex;

  const _CustomerOrderStatusTracker({
    required this.currentStepIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact =
        MediaQuery.of(context).size.width < 380 ||
        MediaQuery.of(context).size.height < 760;
    const steps = <String>[
      'Accepted',
      'Preparing',
      'Ready',
      'On route',
      'Delivered',
    ];
    const stepIcons = <IconData>[
      Icons.assignment_turned_in,
      Icons.restaurant,
      Icons.event_available,
      Icons.local_shipping,
      Icons.check_circle,
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: isCompact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isDone = i < currentStepIndex;
          final isCurrent = i == currentStepIndex;
          final color = (isDone || isCurrent)
              ? const Color(0xFF22B345)
              : const Color(0xFFCFCFCF);

          return Expanded(
            child: _CustomerOrderStatusStep(
              label: steps[i],
              color: color,
              icon: stepIcons[i],
              showConnectorLeft: i != 0,
              showConnectorRight: i != steps.length - 1,
              leftConnectorColor: (i - 1) < currentStepIndex
                  ? const Color(0xFF22B345)
                  : const Color(0xFFCFCFCF),
              rightConnectorColor: i < currentStepIndex
                  ? const Color(0xFF22B345)
                  : const Color(0xFFCFCFCF),
            ),
          );
        }),
      ),
    );
  }
}

class _CustomerOrderStatusStep extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool showConnectorLeft;
  final bool showConnectorRight;
  final Color leftConnectorColor;
  final Color rightConnectorColor;

  const _CustomerOrderStatusStep({
    required this.label,
    required this.color,
    required this.icon,
    required this.showConnectorLeft,
    required this.showConnectorRight,
    required this.leftConnectorColor,
    required this.rightConnectorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: showConnectorLeft
                    ? Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: leftConnectorColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 17,
                  color: color,
                ),
              ),
              Expanded(
                child: showConnectorRight
                    ? Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: rightConnectorColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.8,
            color: Color(0xFF4A4A4A),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueMaxLines = 1,
  });

  final String label;
  final String value;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    final isCompact =
        MediaQuery.of(context).size.width < 380 ||
        MediaQuery.of(context).size.height < 760;

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth * (isCompact ? 0.42 : 0.44);
        return Row(
          crossAxisAlignment: valueMaxLines > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 12.5 : 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF606060),
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: valueMaxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isCompact ? 12.5 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

