import 'package:latlong2/latlong.dart';

/// Backend map provider for live tracking UI.
enum MapProviderKind {
  google,
  osm,
  unknown,
}

/// GET /geo/maps-config — tiles + optional Google key reference.
class MapsConfig {
  const MapsConfig({
    required this.provider,
    this.googleApiKey,
    this.osmTileUrlTemplate,
    this.osmAttribution,
  });

  final MapProviderKind provider;
  final String? googleApiKey;
  final String? osmTileUrlTemplate;
  final String? osmAttribution;

  bool get isGoogle => provider == MapProviderKind.google;
  bool get isOsm => provider == MapProviderKind.osm;

  /// Default OSM raster template if backend omits it.
  static const String defaultOsmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static MapsConfig fromJson(Map<String, dynamic> json) {
    final root = _unwrapData(json);
    final p = (root['provider'] ?? root['map_provider'] ?? '').toString().toLowerCase().trim();
    MapProviderKind kind = MapProviderKind.unknown;
    if (p == 'google' || p == 'gmaps') {
      kind = MapProviderKind.google;
    } else if (p == 'osm' || p == 'openstreetmap' || p == 'flutter_map') {
      kind = MapProviderKind.osm;
    }

    String? gKey;
    final gm = root['google_maps'] ?? root['google'];
    if (gm is Map) {
      final m = Map<String, dynamic>.from(gm);
      gKey = _stringOrNull(m['api_key'] ?? m['apiKey']);
    }
    gKey ??= _stringOrNull(root['google_maps_api_key']);

    String? tileUrl;
    String? attr;
    final osm = root['osm'];
    if (osm is Map) {
      final m = Map<String, dynamic>.from(osm);
      tileUrl = _stringOrNull(m['tile_url_template'] ?? m['url_template'] ?? m['urlTemplate']);
      // Backend may return `attribution` or `tile_attribution`.
      attr = _stringOrNull(m['tile_attribution'] ?? m['attribution'] ?? m['credit']);
    }

    if (kind == MapProviderKind.osm && (tileUrl == null || tileUrl.isEmpty)) {
      tileUrl = defaultOsmTileUrl;
    }
    if (kind == MapProviderKind.osm && (attr == null || attr.isEmpty)) {
      attr = '© OpenStreetMap contributors';
    }

    return MapsConfig(
      provider: kind,
      googleApiKey: gKey,
      osmTileUrlTemplate: tileUrl,
      osmAttribution: attr,
    );
  }

  static Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
    final d = json['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return json;
  }

  static String? _stringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Normalized track payload from customer or driver GET …/track.
class TrackSnapshot {
  const TrackSnapshot({
    required this.destination,
    required this.driverLocation,
    required this.routePoints,
    required this.driverName,
    required this.driverLastUpdated,
    required this.status,
    required this.deliveryAddress,
    this.customerLocation,
    this.customerLocationUpdatedAt,
  });

  final LatLng? destination;
  final LatLng? driverLocation;
  /// Customer live GPS (when the customer app posts to `/geo/customer/location`).
  final LatLng? customerLocation;
  final String? customerLocationUpdatedAt;
  final List<LatLng> routePoints;
  final String driverName;
  final String? driverLastUpdated;
  final String status;
  final String deliveryAddress;

  bool displayEquals(TrackSnapshot other) {
    if (status != other.status ||
        driverName != other.driverName ||
        deliveryAddress != other.deliveryAddress) {
      return false;
    }
    if (!_latLngClose(destination, other.destination) ||
        !_latLngClose(driverLocation, other.driverLocation) ||
        !_latLngClose(customerLocation, other.customerLocation)) {
      return false;
    }
    final a = routePoints;
    final b = other.routePoints;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_latLngClose(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _latLngClose(LatLng? x, LatLng? y) {
    if (x == null && y == null) return true;
    if (x == null || y == null) return false;
    return (x.latitude - y.latitude).abs() < 1e-5 &&
        (x.longitude - y.longitude).abs() < 1e-5;
  }
}
