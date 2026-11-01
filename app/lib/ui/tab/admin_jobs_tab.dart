import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../const/value/regions.dart';
import '../../utils/romanize.dart';
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
            SnackBar(content: Text('Depot set to ${rd.depotName}')));
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
              title: const Text('Multiple regions selected'),
              content: Text(
                  'The selected reports span ${targetRegions.length} regions.\n'
                  'One vehicle crossing regions means a very long route and '
                  'the optimizer may refuse it.\n\n'
                  'Pick a region above and handle one at a time.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Create anyway')),
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
            title: const Text('Depot is in another region'),
            content: Text('Targets are in $target but the depot is in $depotRegion.\n'
                'This would create a route across regions.\n\n'
                '${rd == null ? '' : 'Switch the depot to ${rd.depotName}?'}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'keep'),
                  child: const Text('Keep')),
              if (rd != null)
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'switch'),
                    child: const Text('Switch and continue')),
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
                const Text('Calculating the optimal route',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Text('${targets.length} stops · one moment',
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
            const SnackBar(content: Text('Collection route created')));
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
        title: const Text('Delete report'),
        content: const Text('Permanently delete this report?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
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
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  /// 수거 작업 삭제 (이력 정리용)
  Future<void> _deleteJob(String jobId, int stopCount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job'),
        content: Text('Remove this job ($stopCount stops) from the list?\n'
            'Collected reports and inventory are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
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
            const SnackBar(content: Text('Job deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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
          title: isReturn ? 'Select return point' : 'Select depot',
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
              '${isReturn ? 'Return point' : 'Depot'} set: ${romanizeAddress(pick.address)}')));
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
              const Text('Depot',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.address.isEmpty ? '(not set)' : d.address,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.sub),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _changeDepot(isReturn: false),
                child: const Text('Change',
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
              const Text('Return',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.returnSameAsDepot
                      ? 'Same as depot'
                      : (d.returnAddress.isEmpty
                          ? '(not set)'
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
                  child: const Text('Same',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                ),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: () => _changeDepot(isReturn: true),
                child: const Text('Change',
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
        Uri.parse('https://map.kakao.com/link/to/Stop,$lat,$lng');
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
          Text('Region', style: Theme.of(context).textTheme.titleMedium),
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
                      hint: const Text('All regions',
                          style: TextStyle(fontSize: 14)),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('All regions')),
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
                    child: Text('Use ${depotOf(_region)?.depotName ?? ''}',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          if (_region != null)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('A province office can be far from the sites. '
                  'If you have a closer yard, change the depot below.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          const SizedBox(height: 20),

          // ---------- 출발지/복귀지 (보관소) ----------
          Text('Depot & return point',
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
                error: (e, _) => Text('Settings error: $e'),
              ),
          const SizedBox(height: 20),

          // ---------- 수거 대상 선택 (ADM-03) ----------
          Text(
              _region == null
                  ? 'Select targets (approved)'
                  : 'Select targets — $_region',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          approved.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (all) => switch (_filtered(all)) {
              final list when list.isEmpty => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_region == null
                      ? 'No approved reports. Approve some in the Review tab.'
                      : 'No approved reports in $_region.'),
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
                              tooltip: 'Delete report',
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
                                labelText: 'Vehicle capacity',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _workMin,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Work time (min)',
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
                          label: Text('Generate optimal route (${_selected.length})'),
                        ),
                      ),
                    ],
                  ),
            },
          ),
          const Divider(height: 32),

          // ---------- 작업 목록 (ADM-04~07) ----------
          Text('Collection jobs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          jobs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No jobs yet.'),
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
      '${stops.length} stops',
      if (dist != null) '${(dist / 1000).toStringAsFixed(1)} km',
      if (durS != null) '~${(durS / 60).round()} min',
    ].join(' · ');

    return Card(
      child: ExpansionTile(
        leading: IconButton(
          icon: const Icon(Icons.map_outlined),
          tooltip: 'Route map',
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
            '${(j['created_at'] as String).substring(0, 10)} · ${status == 'done' ? 'done' : 'in progress'} · $doneCount/${stops.length} collected',
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.muted)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.muted),
              tooltip: 'Delete job',
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
                    tooltip: 'Navigate',
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
                          child: const Text('Collected'),
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
                child: const Text('Finish job'),
              ),
            ),
        ],
      ),
    );
  }
}
