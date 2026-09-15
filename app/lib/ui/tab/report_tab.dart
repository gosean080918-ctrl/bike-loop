import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../const/value/regions.dart';
import '../../state_management/providers.dart';
import '../route/location_picker_screen.dart';

/// RPT-01~04: 사진 → 현재 위치 자동 + 지도 조정 → 상태 유형(5종)+설명 → 중복 확인 → 제출
class ReportTab extends ConsumerStatefulWidget {
  const ReportTab({super.key});

  @override
  ConsumerState<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends ConsumerState<ReportTab> {
  final _picker = ImagePicker();
  final _description = TextEditingController();
  File? _photo;
  double? _lat, _lng;
  String? _address; // 역지오코딩 결과 (표시용, 제출 시 함께 저장)
  String? _condition; // kConditionLabels 키
  bool _busy = false;
  bool _locating = false;

  /// ★ GPS 레이스 방지 플래그 (2026-07-21에 이 버그로 GPS를 통째로 뺐던 이력)
  /// 사용자가 지도/검색으로 위치를 한 번이라도 확정하면 true.
  /// 이후 GPS 응답이 늦게 도착해도 절대 덮어쓰지 않는다.
  bool _userPickedLocation = false;

  @override
  void initState() {
    super.initState();
    // 전국 서비스(2026-08-12): 신고 시작 시 신고자의 현재 위치를 먼저 잡아준다.
    // 어디까지나 '초기 후보값'이며, 사용자가 지도에서 얼마든지 수정할 수 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateMe());
  }

  /// 현재 위치 → 좌표 + 주소. 실패해도 조용히 넘어간다(수동 선택 가능).
  Future<void> _locateMe({bool force = false}) async {
    if (_locating) return;
    if (!force && _userPickedLocation) return; // 사용자 확정값 보호
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      // 응답이 오는 사이 사용자가 직접 골랐다면 덮어쓰지 않는다
      if (!mounted || (!force && _userPickedLocation)) return;
      if (pos == null || !isInKorea(pos.latitude, pos.longitude)) {
        if (mounted && force) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('현재 위치를 확인할 수 없습니다. 지도에서 직접 선택해주세요')));
        }
        return;
      }
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = null;
      });
      await _fillAddress(pos.latitude, pos.longitude);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 좌표 → 주소 (서버 프록시). 실패하면 좌표를 그대로 표시한다.
  Future<void> _fillAddress(double lat, double lng) async {
    final addr =
        await ref.read(reportServiceProvider).reverseGeocode(lat, lng);
    if (!mounted) return;
    // 그 사이 위치가 또 바뀌었으면 무시
    if (_lat != lat || _lng != lng) return;
    setState(() => _address = addr);
  }

  Future<void> _takePhoto(ImageSource source) async {
    final img = await _picker.pickImage(
        source: source, maxWidth: 1600, imageQuality: 85);
    if (img == null) return;
    setState(() => _photo = File(img.path));
  }

  /// RPT-02: 지도에서 위치 미세 조정
  Future<void> _adjustLocation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _lat ?? kDefaultLat,
          initialLng: _lng ?? kDefaultLng,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        _address = null;
        _userPickedLocation = true; // 이후 GPS가 덮어쓰지 못하게 잠금
      });
      await _fillAddress(result.latitude, result.longitude);
    }
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _photo == null || _lat == null || _condition == null) {
      return;
    }
    // 서비스 지역(대한민국) 밖 신고 불가
    if (!isInKorea(_lat!, _lng!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('$kOutOfServiceMsg — 지도에서 국내 위치로 수정해주세요')));
      return;
    }
    setState(() => _busy = true);
    final service = ref.read(reportServiceProvider);
    try {
      // 제출 전 중복 확인 (30m 반경)
      final nearby = await service.findNearby(_lat!, _lng!);
      if (nearby.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('근처에 이미 신고가 있어요'),
            content: Text('${nearby.first.distanceM.round()}m 거리에 '
                '처리 중인 신고 ${nearby.length}건이 있습니다.\n'
                '같은 자전거라면 중복 신고가 될 수 있어요. 계속할까요?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('계속 신고')),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }

      await service.submitReport(
        reporterId: user.id,
        photo: _photo!,
        lat: _lat!,
        lng: _lng!,
        condition: _condition!,
        description: _description.text.trim(),
        address: _address, // 이미 얻어둔 주소가 있으면 재조회 없이 사용
      );
      ref.invalidate(myReportsProvider);
      ref.invalidate(activeReportsProvider);
      ref.invalidate(pendingReportsProvider); // 관리자 검토 탭 갱신
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고가 접수되었습니다. 감사합니다!')));
        setState(() {
          _photo = null;
          _lat = null;
          _lng = null;
          _address = null;
          _condition = null;
          _userPickedLocation = false;
          _description.clear();
        });
        _locateMe(); // 다음 신고를 위해 현재 위치 다시 잡아둔다
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('제출 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _photo != null && _lat != null && _condition != null && !_busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 사진 (RPT-01) — 시안: 대시 보더 타일 + 미리보기
          const SectionTitle('사진', required: true),
          const SizedBox(height: 10),
          _photo == null
              ? Row(
                  children: [
                    GestureDetector(
                      onTap: () => _takePhoto(ImageSource.camera),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFB9C4BC), width: 1.4),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('+',
                                style: TextStyle(
                                    fontSize: 24,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w300)),
                            Text('촬영',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _takePhoto(ImageSource.gallery),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFB9C4BC), width: 1.4),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined,
                                size: 22, color: AppColors.primary),
                            SizedBox(height: 4),
                            Text('갤러리',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(_photo!, fit: BoxFit.cover),
                  ),
                ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _takePhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('다시 촬영'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _takePhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('갤러리'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),

          // 2. 위치 (시안: 흰 카드 + 초록 점 + '수정' 링크)
          const SectionTitle('위치'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_locating)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    else
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locating && _lat == null
                            ? '현재 위치를 확인하는 중…'
                            : _lat == null
                                ? '지도에서 자전거 위치를 선택해주세요'
                                : (_address ??
                                    '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color:
                              _lat == null ? AppColors.faint : AppColors.ink,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _adjustLocation,
                      child: Text(_lat == null ? '위치 선택' : '수정',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // 지역 배지 — 어느 지자체가 처리하게 되는지 미리 보여준다
                    if (regionOf(_address) != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(regionOf(_address)!,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _locating ? null : () => _locateMe(force: true),
                      icon: const Icon(Icons.my_location, size: 15),
                      label: const Text('내 위치로'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 3. 상태 유형 선택 (RPT-03, 기획안 5종)
          const SectionTitle('자전거 상태', required: true),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: kConditionLabels.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _condition == e.key,
                      onSelected: (_) => setState(() => _condition = e.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),

          // 4. 간단한 설명 (RPT-03)
          const SectionTitle('설명', hint: '(선택)'),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: '예: 바퀴에 녹이 슬어 있고 안장이 없어요. 한 달 넘게 같은 자리에 있는 것 같아요.',
            ),
          ),
          const SizedBox(height: 14),

          // 5. 제출 (RPT-04 + 중복 확인) — 시안 CTA
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: canSubmit
                  ? const [
                      BoxShadow(
                          color: AppColors.shadowCta,
                          blurRadius: 20,
                          offset: Offset(0, 8)),
                    ]
                  : null,
            ),
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('신고 접수하기'),
            ),
          ),
        ],
      ),
    );
  }
}
