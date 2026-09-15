import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';

/// RPT-05: 카카오맵에 활성 신고 표시
/// 마커는 동선 지도에서 검증된 패턴(onMapCreated 후 setState 주입)을 사용.
class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  Set<Marker> _markers = {};
  bool _mapReady = false;
  KakaoMapController? _controller;

  bool _movedToMe = false;

  @override
  void initState() {
    super.initState();
    // 전국 서비스(2026-08-12): 지도는 전국 뷰로 열되, 내 위치를 얻으면
    // 신고자 동네로 이동한다. 지도는 재생성하지 않고 컨트롤러로만 옮긴다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveToMe());
  }

  /// 내 위치로 이동.
  /// [manual]이면 사용자가 버튼을 눌러 요청한 것 → 실패 시 안내를 띄운다.
  ///
  /// ⚠ 지도(WebView)가 준비되기 전에 setCenter를 호출하면 조용히 무시된다.
  ///   그래서 컨트롤러가 생길 때까지 짧게 재시도한다.
  Future<void> _moveToMe({bool manual = false}) async {
    if (_movedToMe && !manual) return;
    final svc = ref.read(locationServiceProvider);

    // 마지막으로 알던 위치가 있으면 먼저 옮겨 체감 속도를 높인다
    final last = await svc.getLastKnownPosition();
    if (mounted && last != null && isInKorea(last.latitude, last.longitude)) {
      await _center(last.latitude, last.longitude);
    }

    final pos = await svc.getCurrentPosition();
    if (!mounted) return;
    if (pos == null || !isInKorea(pos.latitude, pos.longitude)) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('현재 위치를 확인할 수 없습니다. 위치 권한과 GPS를 확인해주세요')));
      }
      return;
    }
    await _center(pos.latitude, pos.longitude);
    _movedToMe = true;
  }

  /// 컨트롤러가 준비될 때까지 최대 3초간 재시도하며 중심 이동
  Future<void> _center(double lat, double lng) async {
    for (var i = 0; i < 10; i++) {
      if (!mounted) return;
      if (_controller != null) {
        _controller!.setCenter(LatLng(lat, lng));
        _controller!.setLevel(kNearMapLevel);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 유형별 핀 색 (범례와 공유)
  static const Map<String, Color> kConditionColors = {
    'long_term': Color(0xFF1B7742), // 장기방치 의심 — 초록
    'damaged': Color(0xFFE8590C), // 파손 — 오렌지
    'obstruction': Color(0xFFE24B4A), // 통행 방해 — 빨강
    'parts_missing': Color(0xFF1B5FA5), // 부품 분실 — 파랑
    'other': Color(0xFF6B7671), // 기타 — 회색
  };

  static String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  static final Map<String, String> _pinCache = {};

  /// 유형별 원형 핀 (SVG 데이터 URI, 캐시)
  static String _pinFor(String condition) =>
      _pinCache.putIfAbsent(condition, () {
        final color =
            _hex(kConditionColors[condition] ?? kConditionColors['other']!);
        return 'data:image/svg+xml;base64,'
            '${base64Encode(utf8.encode('''
<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34">
  <circle cx="17" cy="17" r="12" fill="$color" stroke="#FFFFFF" stroke-width="3"/>
  <circle cx="17" cy="17" r="4" fill="#FFFFFF"/>
</svg>'''))}';
      });

  void _rebuildMarkers(List<Report> list) {
    if (!_mapReady || !mounted) return;
    setState(() {
      _markers = {
        for (final r in list)
          Marker(
            markerId: r.id,
            latLng: LatLng(r.lat, r.lng),
            markerImageSrc: _pinFor(r.condition),
            width: 34,
            height: 34,
            offsetX: 17,
            offsetY: 17,
          ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(activeReportsProvider);

    // 데이터가 바뀌면 마커 갱신
    ref.listen(activeReportsProvider, (_, next) {
      final list = next.value;
      if (list != null) _rebuildMarkers(list);
    });

    return Stack(
      children: [
        Positioned.fill(
          child: KakaoMap(
            center: LatLng(kDefaultLat, kDefaultLng),
            currentLevel: kDefaultMapLevel,
            markers: _markers.toList(),
            onMapCreated: (c) {
              _mapReady = true;
              _controller = c;
              // 지도 준비 후 현재 데이터로 마커 주입 + 내 위치로 이동
              Future.delayed(const Duration(milliseconds: 400), () {
                final list = ref.read(activeReportsProvider).value;
                if (list != null) _rebuildMarkers(list);
                _moveToMe();
              });
            },
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 10,
                    offset: Offset(0, 2)),
              ],
            ),
            child: reports.when(
              data: (list) => Text('처리 중 신고 ${list.length}건',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              loading: () => const Text('불러오는 중...',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.muted)),
              error: (e, _) => Text('오류: $e',
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: '새로고침',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(activeReportsProvider),
              ),
              const SizedBox(height: 8),
              // 내 위치로 이동 — 자동 이동이 실패했을 때의 수동 수단
              IconButton.filledTonal(
                tooltip: '내 위치',
                icon: const Icon(Icons.my_location),
                onPressed: () => _moveToMe(manual: true),
              ),
            ],
          ),
        ),
        // 유형별 색 범례
        Positioned(
          left: 12,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 10,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in kConditionColors.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: e.value, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          kConditionLabels[e.key] ?? e.key,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sub),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
