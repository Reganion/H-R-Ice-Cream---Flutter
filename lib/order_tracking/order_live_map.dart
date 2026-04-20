import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:ice_cream/services/api/geo_api_service.dart';
import 'package:ice_cream/services/api/models/geo_models.dart';
import 'package:latlong2/latlong.dart';

/// Optional zoom controls for a parent overlay (e.g. delivery tracker).
class OrderLiveMapNavController {
  _OrderLiveMapState? _state;

  void _attach(_OrderLiveMapState s) => _state = s;

  void _detach() => _state = null;

  Future<void> zoomIn() async => _state?._zoomIn();

  Future<void> zoomOut() async => _state?._zoomOut();
}

/// Live map: loads [MapsConfig] from GET /geo/maps-config, then Google Maps or OSM.
/// Polls track every [pollInterval]. Driver mode posts GPS on a ~4s throttle;
/// customer mode posts GPS on a ~8s throttle so the driver map can show the customer.
class OrderLiveMap extends StatefulWidget {
  const OrderLiveMap({
    super.key,
    required this.orderId,
    required this.isDriver,
    this.navController,
    this.pollInterval = const Duration(seconds: 4),
  });

  final String orderId;
  final bool isDriver;
  final OrderLiveMapNavController? navController;
  final Duration pollInterval;

  @override
  State<OrderLiveMap> createState() => _OrderLiveMapState();
}

class _OrderLiveMapState extends State<OrderLiveMap> {
  gmaps.GoogleMapController? _googleController; // unused (kept for backward compatibility)
  final fm.MapController _osmController = fm.MapController();

  Timer? _pollTimer;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _customerPositionSub;
  DateTime? _lastDriverPost;
  DateTime? _lastCustomerPost;

  MapsConfig? _mapsConfig;
  bool _mapsConfigLoading = true;

  TrackSnapshot? _snapshot;
  String? _error;
  bool _locGranted = false;
  bool _didFitCamera = false;
  /// When destination / driver / customer presence changes, refit bounds once.
  String? _lastMarkerFitSig;

  static const LatLng _fallback = LatLng(10.34, 123.9494);

  // Always OSM UI for this app (avoid Google Maps blank view).
  bool get _useOsm => true;

  @override
  void initState() {
    super.initState();
    widget.navController?._attach(this);
    _ensureLocationPermission();
    unawaited(_loadMapsConfig());
    _tick();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _tick());
    if (widget.isDriver) {
      _startDriverGps();
    } else {
      _startCustomerGps();
    }
  }

  void _maybeUpdateFitSig(TrackSnapshot snap) {
    final sig =
        '${snap.destination != null}|${snap.driverLocation != null}|${snap.customerLocation != null}';
    if (_lastMarkerFitSig != sig) {
      _lastMarkerFitSig = sig;
      _didFitCamera = false;
    }
  }

  Future<void> _loadMapsConfig() async {
    try {
      final cfg = await GeoApiService.instance.getMapsConfig();
      if (!mounted) return;
      setState(() {
        // Force OSM UI so the app never instantiates `google_maps_flutter`,
        // even if the backend returns `provider: google`.
        //
        // This prevents Google billing + helps you avoid the Google Maps SDK logs.
        if (cfg.isOsm &&
            (cfg.osmTileUrlTemplate != null && cfg.osmTileUrlTemplate!.isNotEmpty)) {
          _mapsConfig = cfg;
        } else {
          _mapsConfig = MapsConfig(
            provider: MapProviderKind.osm,
            osmTileUrlTemplate: MapsConfig.defaultOsmTileUrl,
            osmAttribution: cfg.osmAttribution ?? '© OpenStreetMap contributors',
          );
        }
        _mapsConfigLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Force free map fallback if /geo/maps-config fails (so we don't use
        // Google Maps and billing).
        _mapsConfig = const MapsConfig(
          provider: MapProviderKind.osm,
          osmTileUrlTemplate: MapsConfig.defaultOsmTileUrl,
          osmAttribution: '© OpenStreetMap contributors',
        );
        _mapsConfigLoading = false;
      });
    }
  }

  Future<void> _ensureLocationPermission() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      final ok = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
      setState(() => _locGranted = ok);
    } catch (_) {
      if (mounted) setState(() => _locGranted = false);
    }
  }

  Future<void> _tick() async {
    final result = widget.isDriver
        ? await GeoApiService.instance.fetchTrackForDriver(widget.orderId)
        : await GeoApiService.instance.fetchTrackForCustomer(widget.orderId);
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage ?? 'Could not load map data.');
      return;
    }
    final snap = result.snapshot!;
    _maybeUpdateFitSig(snap);
    final unchanged = _snapshot != null && _snapshot!.displayEquals(snap);
    if (!unchanged) {
      setState(() {
        _snapshot = snap;
        _error = null;
      });
    } else if (_error != null) {
      setState(() => _error = null);
    }
    if (!_didFitCamera) {
      // For your app: always fit the OSM camera.
      _fitOsmCamera();
    }
  }

  void _fitGoogleCamera() {
    final c = _googleController;
    if (c == null) return;
    final dest = _snapshot?.destination;
    final drv = _snapshot?.driverLocation;
    final cust = _snapshot?.customerLocation;
    final pts = _snapshot?.routePoints ?? [];
    final gpts = pts.map(_toGmaps).toList();
    final hasMeaningful = gpts.length >= 2 || dest != null || drv != null || cust != null;
    if (!hasMeaningful) return;
    _didFitCamera = true;
    if (gpts.length >= 2) {
      double minLat = gpts.first.latitude;
      double maxLat = gpts.first.latitude;
      double minLng = gpts.first.longitude;
      double maxLng = gpts.first.longitude;
      for (final p in gpts) {
        minLat = minLat < p.latitude ? minLat : p.latitude;
        maxLat = maxLat > p.latitude ? maxLat : p.latitude;
        minLng = minLng < p.longitude ? minLng : p.longitude;
        maxLng = maxLng > p.longitude ? maxLng : p.longitude;
      }
      c.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(minLat, minLng),
            northeast: gmaps.LatLng(maxLat, maxLng),
          ),
          48,
        ),
      );
      return;
    }
    final gd = dest != null ? _toGmaps(dest) : null;
    final gr = drv != null ? _toGmaps(drv) : null;
    final gc = cust != null ? _toGmaps(cust) : null;
    if (gd != null && gr != null) {
      c.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(
              gd.latitude < gr.latitude ? gd.latitude : gr.latitude,
              gd.longitude < gr.longitude ? gd.longitude : gr.longitude,
            ),
            northeast: gmaps.LatLng(
              gd.latitude > gr.latitude ? gd.latitude : gr.latitude,
              gd.longitude > gr.longitude ? gd.longitude : gr.longitude,
            ),
          ),
          56,
        ),
      );
      return;
    }
    final one = gd ?? gr ?? gc;
    if (one == null) return;
    c.animateCamera(gmaps.CameraUpdate.newLatLngZoom(one, 14));
  }

  void _fitOsmCamera() {
    final pts = <LatLng>[];
    final rp = _snapshot?.routePoints ?? [];
    if (rp.length >= 2) {
      pts.addAll(rp);
    }
    if (_snapshot?.destination != null) pts.add(_snapshot!.destination!);
    if (_snapshot?.driverLocation != null) pts.add(_snapshot!.driverLocation!);
    if (_snapshot?.customerLocation != null) pts.add(_snapshot!.customerLocation!);
    if (pts.isEmpty) return;
    _didFitCamera = true;
    if (pts.length == 1) {
      _osmController.move(pts.first, 14);
      return;
    }
    final bounds = fm.LatLngBounds.fromPoints(pts);
    _osmController.fitCamera(
      fm.CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  gmaps.LatLng _toGmaps(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

  Future<void> _startDriverGps() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen(_onDriverPosition);
    } catch (_) {}
  }

  Future<void> _onDriverPosition(Position pos) async {
    final now = DateTime.now();
    if (_lastDriverPost != null &&
        now.difference(_lastDriverPost!) < const Duration(seconds: 4)) {
      return;
    }
    _lastDriverPost = now;
    await GeoApiService.instance.postDriverLocation(
      orderId: widget.orderId,
      lat: pos.latitude,
      lng: pos.longitude,
    );
  }

  Future<void> _startCustomerGps() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      _customerPositionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen(_onCustomerPosition);
    } catch (_) {}
  }

  Future<void> _onCustomerPosition(Position pos) async {
    final now = DateTime.now();
    if (_lastCustomerPost != null &&
        now.difference(_lastCustomerPost!) < const Duration(seconds: 8)) {
      return;
    }
    _lastCustomerPost = now;
    await GeoApiService.instance.postCustomerLocation(
      orderId: widget.orderId,
      lat: pos.latitude,
      lng: pos.longitude,
    );
  }

  Future<void> _zoomIn() async {
    final cam = _osmController.camera;
    _osmController.move(cam.center, cam.zoom + 1);
  }

  Future<void> _zoomOut() async {
    final cam = _osmController.camera;
    _osmController.move(cam.center, (cam.zoom - 1).clamp(1, 22));
  }

  Set<gmaps.Marker> get _googleMarkers {
    final out = <gmaps.Marker>{};
    final dest = _snapshot?.destination;
    final drv = _snapshot?.driverLocation;
    final cust = _snapshot?.customerLocation;
    if (dest != null) {
      out.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('destination'),
          position: _toGmaps(dest),
          infoWindow: const gmaps.InfoWindow(title: 'Delivery address'),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed),
        ),
      );
    }
    if (drv != null) {
      out.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('driver'),
          position: _toGmaps(drv),
          infoWindow: gmaps.InfoWindow(
            title: 'Driver',
            snippet: (_snapshot?.driverName ?? '').isEmpty ? null : _snapshot!.driverName,
          ),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueAzure),
        ),
      );
    }
    if (cust != null) {
      out.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('customer'),
          position: _toGmaps(cust),
          infoWindow: const gmaps.InfoWindow(title: 'Your location'),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueGreen),
        ),
      );
    }
    return out;
  }

  Set<gmaps.Polyline> get _googlePolylines {
    final pts = _snapshot?.routePoints ?? [];
    if (pts.length < 2) return {};
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route'),
        points: pts.map(_toGmaps).toList(),
        color: const Color(0xFF7051C7),
        width: 5,
      ),
    };
  }

  List<fm.Marker> get _osmMarkers {
    final out = <fm.Marker>[];
    final dest = _snapshot?.destination;
    final drv = _snapshot?.driverLocation;
    final cust = _snapshot?.customerLocation;
    if (dest != null) {
      out.add(
        fm.Marker(
          point: dest,
          width: 36,
          height: 36,
          child: const Icon(Icons.place, color: Color(0xFFE3001B), size: 36),
        ),
      );
    }
    if (drv != null) {
      out.add(
        fm.Marker(
          point: drv,
          width: 36,
          height: 36,
          child: const Icon(Icons.delivery_dining, color: Color(0xFF7051C7), size: 32),
        ),
      );
    }
    if (cust != null) {
      out.add(
        fm.Marker(
          point: cust,
          width: 36,
          height: 36,
          child: const Icon(Icons.near_me, color: Color(0xFF00AE2A), size: 32),
        ),
      );
    }
    return out;
  }

  List<fm.Polyline<Object>> get _osmPolylines {
    final pts = _snapshot?.routePoints ?? [];
    if (pts.length < 2) return [];
    return [
      fm.Polyline(
        points: pts,
        color: const Color(0xFF7051C7),
        strokeWidth: 5,
      ),
    ];
  }

  LatLng get _center =>
      _snapshot?.destination ??
      _snapshot?.driverLocation ??
      _snapshot?.customerLocation ??
      _fallback;

  @override
  void dispose() {
    widget.navController?._detach();
    _pollTimer?.cancel();
    _positionSub?.cancel();
    _customerPositionSub?.cancel();
    _osmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mapsConfigLoading || _mapsConfig == null) {
      return const ColoredBox(
        color: Color(0xFFE8E8E8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final center = _center;

    final osmTileTemplate =
        _mapsConfig?.osmTileUrlTemplate ?? MapsConfig.defaultOsmTileUrl;

    final mapStack = fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: center,
        initialZoom: 13,
        onMapReady: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_didFitCamera) _fitOsmCamera();
          });
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: osmTileTemplate,
          userAgentPackageName: 'com.example.ice_cream',
        ),
        fm.PolylineLayer(polylines: _osmPolylines),
        fm.MarkerLayer(markers: _osmMarkers),
        if ((_mapsConfig?.osmAttribution ?? '').isNotEmpty)
          fm.SimpleAttributionWidget(
            source: Text(
              _mapsConfig!.osmAttribution!,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        mapStack,
        if (_error != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
