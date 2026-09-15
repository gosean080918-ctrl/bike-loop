import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/regions.dart';
import '../../state_management/providers.dart';
import 'location_picker_screen.dart';

/// 선택 결과 (좌표 + 주소)
class DepotPick {
  final double lat;
  final double lng;
  final String address;
  const DepotPick(this.lat, this.lng, this.address);
}

/// 보관소(출발지/복귀지) 선택 화면 — 전국 확장(2026-08-12)
///
/// 지역이 17곳으로 늘어나 한 줄짜리 '변경' 링크로는 고르기 어려워서
/// 목록 화면으로 분리했다. 시도 대표 청사에서 고르거나,
/// 지도에서 직접 찍어 차고지 주소를 쓸 수 있다.
class DepotPickerScreen extends ConsumerStatefulWidget {
  /// 화면 제목 (출발지/복귀지)
  final String title;

  /// 현재 설정된 주소 (체크 표시용)
  final String currentAddress;

  /// 지도 픽커의 시작 좌표
  final double initialLat;
  final double initialLng;

  const DepotPickerScreen({
    super.key,
    required this.title,
    required this.currentAddress,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  ConsumerState<DepotPickerScreen> createState() => _DepotPickerScreenState();
}

class _DepotPickerScreenState extends ConsumerState<DepotPickerScreen> {
  final _query = TextEditingController();
  String _filter = '';
  bool _busy = false;

  List<RegionDepot> get _list {
    if (_filter.isEmpty) return kRegions;
    final q = _filter.trim();
    return kRegions
        .where((r) =>
            r.name.contains(q) ||
            r.short.contains(q) ||
            r.depotName.contains(q) ||
            r.depotAddress.contains(q))
        .toList();
  }

  /// 청사 주소 → 좌표 (서버 검색, 실패 시 내장 좌표)
  Future<void> _pickRegion(RegionDepot r) async {
    setState(() => _busy = true);
    final resolved =
        await ref.read(settingsServiceProvider).resolveAddress(r.depotAddress);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(
      context,
      DepotPick(
        resolved?.$1 ?? r.lat,
        resolved?.$2 ?? r.lng,
        r.depotAddress,
      ),
    );
  }

  /// 지도에서 직접 지정 (차고지 등 청사가 아닌 장소)
  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: widget.initialLat,
          initialLng: widget.initialLng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final addr = await ref
        .read(reportServiceProvider)
        .reverseGeocode(result.latitude, result.longitude);
    if (!mounted) return;
    Navigator.pop(
      context,
      DepotPick(result.latitude, result.longitude,
          addr ?? '${result.latitude}, ${result.longitude}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          // 검색
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _query,
              onChanged: (v) => setState(() => _filter = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '지역 검색 (예: 경기, 전남)',
              ),
            ),
          ),
          // 지도에서 직접 선택
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickOnMap,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('지도에서 직접 선택 (차고지 등)'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const Divider(height: 1),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 60),
              itemBuilder: (context, i) {
                final r = list[i];
                final isCurrent = widget.currentAddress == r.depotAddress;
                return ListTile(
                  enabled: !_busy,
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(r.short,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isCurrent
                                ? Colors.white
                                : AppColors.primary)),
                  ),
                  title: Text(r.depotName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  subtitle: Text(r.depotAddress,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.muted)),
                  trailing: isCurrent
                      ? const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 22)
                      : const Icon(Icons.chevron_right,
                          color: AppColors.chevron, size: 20),
                  onTap: () => _pickRegion(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
