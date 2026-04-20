import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/delivery/driver_shipment_id.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeliveryViewDetailsPage extends StatefulWidget {
  final String? shipmentId;
  final Map<String, dynamic>? initialShipment;

  const DeliveryViewDetailsPage({
    super.key,
    this.shipmentId,
    this.initialShipment,
  });

  @override
  State<DeliveryViewDetailsPage> createState() => _DeliveryViewDetailsPageState();
}

class _DeliveryViewDetailsPageState extends State<DeliveryViewDetailsPage> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _shipment;
  String? _driverBearerToken;

  @override
  void initState() {
    super.initState();
    _shipment = widget.initialShipment;
    _syncDriverTokenForImages();
    _loadShipment();
  }

  Future<void> _syncDriverTokenForImages() async {
    final t = await _token();
    if (!mounted) return;
    if (t != null && t.isNotEmpty) {
      setState(() => _driverBearerToken = t);
    }
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
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        data = null;
      }
      if (!mounted) return;
      if (res.statusCode == 200 && data != null && data['success'] == true && data['shipment'] is Map) {
        setState(() {
          _shipment = Map<String, dynamic>.from(data!['shipment'] as Map);
          _loading = false;
          _error = '';
        });
      } else {
        setState(() {
          _loading = false;
          _error = (data?['message'] ?? 'Could not load shipment.').toString();
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

  /// Build full URL for delivery proof image (mirrors Laravel `asset('storage/...')`).
  ///
  /// Full URLs from the API are left unchanged except optional host remap. Relative
  /// paths are joined to the web root derived from [Auth.apiBaseUrl] (strip `/api/v1`).
  /// **Do not** use [Uri.resolve] with an absolute `/storage/...` path: it replaces
  /// the entire path and drops `APP_URL` subfolders (XAMPP / subfolder installs).
  String _resolveProofImageUrl(String raw) {
    var value = raw.trim().replaceAll(r'\', '/');
    if (value.isEmpty || value.toLowerCase() == 'null') return '';

    // DB may store "public/delivery-proofs/..." — strip public/ for URL under /storage/.
    if (value.toLowerCase().startsWith('public/')) {
      value = value.substring(7);
    }

    final baseStr =
        Auth.apiBaseUrl.replaceAll('/api/v1', '').replaceAll(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(baseStr);
    final apiUri = Uri.tryParse(Auth.apiBaseUrl);
    if (baseUri == null) return value;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      final remote = Uri.tryParse(value);
      if (remote == null) return value;
      const localHosts = {'localhost', '127.0.0.1', '::1'};
      final pathLower = remote.path.toLowerCase();
      final looksLikeProof =
          pathLower.contains('delivery-proof') || pathLower.contains('/storage/');
      final shouldRemapHost = apiUri != null &&
          remote.host.isNotEmpty &&
          remote.host.toLowerCase() != apiUri.host.toLowerCase() &&
          (localHosts.contains(remote.host.toLowerCase()) || looksLikeProof);
      if (shouldRemapHost) {
        final remapped = remote.replace(
          scheme: apiUri.scheme,
          host: apiUri.host,
          port: apiUri.hasPort ? apiUri.port : null,
        );
        return remapped.toString();
      }
      return value;
    }

    var path = value.startsWith('/') ? value : '/$value';
    final lower = path.toLowerCase();
    if (lower.startsWith('/storage/storage/')) {
      path = '/storage/${path.substring('/storage/storage/'.length)}';
    }
    if (!path.toLowerCase().startsWith('/storage/')) {
      path = '/storage$path';
    }
    return _joinWebRootWithStoragePath(baseUri, path);
  }

  /// Append `/storage/...` under the same path segment as the API (e.g. `/app/public`).
  static String _joinWebRootWithStoragePath(Uri webRoot, String storageAbsPath) {
    final p = storageAbsPath.startsWith('/') ? storageAbsPath : '/$storageAbsPath';
    var root = webRoot.path.replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty || root == '/') {
      return webRoot.replace(path: p).toString();
    }
    return webRoot.replace(path: '$root$p').toString();
  }

  String _proofImageRawFromShipment() {
    final s = _shipment;
    if (s == null) return '';
    final candidates = <dynamic>[
      s['delivery_proof_url'],
      s['proof_image_url'],
      s['delivery_proof_image'],
      s['proof_image'],
    ];
    return _firstNonEmpty(candidates, fallback: '');
  }

  String _firstNonEmpty(Iterable<dynamic> values, {String fallback = '—'}) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return fallback;
  }

  String _formatYmdDate(String value) {
    final date = DateTime.tryParse(value.trim());
    if (date == null) return value;
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _toShortMonthDate(String value) {
    final input = value.trim();
    if (input.isEmpty || input == '—' || input.toLowerCase() == 'null') return '—';

    // Try direct parse first (works for ISO-like strings).
    final parsed = DateTime.tryParse(input);
    if (parsed != null) {
      return _formatYmdDate(parsed.toIso8601String());
    }

    // Convert "10 March 2026" -> "10 Mar 2026".
    const fullToShort = <String, String>{
      'january': 'Jan',
      'february': 'Feb',
      'march': 'Mar',
      'april': 'Apr',
      'may': 'May',
      'june': 'Jun',
      'july': 'Jul',
      'august': 'Aug',
      'september': 'Sep',
      'october': 'Oct',
      'november': 'Nov',
      'december': 'Dec',
    };
    final parts = input.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final month = parts[1].toLowerCase();
      final short = fullToShort[month];
      if (short != null) {
        parts[1] = short;
        return '${parts[0]} ${parts[1]} ${parts[2]}';
      }
    }
    return input;
  }

  String _formatDisplayTime(String value) {
    final input = value.trim();
    if (input.isEmpty || input == '—' || input.toLowerCase() == 'null') return '—';

    // 12-hour input like "9:10 PM" or "09:10PM".
    final twelveHour = RegExp(r'^(\d{1,2}):(\d{2})\s*([aApP][mM])$');
    final m12 = twelveHour.firstMatch(input);
    if (m12 != null) {
      final hour = int.tryParse(m12.group(1) ?? '');
      final minute = m12.group(2) ?? '00';
      final suffix = (m12.group(3) ?? '').toUpperCase();
      if (hour != null && hour >= 1 && hour <= 12) {
        return '${hour.toString().padLeft(2, '0')}:$minute$suffix';
      }
    }

    // 24-hour input like "21:10".
    final twentyFourHour = RegExp(r'^(\d{1,2}):(\d{2})$');
    final m24 = twentyFourHour.firstMatch(input);
    if (m24 != null) {
      final h24 = int.tryParse(m24.group(1) ?? '');
      final minute = m24.group(2) ?? '00';
      if (h24 != null && h24 >= 0 && h24 <= 23) {
        final isPm = h24 >= 12;
        final h12 = (h24 % 12 == 0) ? 12 : (h24 % 12);
        return '${h12.toString().padLeft(2, '0')}:$minute${isPm ? 'PM' : 'AM'}';
      }
    }

    // 24-hour input with seconds like "21:10:00".
    final twentyFourWithSeconds = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})$');
    final m24s = twentyFourWithSeconds.firstMatch(input);
    if (m24s != null) {
      final h24 = int.tryParse(m24s.group(1) ?? '');
      final minute = m24s.group(2) ?? '00';
      if (h24 != null && h24 >= 0 && h24 <= 23) {
        final isPm = h24 >= 12;
        final h12 = (h24 % 12 == 0) ? 12 : (h24 % 12);
        return '${h12.toString().padLeft(2, '0')}:$minute${isPm ? 'PM' : 'AM'}';
      }
    }

    return input;
  }

  String _formatIsoToCompactTime(String value) {
    final dt = DateTime.tryParse(value.trim());
    if (dt == null) return '';
    final isPm = dt.hour >= 12;
    final h12 = (dt.hour % 12 == 0) ? 12 : (dt.hour % 12);
    final hh = h12.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm${isPm ? 'PM' : 'AM'}';
  }

  String _datePartFromSchedule(String schedule) {
    final s = schedule.trim();
    if (s.isEmpty || s == '—') return '—';
    final parts = s.split(',');
    return parts.first.trim();
  }

  String _timePartFromSchedule(String schedule) {
    final s = schedule.trim();
    if (s.isEmpty || s == '—') return '—';
    final parts = s.split(',');
    if (parts.length < 2) return '—';
    return parts.sublist(1).join(',').trim();
  }

  @override
  Widget build(BuildContext context) {
    const Color kText = Color(0xFF111111);
    const Color kMuted = Color(0xFF606060);
    final scheduleText = (_shipment?['expected_on'] ?? '—').toString();
    final rawDeliveryDate = _shipment?['delivery_date'];
    final deliveredDateFromApi = _toShortMonthDate(
      (_shipment?['delivered_date'] ?? '').toString(),
    );
    final deliveredDate = _firstNonEmpty([
      deliveredDateFromApi,
      rawDeliveryDate != null ? _formatYmdDate(rawDeliveryDate.toString()) : null,
      _datePartFromSchedule(scheduleText),
      scheduleText,
    ]);
    final deliveredTimeRaw = _firstNonEmpty([
      _shipment?['delivery_time_compact'],
      _formatDisplayTime((_shipment?['delivery_time'] ?? '').toString()),
      _shipment?['delivered_time_compact'],
      _shipment?['delivered_time'],
      _formatIsoToCompactTime((_shipment?['delivered_at'] ?? '').toString()),
      _shipment?['expected_time'],
      _shipment?['time'],
      _timePartFromSchedule(scheduleText),
    ]);
    final deliveredTime = _formatDisplayTime(deliveredTimeRaw);
    final imageUrl = _resolveProofImageUrl(_proofImageRawFromShipment());

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F6F6),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Symbols.arrow_back,
            color: kText,
            fill: 1,
            weight: 300,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: Color(0xFFE3001B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _TopMeta(
                    title: deliveredDate,
                    subtitle: 'Delivered',
                    titleFontSize: 26,
                    subtitleFontSize: 13,
                  ),
                ),
                Expanded(
                  child: _TopMeta(
                    title: deliveredTime,
                    subtitle: 'Time',
                    titleFontSize: 26,
                    subtitleFontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _TransactionBadge(
              transactionId: (_shipment?['transaction_label'] ??
                      _shipment?['transaction_id'] ??
                      '—')
                  .toString(),
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: const Color(0xFFD9D9D9),
            ),
            const SizedBox(height: 10),
            const Text(
              'Customer',
              style: TextStyle(
                color: kMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (_shipment?['customer_name'] ?? '—').toString(),
              style: const TextStyle(
                color: kText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Delivery address:',
              style: TextStyle(
                color: kMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (_shipment?['delivery_address'] ?? _shipment?['location'] ?? '—').toString(),
              style: const TextStyle(
                color: kText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFEFEF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _InfoRow(label: 'Quantity:', value: (_shipment?['quantity'] ?? '1').toString()),
                  _InfoRow(label: 'Gallon:', value: (_shipment?['size'] ?? '—').toString()),
                  _InfoRow(
                    label: 'Flavor:',
                    value: (_shipment?['order_name'] ?? _shipment?['product_name'] ?? '—')
                        .toString(),
                  ),
                  _InfoRow(
                    label: 'Flavor Type:',
                    value: (_shipment?['order_type'] ?? '—').toString(),
                  ),
                  _InfoRow(
                    label: 'Cost:',
                    value: _fmtMoney(_shipment?['cost_text'] ?? _shipment?['cost']),
                  ),
                  _InfoRow(
                    label: 'Amount:',
                    value: _fmtMoney(
                      _shipment?['received_amount'] ??
                          _shipment?['amount_text'] ??
                          _shipment?['amount'],
                    ),
                  ),
                  _InfoRow(
                    label: 'Payment Method:',
                    value: _firstNonEmpty([_shipment?['delivery_payment_method']]),
                  ),
                  _InfoRow(
                    label: 'Customer Number:',
                    value: (_shipment?['customer_phone'] ?? '—').toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Proof of Delivery:',
              style: TextStyle(
                color: kText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: imageUrl.isNotEmpty
                    ? _DeliveryProofImage(
                        key: ValueKey(imageUrl),
                        imageUrl: imageUrl,
                        bearerToken: _driverBearerToken,
                      )
                    : Container(
                        color: const Color(0xFFE1E1E1),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          color: Color(0xFF8B8B8B),
                          size: 34,
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

/// Loads proof bytes via [http] (public `/storage/` first, then Bearer) so loading
/// matches Laravel symlink behavior and avoids [Image.network] header quirks.
class _DeliveryProofImage extends StatefulWidget {
  const _DeliveryProofImage({
    super.key,
    required this.imageUrl,
    this.bearerToken,
  });

  final String imageUrl;
  final String? bearerToken;

  @override
  State<_DeliveryProofImage> createState() => _DeliveryProofImageState();
}

class _DeliveryProofImageState extends State<_DeliveryProofImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DeliveryProofImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.bearerToken != widget.bearerToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _bytes = null;
        });
      }
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _bytes = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _bytes = null;
      });
    }

    try {
      final bytes = await _fetchProofBytes(uri, widget.bearerToken);
      if (!mounted) return;
      final ok = bytes != null && bytes.isNotEmpty;
      setState(() {
        _bytes = ok ? bytes : null;
        _loading = false;
        _failed = !ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _bytes = null;
      });
    }
  }

  static Future<Uint8List?> _fetchProofBytes(Uri uri, String? bearer) async {
    const accept = {'Accept': 'image/*'};

    Future<http.Response> get(Map<String, String> headers) =>
        http.get(uri, headers: headers);

    // Prefer unauthenticated: Laravel public storage is usually open; some stacks
    // mis-handle Authorization on static files.
    var res = await get(accept);
    if (_responseLooksLikeImage(res)) return res.bodyBytes;

    if (bearer != null && bearer.isNotEmpty) {
      res = await get({
        ...accept,
        'Authorization': 'Bearer $bearer',
      });
      if (_responseLooksLikeImage(res)) return res.bodyBytes;
    }

    return null;
  }

  static bool _responseLooksLikeImage(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) return false;
    if (res.bodyBytes.isEmpty) return false;
    final ct = res.headers['content-type']?.toLowerCase() ?? '';
    if (ct.contains('text/html')) return false;
    if (ct.contains('application/json')) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: const Color(0xFFE1E1E1),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_failed || _bytes == null) {
      return Container(
        color: const Color(0xFFE1E1E1),
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_outlined,
          color: Color(0xFF8B8B8B),
          size: 34,
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  }
}

class _TopMeta extends StatelessWidget {
  const _TopMeta({
    required this.title,
    required this.subtitle,
    this.titleFontSize = 26,
    this.subtitleFontSize = 13,
  });

  final String title;
  final String subtitle;
  final double titleFontSize;
  final double subtitleFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF111111),
            fontSize: titleFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: const Color(0xFF606060),
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TransactionBadge extends StatelessWidget {
  final String transactionId;

  const _TransactionBadge({required this.transactionId});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEFEFEF),
            ),
            child: const Icon(
              Symbols.deployed_code,
              color: Color(0xFF2A2A2A),
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transactionId,
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Transaction ID',
                style: TextStyle(
                  color: Color(0xFF606060),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF606060),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
