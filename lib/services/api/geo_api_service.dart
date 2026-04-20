import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/services/api/geo_polyline_decode.dart';
import 'package:ice_cream/services/api/models/geo_models.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Laravel geo + live tracking API (`/api/v1/...`).
class GeoApiService {
  GeoApiService._();

  static final GeoApiService instance = GeoApiService._();

  static String get _base => Auth.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  MapsConfig? _mapsConfigCache;

  /// Clears cached maps config (e.g. after env switch).
  void clearMapsConfigCache() => _mapsConfigCache = null;

  /// GET /geo/maps-config (public). Optional [provider] query: `google` | `osm`.
  Future<MapsConfig> getMapsConfig({String? provider, bool forceRefresh = false}) async {
    if (!forceRefresh && _mapsConfigCache != null) {
      return _mapsConfigCache!;
    }
    final q = <String, String>{};
    if (provider != null && provider.isNotEmpty) {
      q['provider'] = provider;
    }
    final uri = q.isEmpty
        ? Uri.parse('$_base/geo/maps-config')
        : Uri.parse('$_base/geo/maps-config').replace(queryParameters: q);
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GeoApiException('maps-config failed (${res.statusCode})', statusCode: res.statusCode);
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw GeoApiException('Invalid JSON for maps-config: $e');
    }
    final config = MapsConfig.fromJson(json);
    _mapsConfigCache = config;
    return config;
  }

  /// GET /geo/orders/{orderId}/track — customer Bearer token.
  Future<GeoTrackResult> fetchTrackForCustomer(String orderId) async {
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      return const GeoTrackResult.error('Not signed in.');
    }
    final uri = Uri.parse('$_base/geo/orders/${Uri.encodeComponent(orderId)}/track');
    final res = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    return _parseTrackResponse(res);
  }

  /// GET /driver/geo/orders/{orderId}/track — driver Bearer token.
  Future<GeoTrackResult> fetchTrackForDriver(String orderId) async {
    final token = await _driverToken();
    if (token == null || token.isEmpty) {
      return const GeoTrackResult.error('Driver session missing.');
    }
    final uri = Uri.parse('$_base/driver/geo/orders/${Uri.encodeComponent(orderId)}/track');
    final res = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    return _parseTrackResponse(res);
  }

  /// POST /driver/geo/location — driver Bearer token. [orderId] optional.
  Future<GeoVoidResult> postDriverLocation({
    String? orderId,
    required double lat,
    required double lng,
  }) async {
    final token = await _driverToken();
    if (token == null || token.isEmpty) {
      return const GeoVoidResult.error('Driver session missing.');
    }
    final uri = Uri.parse('$_base/driver/geo/location');
    final body = <String, dynamic>{'lat': lat, 'lng': lng};
    final oid = orderId?.trim();
    if (oid != null && oid.isNotEmpty) {
      body['order_id'] = oid;
    }
    try {
      final res = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return GeoVoidResult.error('Location update failed (${res.statusCode})', statusCode: res.statusCode);
      }
      try {
        final m = jsonDecode(res.body) as Map<String, dynamic>?;
        if (m?['success'] == false) {
          return GeoVoidResult.error((m?['message'] ?? 'Rejected').toString(), statusCode: res.statusCode);
        }
      } catch (_) {}
      return const GeoVoidResult.ok();
    } catch (e) {
      return GeoVoidResult.error(e.toString());
    }
  }

  Future<String?> _driverToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_token');
  }

  GeoTrackResult _parseTrackResponse(http.Response res) {
    if (res.statusCode == 401) {
      return const GeoTrackResult.error('Unauthorized.');
    }
    if (res.statusCode == 404) {
      return const GeoTrackResult.error('Order not found.');
    }
    if (res.statusCode != 200) {
      return GeoTrackResult.error('Track failed (${res.statusCode})', statusCode: res.statusCode);
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {
      return const GeoTrackResult.error('Invalid track JSON.');
    }
    if (body == null) {
      return const GeoTrackResult.error('Empty track response.');
    }

    final dest = _parseLatLng(body['destination']);
    final driverMap = body['driver'];
    LatLng? driverLoc;
    String driverName = '';
    String? driverUpdated;
    if (driverMap is Map) {
      final dm = Map<String, dynamic>.from(driverMap);
      driverName = (dm['name'] ?? '').toString();
      driverUpdated = dm['last_updated']?.toString();
      driverLoc = _parseLatLng(dm['location']);
    }

    LatLng? customerLoc;
    String? customerUpdated;
    final custRaw = body['customer_location'];
    if (custRaw is Map) {
      final cm = Map<String, dynamic>.from(custRaw);
      customerLoc = _parseLatLng(cm);
      customerUpdated = cm['updated_at']?.toString();
    }

    final routePoints = decodeRoutePolyline(body['route']);

    return GeoTrackResult.ok(
      TrackSnapshot(
        destination: dest,
        driverLocation: driverLoc,
        routePoints: routePoints,
        driverName: driverName,
        driverLastUpdated: driverUpdated,
        status: (body['status'] ?? '').toString(),
        deliveryAddress: (body['delivery_address'] ?? '').toString(),
        customerLocation: customerLoc,
        customerLocationUpdatedAt: customerUpdated,
      ),
    );
  }

  /// POST /geo/customer/location — customer Bearer token (shares live position for the order).
  Future<GeoVoidResult> postCustomerLocation({
    required String orderId,
    required double lat,
    required double lng,
  }) async {
    final token = await Auth.getApiToken();
    if (token == null || token.isEmpty) {
      return const GeoVoidResult.error('Not signed in.');
    }
    final uri = Uri.parse('$_base/geo/customer/location');
    try {
      final res = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'order_id': orderId,
          'lat': lat,
          'lng': lng,
        }),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return GeoVoidResult.error('Location update failed (${res.statusCode})', statusCode: res.statusCode);
      }
      try {
        final m = jsonDecode(res.body) as Map<String, dynamic>?;
        if (m?['success'] == false) {
          return GeoVoidResult.error((m?['message'] ?? 'Rejected').toString(), statusCode: res.statusCode);
        }
      } catch (_) {}
      return const GeoVoidResult.ok();
    } catch (e) {
      return GeoVoidResult.error(e.toString());
    }
  }

  static LatLng? _parseLatLng(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final lat = m['lat'];
    final lng = m['lng'];
    if (lat == null || lng == null) return null;
    final la = double.tryParse(lat.toString());
    final lo = double.tryParse(lng.toString());
    if (la == null || lo == null) return null;
    if (la == 0.0 && lo == 0.0) return null;
    return LatLng(la, lo);
  }
}

class GeoApiException implements Exception {
  GeoApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class GeoTrackResult {
  const GeoTrackResult._(this.snapshot, this.errorMessage, this.statusCode);

  const GeoTrackResult.ok(TrackSnapshot s) : this._(s, null, null);

  const GeoTrackResult.error(String msg, {int? statusCode}) : this._(null, msg, statusCode);

  final TrackSnapshot? snapshot;
  final String? errorMessage;
  final int? statusCode;

  bool get isSuccess => snapshot != null;
}

class GeoVoidResult {
  const GeoVoidResult._(this.ok, this.errorMessage, this.statusCode);

  const GeoVoidResult.ok() : this._(true, null, null);

  const GeoVoidResult.error(String msg, {int? statusCode}) : this._(false, msg, statusCode);

  final bool ok;
  final String? errorMessage;
  final int? statusCode;
}

