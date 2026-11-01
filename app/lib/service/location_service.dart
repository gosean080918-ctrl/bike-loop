import 'package:geolocator/geolocator.dart';

/// RPT-02: location permission and current position
class LocationService {
  /// Checks or requests permission, then returns the current position; null on failure.
  Future<Position?> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    // Time-limited so the app does not look frozen indoors, where a GPS fix is slow
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      // On timeout, fall back to the last known position
      return Geolocator.getLastKnownPosition();
    }
  }

  /// The cached last position: returns immediately, but may be less accurate.
  /// Used to move the map roughly into place first, so the app feels faster.
  Future<Position?> getLastKnownPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}
