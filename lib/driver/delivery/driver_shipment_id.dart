/// Firestore order document IDs are strings (UUIDs, etc.). Driver APIs use
/// `GET|POST /api/v1/driver/shipments/{id}/...` with that string — never force `int`.
String? driverShipmentIdFrom(dynamic id) {
  if (id == null) return null;
  final s = id.toString().trim();
  if (s.isEmpty) return null;
  return s;
}

/// Path segment for URLs (encodes `/`, spaces, etc.).
String driverShipmentIdForPath(String id) => Uri.encodeComponent(id);
