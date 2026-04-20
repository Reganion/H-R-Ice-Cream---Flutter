import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/delivery/cd_photo.dart';
import 'package:ice_cream/driver/delivery/delivery_async_buttons.dart';
import 'package:ice_cream/driver/delivery/driver_shipment_id.dart';
import 'package:ice_cream/driver/message/messages.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CompleteDeliveryPage extends StatefulWidget {
  final String? shipmentId;
  final Map<String, dynamic>? initialShipment;

  const CompleteDeliveryPage({
    super.key,
    this.shipmentId,
    this.initialShipment,
  });

  @override
  State<CompleteDeliveryPage> createState() => _CompleteDeliveryPageState();
}

class _CompleteDeliveryPageState extends State<CompleteDeliveryPage> {
  bool _loading = true;
  bool _submitting = false;
  String _error = '';
  Map<String, dynamic>? _shipment;

  @override
  void initState() {
    super.initState();
    _shipment = widget.initialShipment;
    _loadShipment();
  }

  String? get _shipmentId {
    final fromWidget = widget.shipmentId;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return driverShipmentIdFrom(_shipment?['id']);
  }

  String _fmtMoney(dynamic value) {
    if (value == null) return '₱0';
    final s = value.toString();
    if (s.toUpperCase().startsWith('PHP ')) return '₱${s.substring(4)}';
    final n = value is num ? value.toDouble() : double.tryParse(s);
    if (n == null) return s;
    return '₱${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_token');
  }

  Future<void> _loadShipment() async {
    final id = _shipmentId;
    if (id == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Shipment ID is missing.';
      });
      return;
    }

    try {
      final token = await _token();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Missing driver session. Please login again.';
        });
        return;
      }

      final res = await http.get(
        Uri.parse(
          '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(id)}',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;

      if (res.statusCode == 200 && data['success'] == true && data['shipment'] is Map) {
        setState(() {
          _shipment = Map<String, dynamic>.from(data['shipment'] as Map);
          _loading = false;
          _error = '';
        });
      } else {
        setState(() {
          _loading = false;
          _error = (data['message'] ?? 'Could not load shipment.').toString();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load shipment. Check connection.';
      });
    }
  }

  int _statusStepIndex() {
    final raw = (_shipment?['status'] ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return 0;
    if (raw.contains('prepar')) return 1;
    if (raw.contains('ready')) return 2;
    if (raw.contains('route') ||
        raw.contains('on route') ||
        raw.contains('out for delivery') ||
        raw.contains('deliver')) {
      return 3;
    }
    if (raw.contains('complete') || raw.contains('delivered')) return 4;
    if (raw.contains('confirm')) return 0;
    return 0;
  }

  Future<void> _openTakePhotoFlow() async {
    setState(() => _submitting = true);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CompleteDeliveryPhotoPage(
            shipmentId: _shipmentId,
            initialShipment: _shipment,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openChatForCustomer() async {
    final id = _shipmentId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment ID is missing.')),
      );
      return;
    }
    final token = await _token();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing driver session. Please login again.')),
      );
      return;
    }
    final customerName = (_shipment?['customer_name'] ?? 'Customer').toString();
    final customerPhone = (_shipment?['customer_phone'] ?? '').toString();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          shipmentId: id,
          relatedShipmentIds: [id],
          customerName: customerName,
          customerPhone: customerPhone,
        ),
      ),
    );
  }

  String _phoneDigits(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _openCall() async {
    final raw = (_shipment?['customer_phone'] ?? '').toString().trim();
    final cleaned = _phoneDigits(raw);
    if (cleaned.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer phone number is unavailable.')),
      );
      return;
    }
    try {
      final uri = Uri.parse('tel:$cleaned');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer.')),
        );
      }
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone plugin not ready. Please restart app.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer.')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Symbols.arrow_back,
            size: 24,
            color: Color(0xFF414141),
            fill: 1,
            weight: 200,
            grade: 200,
            opticalSize: 24,
          ),
        ),
        title: const Text(
          'Delivery',
          style: TextStyle(
            color: Color(0xFF1C1B1F),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _OrderStatusTracker(currentStepIndex: _statusStepIndex()),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error,
                        style: const TextStyle(
                          color: Color(0xFFE3001B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                        Text(
                          'Expected on: ${(_shipment?['expected_on'] ?? '—').toString()}',
                          style: TextStyle(
                            fontSize: isCompact ? 21 : 23,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1C1B1F),
                          ),
                        ),
                        SizedBox(height: isCompact ? 8 : 10),
                        Row(
                          children: [
                            _CompleteMetricItem(
                              icon: Symbols.deployed_code,
                              value: (_shipment?['transaction_label'] ??
                                      _shipment?['transaction_id'] ??
                                      '—')
                                  .toString(),
                              label: 'Transaction ID',
                              alignCenter: false,
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 10 : 12),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
                        SizedBox(height: isCompact ? 10 : 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Customer',
                                    style: TextStyle(
                                      fontSize: isCompact ? 15 : 16,
                                      color: const Color(0xFF606060),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  Text(
                                    (_shipment?['customer_name'] ?? '—').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: isCompact ? 17 : 18,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1C1B1F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: isCompact ? 8 : 10),
                            _CompleteActionIconButton(
                              icon: Symbols.chat_bubble,
                              onTap: _openChatForCustomer,
                            ),
                            SizedBox(width: isCompact ? 8 : 10),
                            _CompleteActionIconButton(
                              icon: Symbols.call,
                              onTap: _openCall,
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 10 : 12),
                        Text(
                          'Delivery address:',
                          style: TextStyle(
                            fontSize: isCompact ? 15.5 : 16.5,
                            color: const Color(0xFF606060),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          (_shipment?['delivery_address'] ??
                                  _shipment?['location'] ??
                                  '—')
                              .toString(),
                          style: TextStyle(
                            fontSize: isCompact ? 17 : 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1C1B1F),
                            height: 1.35,
                          ),
                        ),
                        SizedBox(height: isCompact ? 10 : 12),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: isCompact ? 10 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CompleteOrderRow(
                                label: 'Quantity:',
                                value: (_shipment?['quantity'] ?? '1').toString(),
                              ),
                              _CompleteOrderRow(
                                label: 'Size:',
                                value: (_shipment?['size'] ?? '—').toString(),
                              ),
                              _CompleteOrderRow(
                                label: 'Order:',
                                value: (_shipment?['order_name'] ??
                                        _shipment?['product_name'] ??
                                        '—')
                                    .toString(),
                              ),
                              _CompleteOrderRow(
                                label: 'Order Type:',
                                value: (_shipment?['order_type'] ?? '—').toString(),
                              ),
                              _CompleteOrderRow(
                                label: 'Total Amount:',
                                value: _fmtMoney(_shipment?['cost_text'] ?? _shipment?['cost']),
                              ),
                              _CompleteOrderRow(
                                label: 'Down Payment:',
                                value: _fmtMoney(_shipment?['downpayment']),
                              ),
                              _CompleteOrderRow(
                                label: 'Balance:',
                                value: _fmtMoney(_shipment?['balance']),
                              ),
                              _CompleteOrderRow(
                                label: 'Customer Number:',
                                value: (_shipment?['customer_phone'] ?? '—').toString(),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isCompact ? 12 : 16),
                        DeliveryFilledPillButton(
                          label: 'Complete delivery',
                          backgroundColor: const Color(0xFF00AE2A),
                          busy: _submitting,
                          enabled: !_loading,
                          verticalPadding: isCompact ? 13 : 16,
                          fontSize: isCompact ? 15 : 16,
                          onPressed: () async {
                            await _openTakePhotoFlow();
                          },
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
    );
  }
}

class _OrderStatusTracker extends StatelessWidget {
  final int currentStepIndex;

  const _OrderStatusTracker({
    required this.currentStepIndex,
  });

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x14000000),
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isDone = i < currentStepIndex;
          final isCurrent = i == currentStepIndex;
          final color = (isDone || isCurrent)
              ? const Color(0xFF00AE2A)
              : const Color(0xFFCFCFCF);

          final icon = stepIcons[i];

          return Expanded(
            child: _OrderStatusStep(
              label: steps[i],
              color: color,
              icon: icon,
              showConnectorLeft: i != 0,
              showConnectorRight: i != steps.length - 1,
              leftConnectorColor: (i - 1) < currentStepIndex
                  ? const Color(0xFF00AE2A)
                  : const Color(0xFFCFCFCF),
              rightConnectorColor: i < currentStepIndex
                  ? const Color(0xFF00AE2A)
                  : const Color(0xFFCFCFCF),
            ),
          );
        }),
      ),
    );
  }
}

class _OrderStatusStep extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool showConnectorLeft;
  final bool showConnectorRight;
  final Color leftConnectorColor;
  final Color rightConnectorColor;

  const _OrderStatusStep({
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
                  color: color.withValues(alpha: 0.12),
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
            fontSize: 11.5,
            color: Color(0xFF4A4A4A),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _CompleteMetricItem extends StatelessWidget {
  final IconData? icon;
  final String value;
  final String label;
  final bool alignCenter;

  const _CompleteMetricItem({
    this.icon,
    required this.value,
    required this.label,
    required this.alignCenter,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 760;

    if (icon != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isCompact ? 32 : 36,
            height: isCompact ? 32 : 36,
            decoration: const BoxDecoration(
              color: Color(0xFFF2F2F2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: isCompact ? 16 : 18, color: const Color(0xFF1C1B1F)),
          ),
          SizedBox(width: isCompact ? 8 : 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: isCompact ? 17 : 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1C1B1F),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 0),
              Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 14 : 15,
                  color: Color(0xFF575757),
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          textAlign: alignCenter ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            fontSize: isCompact ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1C1B1F),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 0),
        Text(
          label,
          textAlign: alignCenter ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            fontSize: isCompact ? 13 : 14,
            color: Color(0xFF8B8B8B),
            fontWeight: FontWeight.w400,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _CompleteOrderRow extends StatelessWidget {
  final String label;
  final String value;

  const _CompleteOrderRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 760;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isCompact ? 4 : 5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 13.5 : 14.5,
                color: const Color(0xFF7A7A7A),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: isCompact ? 13.5 : 14.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1C1B1F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CompleteActionIconButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 760;

    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Colors.black, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: isCompact ? 44 : 48,
          height: isCompact ? 44 : 48,
          child: Icon(
            icon,
            size: isCompact ? 20 : 22,
            color: const Color(0xFF1C1B1F),
            fill: 1,
            weight: 300,
            grade: 200,
            opticalSize: 24,
          ),
        ),
      ),
    );
  }
}
