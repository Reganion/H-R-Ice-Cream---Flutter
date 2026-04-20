import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/home_page.dart';
import 'package:ice_cream/client/order/payment_success.dart';
import 'package:intl/intl.dart';

/// QRPH downpayment screen.
/// - Shown after Place Order when payment method is Gcash/QRPH.
/// - Cancel Payment (bottom): marks invoice as failed via cancel API, then goes Home with an "Order failed" banner.
/// - Status is polled every few seconds; when paid, success is shown and user goes Home (no button press needed).
/// - "I have paid" button: optional immediate check.
class QrphPage extends StatefulWidget {
  const QrphPage({
    super.key,
    required this.invoiceId,
    this.orderId,
    required this.qrImageUrl,
    required this.downpaymentAmount,
  });

  /// Builds from [POST /orders/downpayment] `data` map. Never uses [int.parse] on ids.
  factory QrphPage.fromDownpaymentData(
    Map<String, dynamic> data, {
    required String qrImageUrl,
    required double downpaymentAmount,
  }) {
    final invRaw = data['invoice_id'];
    final invoiceId = invRaw == null ? '' : invRaw.toString().trim();
    final orderRaw = data['order_id'];
    String? orderId;
    if (orderRaw != null) {
      final s = orderRaw.toString().trim();
      orderId = s.isEmpty ? null : s;
    }
    return QrphPage(
      invoiceId: invoiceId,
      orderId: orderId,
      qrImageUrl: qrImageUrl,
      downpaymentAmount: downpaymentAmount,
    );
  }

  /// Firestore document id (often non-numeric); must not be parsed as int.
  final String invoiceId;
  /// Null until payment succeeds; backend creates order only after downpayment is paid.
  final String? orderId;
  final String qrImageUrl;
  final double downpaymentAmount;

  @override
  State<QrphPage> createState() => _QrphPageState();
}

class _QrphPageState extends State<QrphPage> {
  bool _checkingStatus = false;
  bool _cancelPaymentBusy = false;
  Timer? _pollTimer;
  bool _alreadyHandledPaid = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Background poll: only shows UI when paid or failed; pending does nothing.
  Future<void> _pollStatus() async {
    if (_alreadyHandledPaid || !mounted) return;
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) return;
    final base = Auth.apiBaseUrl;
    try {
      final res = await http.get(
        Uri.parse('$base/orders/downpayment/status/${Uri.encodeComponent(widget.invoiceId)}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (!mounted || _alreadyHandledPaid) return;
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as Map?) ?? {};
      final invoiceStatus = (data['invoice_status'] ?? '').toString();
      final orderStatus = (data['order_status'] ?? '').toString();
      final paymentStatus = (data['payment_status'] ?? '').toString();

      if (invoiceStatus == 'paid') {
        _alreadyHandledPaid = true;
        _stopPolling();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PaymentSuccessPage()),
          (route) => false,
        );
      } else if (invoiceStatus == 'failed' || orderStatus == 'cancelled' || paymentStatus == 'failed') {
        _stopPolling();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downpayment failed or was cancelled. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      // ignore errors in background poll
    }
  }

  Uint8List _decodeQrData(String src) {
    final parts = src.split(',');
    final base64Str = parts.length > 1 ? parts.last : parts.first;
    return base64Decode(base64Str);
  }

  Future<void> _checkStatus() async {
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in again to check payment status.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final base = Auth.apiBaseUrl;
    setState(() => _checkingStatus = true);
    try {
      final res = await http.get(
        Uri.parse('$base/orders/downpayment/status/${Uri.encodeComponent(widget.invoiceId)}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (!mounted) return;
      setState(() => _checkingStatus = false);
      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch payment status (code ${res.statusCode}).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as Map?) ?? {};
      final invoiceStatus = (data['invoice_status'] ?? '').toString();
      final orderStatus = (data['order_status'] ?? '').toString();
      final paymentStatus = (data['payment_status'] ?? '').toString();

      if (invoiceStatus == 'paid') {
        _alreadyHandledPaid = true;
        _stopPolling();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PaymentSuccessPage()),
          (route) => false,
        );
      } else if (invoiceStatus == 'failed' || orderStatus == 'cancelled' || paymentStatus == 'failed') {
        _stopPolling();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downpayment failed or was cancelled. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment still pending. Please complete the scan in your wallet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingStatus = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not check status: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Cancel payment: mark invoice as failed via API, then go Home with "Order failed" banner.
  Future<void> _cancelAndGoBack() async {
    if (_cancelPaymentBusy || _checkingStatus) return;
    _stopPolling();
    setState(() => _cancelPaymentBusy = true);
    final token = await Auth.getApiToken();
    if (token != null && token.isNotEmpty) {
      final base = Auth.apiBaseUrl;
      try {
        await http.post(
          Uri.parse('$base/orders/downpayment/cancel/${Uri.encodeComponent(widget.invoiceId)}'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {
        // still navigate home even if request fails
      }
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const HomePage(showOrderFailedBanner: true),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final amountLabel = NumberFormat('#,##0.00').format(widget.downpaymentAmount);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Scan to Pay",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: ColoredBox(
            color: Color(0xFFE3001B),
            child: SizedBox(height: 4),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      "Scan Here to Pay",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1B1F),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Downpayment: ₱$amountLabel",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF505050),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8E8E8)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: widget.qrImageUrl.startsWith('data:image')
                            ? Image.memory(
                                _decodeQrData(widget.qrImageUrl),
                                width: 220,
                                height: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stackTrace) {
                                  print('QR load error (memory): $error');
                                  return const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(
                                      child: Text(
                                        'Unable to load QR code.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Image.network(
                                widget.qrImageUrl,
                                width: 220,
                                height: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stackTrace) {
                                  print('QR load error (network): $error');
                                  return const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(
                                      child: Text(
                                        'Unable to load QR code.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Open your mobile wallet and scan this QRPH code to pay the downpayment.",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE3001B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: (_checkingStatus || _cancelPaymentBusy)
                            ? null
                            : _checkStatus,
                        child: _checkingStatus
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                "I have paid, check status",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: (_cancelPaymentBusy || _checkingStatus) ? null : _cancelAndGoBack,
                  child: _cancelPaymentBusy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Cancel Payment',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF505050),
                          ),
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

