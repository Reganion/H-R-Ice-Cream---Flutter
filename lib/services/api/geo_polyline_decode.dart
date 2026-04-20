import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';

/// Decodes Google-encoded polyline from Directions / track [route] object.
List<LatLng> decodeRoutePolyline(dynamic route) {
  if (route == null) return [];
  if (route is! Map) return [];
  final m = Map<String, dynamic>.from(route);
  String? encoded;

  final ov = m['overview_polyline'];
  if (ov is String && ov.isNotEmpty) {
    encoded = ov;
  }
  final direct = m['polyline'] ?? m['points'] ?? m['encoded'];
  if (encoded == null && direct is String && direct.isNotEmpty) {
    encoded = direct;
  }
  if (encoded == null && direct is Map) {
    final om = Map<String, dynamic>.from(direct);
    final p = om['points'] ?? om['encoded'];
    if (p is String && p.isNotEmpty) encoded = p;
  }
  final overview = m['overview_polyline'];
  if (encoded == null && overview is Map) {
    final om = Map<String, dynamic>.from(overview);
    final p = om['points'];
    if (p is String && p.isNotEmpty) encoded = p;
  }
  if (encoded == null || encoded.isEmpty) return [];

  final pts = PolylinePoints.decodePolyline(encoded);
  return pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
}
