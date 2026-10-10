import 'package:geolocator/geolocator.dart';

enum LocationState { available, disabled, denied, permanentlyDenied, unavailable }
class LocationResult {
  final LocationState state;
  final double? latitude;
  final double? longitude;
  const LocationResult(this.state, {this.latitude, this.longitude});
}

/// Requests one foreground position only after explicit consent.
class LocationService {
  final Future<bool> Function() enabled;
  final Future<LocationPermission> Function() checkPermission;
  final Future<LocationPermission> Function() requestPermission;
  final Future<LocationResult> Function() readPosition;
  LocationService({Future<bool> Function()? enabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<LocationResult> Function()? readPosition})
      : enabled = enabled ?? Geolocator.isLocationServiceEnabled,
        checkPermission = checkPermission ?? Geolocator.checkPermission,
        requestPermission = requestPermission ?? Geolocator.requestPermission,
        readPosition = readPosition ?? _readPosition;
  static Future<LocationResult> _readPosition() async {
    final p = await Geolocator.getCurrentPosition(locationSettings:
      const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
    return LocationResult(LocationState.available,
      latitude: double.parse(p.latitude.toStringAsFixed(6)), longitude: double.parse(p.longitude.toStringAsFixed(6)));
  }
  Future<LocationResult> request() async {
    try {
      if (!await enabled()) return const LocationResult(LocationState.disabled);
      var permission = await checkPermission();
      if (permission == LocationPermission.denied) permission = await requestPermission();
      if (permission == LocationPermission.deniedForever) return const LocationResult(LocationState.permanentlyDenied);
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return const LocationResult(LocationState.denied);
      return await readPosition();
    } catch (_) { return const LocationResult(LocationState.unavailable); }
  }
  static Future<bool> openSettings({bool services = false}) async {
    try { return services ? await Geolocator.openLocationSettings() : await Geolocator.openAppSettings(); }
    catch (_) { return false; }
  }
}
