import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/delivery/delivery_async_buttons.dart';
import 'package:ice_cream/driver/delivery/driver_shipment_id.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cd_success.dart';

/// Photo / submit screen shown after tapping "Complete delivery".
/// Matches design: delivery overview, customer & order, received amount,
/// payment method (GCash / Cash), Take Photo + image display, Submit button.
class CompleteDeliveryPhotoPage extends StatefulWidget {
  final String? shipmentId;
  final Map<String, dynamic>? initialShipment;

  const CompleteDeliveryPhotoPage({
    super.key,
    this.shipmentId,
    this.initialShipment,
  });

  @override
  State<CompleteDeliveryPhotoPage> createState() =>
      _CompleteDeliveryPhotoPageState();
}

class _CompleteDeliveryPhotoPageState extends State<CompleteDeliveryPhotoPage> {
  static const int _maxProofPhotoBytes = 4 * 1024 * 1024; // 4 MB
  final TextEditingController _receivedAmountController =
      TextEditingController();
  int _selectedPaymentMethod = -1; // -1 = none, 0 = GCash, 1 = Cash
  bool _hasPhoto = false;
  String? _photoPath;
  bool _loading = true;
  bool _submitting = false;
  String _error = '';
  Map<String, dynamic>? _shipment;
  final ImagePicker _picker = ImagePicker();

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
        final map = Map<String, dynamic>.from(data['shipment'] as Map);
        setState(() {
          _shipment = map;
          _loading = false;
          _error = '';
          final bal = map['balance'];
          if (bal != null) {
            _receivedAmountController.text =
                (bal is num ? bal.toDouble() : double.tryParse(bal.toString()) ?? 0)
                    .toString();
          }
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

  /// Delivery date text for the header, matching design ("13 Mar 2026").
  /// Prefer explicit delivered_date from API; otherwise, strip time from expected_on.
  String get _deliveryDateText {
    final delivered = (_shipment?['delivered_date'] ?? '').toString().trim();
    if (delivered.isNotEmpty) return delivered;
    final expected = (_shipment?['expected_on'] ?? '').toString().trim();
    if (expected.isEmpty) return '—';
    final commaIndex = expected.indexOf(',');
    if (commaIndex > 0) {
      return expected.substring(0, commaIndex).trim();
    }
    return expected;
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 55,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (!mounted || file == null) return;

    final bytes = await File(file.path).length();
    if (!mounted) return;
    if (bytes > _maxProofPhotoBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photo is too large. Retake photo with less detail or from a bit farther away.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _photoPath = file.path;
      _hasPhoto = true;
    });
  }

  String _paymentMethodValue() {
    if (_selectedPaymentMethod == 0) return 'gcash';
    if (_selectedPaymentMethod == 1) return 'cash';
    return '';
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String body) {
    if (body.trim().isEmpty) return null;
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  Future<void> _submitCompleteDelivery() async {
    if (_submitting) return;

    final id = _shipmentId;
    if (id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shipment ID is missing.')));
      return;
    }

    final amountText = _receivedAmountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Received amount is required.')),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid received amount.')),
      );
      return;
    }

    if (_photoPath == null || _photoPath!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Proof photo is required.')));
      return;
    }

    final paymentMethod = _paymentMethodValue();
    if (paymentMethod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment method is required.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final token = await _token();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing driver session. Please login again.')),
        );
        return;
      }

      final req = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${Auth.apiBaseUrl}/driver/shipments/${driverShipmentIdForPath(id)}/complete',
        ),
      );
      req.headers['Accept'] = 'application/json';
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['received_amount'] = amount.toString();
      req.fields['payment_method'] = paymentMethod;
      req.files.add(await http.MultipartFile.fromPath('proof_photo', _photoPath!));

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      Map<String, dynamic>? data;
      try {
        data = _tryDecodeJsonObject(res.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;
      final is2xx = res.statusCode >= 200 && res.statusCode < 300;
      final successFlag = data?['success'];
      // Some backend responses for multipart endpoints may return empty/non-JSON
      // bodies even when the operation succeeded. Treat 2xx as success unless
      // JSON explicitly says success=false.
      final isSuccess = is2xx && successFlag != false;
      if (isSuccess) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const CompleteDeliverySuccessPage(),
          ),
        );
        return;
      }

      final message =
          data?['message']?.toString() ??
          (res.statusCode == 413
              ? 'Submit failed. Photo file is too large.'
              : is2xx
              ? 'Submit failed. Unexpected server response.'
              : 'Submit failed. Server returned ${res.statusCode}.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on SocketException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submit failed. Check your internet connection.')),
      );
    } on HttpException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submit failed. Network request error.')),
      );
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submit failed. Invalid server response format.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submit failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _receivedAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   elevation: 0,
      //   leading: IconButton(
      //     onPressed: () => Navigator.pop(context),
      //     icon: const Icon(
      //       Symbols.arrow_back,
      //       color: Color(0xFF1C1B1F),
      //       size: 24,
      //       fill: 1,
      //       weight: 200,
      //       grade: 200,
      //       opticalSize: 24,
      //     ),
      //   ),
      //   title: const Text(
      //     'Complete delivery',
      //     style: TextStyle(
      //       fontSize: 18,
      //       fontWeight: FontWeight.w600,
      //       color: Color(0xFF1C1B1F),
      //     ),
      //   ),
      //   centerTitle: true,
      // ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewPadding.bottom;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, 14, 18, bottomInset > 0 ? 6 : 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (bottomInset > 0 ? 6 : 8),
                ),
                child: IntrinsicHeight(
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
            // Delivery date, Time, Delivered time
            Row(
              children: [
                _buildLabelValue(
                  _deliveryDateText,
                  'Delivery date',
                ),
                const SizedBox(width: 16),
                _buildLabelValue(
                  (_shipment?['expected_time'] ?? _shipment?['time'] ?? '—')
                      .toString(),
                  'Time',
                ),
                const SizedBox(width: 16),
                _buildLabelValue(
                  (_shipment?['delivered_time'] ?? '—').toString(),
                  'Delivered time',
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Transaction ID (with package icon)
            Row(
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
                  child: Icon(
                    Symbols.inventory_2,
                    size: 18,
                    color: const Color(0xFF1C1B1F),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildLabelValueColumn(
                    (_shipment?['transaction_label'] ??
                            _shipment?['transaction_id'] ??
                            '—')
                        .toString(),
                    'Transaction ID',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
            const SizedBox(height: 4),
            const Text(
              'Customer',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF606060),
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              (_shipment?['customer_name'] ?? '—').toString(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1B1F),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Delivery address:',
              style: TextStyle(
                fontSize: 13.67,
                color: Color(0xFF606060),
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              (_shipment?['delivery_address'] ?? _shipment?['location'] ?? '—')
                  .toString(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1B1F),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderRow(
                    'Quantity:',
                    (_shipment?['quantity'] ?? '1').toString(),
                  ),
                  _buildOrderRow(
                    'Size:',
                    (_shipment?['size'] ?? '—').toString(),
                  ),
                  _buildOrderRow(
                    'Order:',
                    (_shipment?['order_name'] ?? _shipment?['product_name'] ?? '—')
                        .toString(),
                  ),
                  _buildOrderRow(
                    'Order Type:',
                    (_shipment?['order_type'] ?? '—').toString(),
                  ),
                  _buildOrderRow(
                    'Cost:',
                    _fmtMoney(_shipment?['cost_text'] ?? _shipment?['cost']),
                  ),
                  _buildOrderRow(
                    'Down Payment:',
                    _fmtMoney(_shipment?['downpayment']),
                  ),
                  _buildOrderRow(
                    'Balance:',
                    _fmtMoney(_shipment?['balance']),
                  ),
                  _buildOrderRow(
                    'Customer Number:',
                    (_shipment?['customer_phone'] ?? '—').toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Received Amount (label and field vertically aligned in a row)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Received\nAmount',
                  style: TextStyle(
                    fontSize: 13.67,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1B1F),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _receivedAmountController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Enter amount',
                      hintStyle: const TextStyle(
                        fontSize: 13.67,
                        color: Color(0xFF8B8B8B),
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF2F2F2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Color(
                            0xFFCECECE,
                          ), // Set border color to #CECECE
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Color(0xFFCECECE),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Color(0xFFCECECE),
                          width: 1,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Payment Method
            // Payment Method (label and buttons vertically aligned in a row)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Payment\nMethod',
                  style: TextStyle(
                    fontSize: 13.67,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1B1F),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _PaymentMethodButton(
                          label: 'GCash',
                          iconWidget: Image.asset(
                            "lib/client/order/images/gcsh.png",
                            width: 26,
                            height: 26,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 22,
                              color: Color(0xFF002CB8),
                            ),
                          ),
                          iconColor: const Color(0xFF002CB8),

                          isSelected: _selectedPaymentMethod == 0,
                          onTap: () =>
                              setState(() => _selectedPaymentMethod = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PaymentMethodButton(
                          label: 'Cash',
                          iconWidget: Image.asset(
                            "lib/driver/delivery/images/cod.png",
                            width: 28,
                            height: 28,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.payments_rounded,
                              size: 22,
                              color: Color(0xFF00AE2A),
                            ),
                          ),
                          iconColor: const Color(0xFF00AE2A),
                          isSelected: _selectedPaymentMethod == 1,
                          onTap: () =>
                              setState(() => _selectedPaymentMethod = 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Take Photo + Image display
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: _PhotoCard(
                    icon: Icons.camera_alt,
                    label: 'Take Photo',
                    backgroundColor: const Color(0xFFF2F2F2),
                    iconColor: Colors.black,
                    height: 110,
                    onTap: () {
                      _takePhoto();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _PhotoCard(
                      icon: null,
                      label: '',
                      showPlaceholder: !_hasPhoto,
                      imagePath: _photoPath,
                      onTap: () {
                        _takePhoto();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),

                    // Submit button (green) – onTap shows CompleteDeliverySuccessPage
                    DeliveryFilledPillButton(
                      label: 'Submit',
                      backgroundColor: const Color(0xFF00AE2A),
                      busy: _submitting,
                      enabled: !_loading,
                      verticalPadding: 14,
                      fontSize: 16,
                      onPressed: _submitCompleteDelivery,
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLabelValue(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1B1F),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8B8B8B),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValueColumn(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1B1F),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8B8B8B),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildOrderRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF606060),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1B1F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  final String label;
  final Widget iconWidget;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodButton({
    required this.label,
    required this.iconWidget,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2F2F2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? iconColor : const Color(0xFFE0E0E0),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool showPlaceholder;
  final String? imagePath;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? height;
  final VoidCallback onTap;

  const _PhotoCard({
    this.icon,
    required this.label,
    this.showPlaceholder = true,
    this.imagePath,
    this.backgroundColor,
    this.iconColor,
    this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Colors.white;
    final contentColor = iconColor ?? const Color(0xFF606060);
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height ?? 72,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: backgroundColor != null
                ? null
                : Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: showPlaceholder && imagePath == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 24, color: contentColor),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: contentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                )
              : imagePath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(imagePath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 36, color: contentColor),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          color: contentColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
