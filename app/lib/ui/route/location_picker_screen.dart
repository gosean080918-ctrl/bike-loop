import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';

/// RPT-02: 지도에서 신고 위치 조정 + 장소 검색 (예: "강남역")
/// 지도를 움직여 중앙 핀을 맞추거나, 검색으로 바로 이동 후 확정.
class LocationPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const LocationPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _Place {
  final String name;
  final String address;
  final double lat;
  final double lng;
  _Place(this.name, this.address, this.lat, this.lng);
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  KakaoMapController? _controller;
  final _query = TextEditingController();
  List<_Place> _results = [];
  bool _searching = false;

  // 카카오맵은 한국 밖 타일이 없음 → 해외 좌표(에뮬레이터 기본 GPS 등)는
  // 흰 화면이 되므로 기본 위치(전국 중심)로 대체
  late double _centerLat = isInKorea(widget.initialLat, widget.initialLng)
      ? widget.initialLat
      : kDefaultLat;
  late double _centerLng = isInKorea(widget.initialLat, widget.initialLng)
      ? widget.initialLng
      : kDefaultLng;

  /// 신고자 위치가 있으면 동네 수준으로, 없으면 전국 뷰로 시작
  late final int _initialLevel =
      isInKorea(widget.initialLat, widget.initialLng)
          ? kNearMapLevel
          : kDefaultMapLevel;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final res = await http
          .get(Uri.parse('$kSearchUrl?q=${Uri.encodeComponent(q)}'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) throw Exception('검색 실패');
      final places = (jsonDecode(res.body)['places'] as List)
          .map((p) => _Place(
                p['name'] as String? ?? '',
                p['address'] as String? ?? '',
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList();
      if (mounted) setState(() => _results = places);
      if (places.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('검색 결과가 없습니다')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('검색 실패 — 서버가 켜져 있는지 확인하세요')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _moveTo(_Place p) {
    // 서비스 지역(대한민국) 밖이면 이동 자체를 막음
    if (!isInKorea(p.lat, p.lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOutOfServiceMsg)));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _centerLat = p.lat;
      _centerLng = p.lng;
      _results = [];
      _query.text = p.name;
    });
    // 지도 재생성 없이 컨트롤러로 직접 이동
    _controller?.setCenter(LatLng(p.lat, p.lng));
    _controller?.setLevel(3);
  }

  Future<void> _confirm() async {
    LatLng? center;
    if (_controller != null) {
      center = await _controller!.getCenter();
    }
    center ??= LatLng(_centerLat, _centerLng);
    if (!mounted) return;
    // 서비스 지역(대한민국) 밖 확정 불가
    if (!isInKorea(center.latitude, center.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOutOfServiceMsg)));
      return;
    }
    Navigator.of(context).pop(center);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('신고 위치 조정')),
      body: Stack(
        children: [
          // 지도를 화면 전체에 강제 배치 (크기 미지정으로 인한 빈 화면 방지)
          Positioned.fill(
            child: KakaoMap(
              center: LatLng(_centerLat, _centerLng),
              currentLevel: _initialLevel,
              onMapCreated: (c) {
                _controller = c;
                // 생성 직후 레이아웃/중심 재적용 (빈 화면 보정)
                Future.delayed(const Duration(milliseconds: 600), () {
                  _controller?.relayout();
                  _controller?.setCenter(
                      LatLng(_centerLat, _centerLng));
                });
              },
            ),
          ),
          // 화면 중앙 고정 핀
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 36),
                  child: Icon(Icons.place,
                      size: 44, color: Color(0xFFD32F2F)),
                ),
              ),
            ),
          ),
          // 상단 검색바 + 결과 리스트
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2214281E),
                          blurRadius: 16,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.search,
                          size: 20, color: AppColors.faint),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            hintText: '동네 이름, 장소로 검색 (예: 강남역)',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 14),
                          ),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.only(right: 14),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.arrow_forward,
                              size: 20, color: AppColors.primary),
                          onPressed: _search,
                        ),
                    ],
                  ),
                ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x2214281E),
                            blurRadius: 16,
                            offset: Offset(0, 4)),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, i) {
                        final p = _results[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              size: 20, color: AppColors.primary),
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(p.address,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.muted)),
                          onTap: () => _moveTo(p),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: const Text('이 위치로 확정'),
          ),
        ),
      ),
    );
  }
}
