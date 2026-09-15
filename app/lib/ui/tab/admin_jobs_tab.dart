import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../const/value/regions.dart';
import '../../service/settings_service.dart';
import '../../state_management/providers.dart';
import '../route/depot_picker_screen.dart';
import '../route/route_map_screen.dart';

/// ADM-03~07: 수거 대상 선택 → 경로 생성 → 방문 순서 → 길안내 → 완료 처리
class AdminJobsTab extends ConsumerStatefulWidget {
  const AdminJobsTab({super.key});

  @override
  ConsumerState<AdminJobsTab> createState() => _AdminJobsTabState();
}

class _AdminJobsTabState extends ConsumerState<AdminJobsTab> {
  final Set<String> _selected = {};
  final _capacity = TextEditingController(text: '20');
  final _workMin = TextEditingController(text: '240');
  bool _busy = false;

  /// 전국 확장(2026-08-12): 담당 지역 필터. null이면 전체.
  /// ⚠ 지역이 섞인 채로 경로를 만들면 제주 신고와 경기 신고가 한 경로에
  ///   들어가 버리므로, 지역을 고르면 목록과 선택을 그 지역으로 한정한다.
  String? _region;

  /// 선택 지역의 기본 보관소(도청/시청)를 출발·복귀지로 설정
  Future<void> _useRegionDepot() async {
    final rd = depotOf(_region);
    if (rd == null) return;
    setState(() => _busy = true);
    try {
      // 정확한 좌표는 서버 검색으로 얻고, 실패하면 내장 좌표로 폴백
      final settings = ref.read(settingsServiceProvider);
      final resolved = await settings.resolveAddress(rd.depotAddress);
      final lat = resolved?.$1 ?? rd.lat;
      final lng = resolved?.$2 ?? rd.lng;
      await settings.saveDepot(lat, lng, rd.depotAddress);
      await settings.clearReturn(); // 복귀지는 출발지와 동일로 초기화
      ref.invalidate(depotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('출발지가 ${rd.depotName}으로 설정되었습니다')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 지역 필터 적용
  List<Report> _filtered(List<Report> list) {
    if (_region == null) return list;
    return list.where((r) => regionOf(r.address) == _region).toList();
  }

  /// ★ 경로 생성 전 지역 검증 (전국 확장 후 필수)
  /// 제주 보관소에서 출발해 서울 자전거를 주우러 가는 동선이 만들어지는 것을 막는다.
  /// 통과하면 true, 사용자가 취소하면 false.
  Future<bool> _checkRegions(List<Report> targets) async {
    final depot = await ref.read(depotProvider.future);
    if (!mounted) return false;
    final depotRegion = regionOf(depot.address);
    final targetRegions =
        targets.map((r) => regionOf(r.address)).whereType<String>().toSet();

    // ① 선택한 신고가 여러 지역에 걸쳐 있는 경우
    if (targetRegions.length > 1) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('여러 지역이 섞여 있습니다'),
              content: Text(
                  '선택한 신고가 ${targetRegions.join(', ')} 에 걸쳐 있습니다.\n'
                  '한 차량이 지역을 넘나들면 이동거리가 매우 커지고 '
                  '경로 생성이 실패할 수 있습니다.\n\n'
                  '위의 담당 지역을 골라 한 지역씩 처리하는 것을 권합니다.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('그래도 생성')),
              ],
            ),
          ) ??
          false;
      if (!ok) return false;
    }

    // ② 출발지가 대상 지역과 다른 경우 → 해당 지역 청사로 바꿔줄지 물어본다
    if (targetRegions.length == 1) {
      final target = targetRegions.first;
      if (depotRegion != null && depotRegion != target) {
        final rd = depotOf(target);
        if (!mounted) return false;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('출발지가 다른 지역입니다'),
            content: Text('수거 대상은 $target인데 '
                '출발지는 $depotRegion으로 설정되어 있습니다.\n'
                '이대로 만들면 지역을 가로지르는 동선이 됩니다.\n\n'
                '${rd == null ? '' : '출발지를 ${rd.depotName}으로 바꿀까요?'}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('취소')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'keep'),
                  child: const Text('그대로 진행')),
              if (rd != null)
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'switch'),
                    child: const Text('바꾸고 진행')),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return false;
        if (choice == 'switch' && rd != null) {
          final settings = ref.read(settingsServiceProvider);
          final resolved = await settings.resolveAddress(rd.depotAddress);
          await settings.saveDepot(
              resolved?.$1 ?? rd.lat, resolved?.$2 ?? rd.lng, rd.depotAddress);
          await settings.clearReturn();
          ref.invalidate(depotProvider);
        }
      }
    }
    return true;
  }

  Future<void> _createJob(List<Report> approved) async {
    final targets =
        approved.where((r) => _selected.contains(r.id)).toList();
    if (targets.isEmpty) return;
    final regionOk = await _checkRegions(targets);
    if (!regionOk || !mounted) return;
    setState(() => _busy = true);
    // 계산 중에는 화면을 막고 진행 상태를 보여준다(중복 입력 방지)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                      strokeWidth: 3.2, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                const Text('최적 경로를 계산하고 있습니다',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Text('${targets.length}개 지점 · 잠시만 기다려주세요',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final depot = await ref.read(depotProvider.future);
      await ref.read(adminServiceProvider).createJob(
            targets: targets,
            depotLat: depot.lat,
            depotLng: depot.lng,
            returnLat:
                depot.returnSameAsDepot ? null : depot.returnLat,
            returnLng:
                depot.returnSameAsDepot ? null : depot.returnLng,
            vehicleCapacity: int.tryParse(_capacity.text) ?? 20,
            workMinutes: int.tryParse(_workMin.text) ?? 240,
          );
      _selected.clear();
      ref.invalidate(approvedReportsProvider);
      ref.invalidate(jobsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('수거 경로가 생성되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 로딩 닫기
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteReport(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신고 삭제'),
        content: const Text('이 신고를 영구 삭제할까요?\n(테스트/오입력 데이터 정리용)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminServiceProvider).deleteReport(id);
      _selected.remove(id);
      ref.invalidate(approvedReportsProvider);
      ref.invalidate(activeReportsProvider);
      ref.invalidate(pendingReportsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('삭제되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  /// 수거 작업 삭제 (이력 정리용)
  Future<void> _deleteJob(String jobId, int stopCount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('수거 작업 삭제'),
        content: Text('이 작업($stopCount지점)을 목록에서 지울까요?\n'
            '수거 완료된 신고와 재고는 그대로 남습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminServiceProvider).deleteJob(jobId);
      ref.invalidate(jobsProvider);
      ref.invalidate(approvedReportsProvider);
      ref.invalidate(activeReportsProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('작업이 삭제되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  /// 출발지/복귀지 변경 — 전국 17개 청사 목록 화면에서 선택
  /// (목록에서 '지도에서 직접 선택'으로 차고지 지정도 가능)
  Future<void> _changeDepot({required bool isReturn}) async {
    final depot = await ref.read(depotProvider.future);
    if (!mounted) return;
    final pick = await Navigator.of(context).push<DepotPick>(
      MaterialPageRoute(
        builder: (_) => DepotPickerScreen(
          title: isReturn ? '복귀지 선택' : '출발지 선택',
          currentAddress:
              isReturn ? depot.returnAddress : depot.address,
          initialLat: isReturn ? depot.returnLat : depot.lat,
          initialLng: isReturn ? depot.returnLng : depot.lng,
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final settings = ref.read(settingsServiceProvider);
    if (isReturn) {
      await settings.saveReturn(pick.lat, pick.lng, pick.address);
    } else {
      await settings.saveDepot(pick.lat, pick.lng, pick.address);
    }
    ref.invalidate(depotProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${isReturn ? '복귀지' : '출발지'}가 변경되었습니다: ${pick.address}')));
    }
  }

  Widget _depotRow(DepotConfig d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 10,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.home_work_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('출발지',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.address.isEmpty ? '(설정 안 됨)' : d.address,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.sub),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _changeDepot(isReturn: false),
                child: const Text('변경',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.keyboard_return,
                  size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              const Text('복귀지',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.returnSameAsDepot
                      ? '출발지와 동일'
                      : (d.returnAddress.isEmpty
                          ? '(설정 안 됨)'
                          : d.returnAddress),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.sub),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!d.returnSameAsDepot) ...[
                GestureDetector(
                  onTap: () async {
                    await ref
                        .read(settingsServiceProvider)
                        .clearReturn();
                    ref.invalidate(depotProvider);
                  },
                  child: const Text('동일하게',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                ),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: () => _changeDepot(isReturn: true),
                child: const Text('변경',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ADM-05: KakaoMap 외부 앱(미설치 시 웹) 길안내
  Future<void> _navigateTo(double lat, double lng) async {
    final appUrl = Uri.parse('kakaomap://route?ep=$lat,$lng&by=CAR');
    final webUrl =
        Uri.parse('https://map.kakao.com/link/to/수거지점,$lat,$lng');
    if (await canLaunchUrl(appUrl)) {
      await launchUrl(appUrl);
    } else {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = ref.watch(approvedReportsProvider);
    final jobs = ref.watch(jobsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(approvedReportsProvider);
        ref.invalidate(jobsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---------- 담당 지역 (전국 확장) ----------
          Text('담당 지역', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 10,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.map_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _region,
                      hint: const Text('전체 지역',
                          style: TextStyle(fontSize: 14)),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('전체 지역')),
                        ...kRegions.map((r) => DropdownMenuItem<String?>(
                              value: r.name,
                              child: Text(r.name),
                            )),
                      ],
                      onChanged: (v) => setState(() {
                        _region = v;
                        _selected.clear(); // 지역이 바뀌면 선택 초기화(혼선 방지)
                      }),
                    ),
                  ),
                ),
                if (_region != null)
                  TextButton(
                    onPressed: _busy ? null : _useRegionDepot,
                    child: Text('${depotOf(_region)?.depotName ?? ''} 사용',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          if (_region != null)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('※ 도 지역은 청사에서 멀면 이동거리가 커집니다. '
                  '가까운 차고지가 있으면 아래에서 출발지를 바꾸세요.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          const SizedBox(height: 20),

          // ---------- 출발지/복귀지 (보관소) ----------
          Text('출발·복귀 설정 (보관소)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ref.watch(depotProvider).when(
                data: _depotRow,
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))),
                ),
                error: (e, _) => Text('설정 오류: $e'),
              ),
          const SizedBox(height: 20),

          // ---------- 수거 대상 선택 (ADM-03) ----------
          Text(
              _region == null
                  ? '수거 대상 선택 (승인된 신고)'
                  : '수거 대상 선택 — $_region',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          approved.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('오류: $e'),
            data: (all) => switch (_filtered(all)) {
              final list when list.isEmpty => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_region == null
                      ? '승인된 신고가 없습니다. 검토 탭에서 먼저 승인하세요.'
                      : '$_region에 승인된 신고가 없습니다.'),
                ),
              final list => Column(
                    children: [
                      ...list.map((r) => CheckboxListTile(
                            dense: true,
                            value: _selected.contains(r.id),
                            onChanged: (v) => setState(() => v == true
                                ? _selected.add(r.id)
                                : _selected.remove(r.id)),
                            title: Text(
                                kConditionLabels[r.condition] ?? r.condition),
                            subtitle: Text(r.address ??
                                '${r.lat.toStringAsFixed(4)}, ${r.lng.toStringAsFixed(4)}'),
                            secondary: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20),
                              tooltip: '신고 삭제',
                              onPressed: () => _deleteReport(r.id),
                            ),
                          )),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _capacity,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '차량 적재량(대)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _workMin,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '작업시간(분)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _selected.isEmpty || _busy
                              ? null
                              : () => _createJob(list),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.route),
                          label: Text('최적 수거 경로 생성 (${_selected.length}건)'),
                        ),
                      ),
                    ],
                  ),
            },
          ),
          const Divider(height: 32),

          // ---------- 작업 목록 (ADM-04~07) ----------
          Text('수거 작업', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          jobs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('오류: $e'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('생성된 작업이 없습니다.'),
                  )
                : Column(
                    children: list.map((j) => _jobCard(j)).toList()),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final stops = ((j['job_stops'] ?? []) as List)
        .cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    final doneCount = stops.where((s) => s['done'] == true).length;
    final status = j['status'] as String;
    final dist = j['total_distance_m'];
    final durS = j['total_duration_s'];
    final jobId = j['id'] as String;
    final summary = [
      '${stops.length}개 지점',
      if (dist != null) '총 ${(dist / 1000).toStringAsFixed(1)}km',
      if (durS != null) '예상 ${(durS / 60).round()}분',
    ].join(' · ');

    return Card(
      child: ExpansionTile(
        leading: IconButton(
          icon: const Icon(Icons.map_outlined),
          tooltip: '동선 지도 보기',
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RouteMapScreen(
                depotLat:
                    (j['depot_lat'] as num?)?.toDouble() ?? kDefaultLat,
                depotLng:
                    (j['depot_lng'] as num?)?.toDouble() ?? kDefaultLng,
                roadPolyline: j['route_polyline'] as List<dynamic>?,
                stops: stops.map((s) {
                  final r = s['reports'] as Map<String, dynamic>?;
                  return {
                    'seq': s['seq'],
                    'lat': (r?['lat'] as num?)?.toDouble() ?? 0.0,
                    'lng': (r?['lng'] as num?)?.toDouble() ?? 0.0,
                    'label': (r?['address'] as String?) ??
                        (kConditionLabels[r?['condition']] ?? ''),
                  };
                }).toList(),
              ),
            ));
          },
        ),
        title: Text(summary,
            style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2)),
        subtitle: Text(
            '${(j['created_at'] as String).substring(0, 10)} · ${status == 'done' ? '완료' : '진행 중'} · $doneCount/${stops.length} 수거',
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.muted)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.muted),
              tooltip: '작업 삭제',
              onPressed: () => _deleteJob(jobId, stops.length),
            ),
            const Icon(Icons.expand_more, color: AppColors.muted),
          ],
        ),
        children: [
          ...stops.map((s) {
            final r = s['reports'] as Map<String, dynamic>?;
            final lat = (r?['lat'] as num?)?.toDouble() ?? 0;
            final lng = (r?['lng'] as num?)?.toDouble() ?? 0;
            final done = s['done'] == true;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: done ? Colors.green : Colors.grey.shade400,
                child: Text('${s['seq']}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              title: Text(
                  kConditionLabels[r?['condition']] ?? '${r?['condition']}'),
              subtitle: Text((r?['address'] as String?) ??
                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.navigation, size: 20),
                    tooltip: '카카오맵 길안내',
                    onPressed: () => _navigateTo(lat, lng),
                  ),
                  done
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 20)
                      : TextButton(
                          onPressed: () async {
                            await ref
                                .read(adminServiceProvider)
                                .completeStop(
                                  jobId: jobId,
                                  seq: s['seq'] as int,
                                  reportId: s['report_id'] as String,
                                );
                            ref.invalidate(jobsProvider);
                            ref.invalidate(activeReportsProvider);
                            ref.invalidate(dashboardProvider);
                          },
                          child: const Text('수거 완료'),
                        ),
                ],
              ),
            );
          }),
          if (status != 'done' && doneCount == stops.length && stops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton(
                onPressed: () async {
                  await ref.read(adminServiceProvider).finishJob(jobId);
                  ref.invalidate(jobsProvider);
                },
                child: const Text('작업 종료'),
              ),
            ),
        ],
      ),
    );
  }
}
