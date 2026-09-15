import 'package:geolocator/geolocator.dart';

/// RPT-02 위치 권한 + 현재 위치
class LocationService {
  /// 권한 확인/요청 후 현재 위치 반환. 실패 시 null.
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

    // GPS 수신이 느린 실내 등에서 앱이 멈춘 것처럼 보이지 않도록 시간 제한
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      // 시간 초과 시 마지막으로 알던 위치라도 반환
      return Geolocator.getLastKnownPosition();
    }
  }

  /// 캐시된 마지막 위치 (즉시 반환, 정확도는 낮을 수 있음).
  /// 지도를 먼저 대략 옮겨 체감 속도를 높이는 용도.
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
