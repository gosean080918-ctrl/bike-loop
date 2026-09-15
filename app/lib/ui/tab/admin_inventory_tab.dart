import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';
import '../component/signed_photo.dart';

/// ADM-08: 수거 완료 재고 목록 — 관리번호/사진/신고위치/신고일/수거일/
/// 보관장소/상태. 상태 필터 + 관리번호 검색 + 상세에서 상태·보관장소 변경.
class AdminInventoryTab extends ConsumerStatefulWidget {
  const AdminInventoryTab({super.key});

  @override
  ConsumerState<AdminInventoryTab> createState() =>
      _AdminInventoryTabState();
}

class _AdminInventoryTabState extends ConsumerState<AdminInventoryTab> {
  String? _stateFilter; // null = 전체
  final _search = TextEditingController();
  List<Map<String, dynamic>> _bikes = [];
  Map<String, int> _summary = {}; // 상태별 집계(필터와 무관하게 전체)
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final admin = ref.read(adminServiceProvider);
      final rows = await admin.fetchBikes(
        state: _stateFilter,
        query: _search.text,
      );
      // 요약은 필터와 무관하게 전체 기준으로 집계
      final all = await admin.fetchBikes(limit: 1000);
      final counts = <String, int>{};
      for (final b in all) {
        final s = b['state'] as String? ?? 'storage';
        counts[s] = (counts[s] ?? 0) + 1;
      }
      if (mounted) {
        setState(() {
          _bikes = rows;
          _summary = counts;
          _total = all.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('재고 조회 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 재고 항목 삭제 (신고 기록은 보존)
  Future<void> _deleteBike(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('재고 삭제'),
        content: Text('${b['code'] ?? ''} 항목을 재고 목록에서 지울까요?\n'
            '신고 기록은 ‘수거 완료’로 그대로 남습니다.'),
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
      await ref
          .read(adminServiceProvider)
          .deleteBike(b['id'] as String);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('재고에서 삭제되었습니다')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> b) async {
    final report = b['reports'] as Map<String, dynamic>?;
    final storageCtl =
        TextEditingController(text: b['storage_location'] as String? ?? '');
    final fmt = DateFormat('yyyy-MM-dd');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SignedPhoto(
                    path: report?['photo_url'] as String? ?? '', size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b['code'] as String? ?? '(번호 없음)',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(
                        report?['address'] as String? ?? '주소 없음',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '신고 ${fmt.format(DateTime.parse(report?['reported_at'] as String? ?? b['collected_at'] as String))}'
                        ' · 수거 ${fmt.format(DateTime.parse(b['collected_at'] as String))}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.dateGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('상태 변경',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in kBikeStateLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: b['state'] == e.key,
                    onSelected: (_) async {
                      await ref
                          .read(adminServiceProvider)
                          .updateBikeState(b['id'] as String, e.key);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('보관 장소',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: storageCtl,
                    decoration: const InputDecoration(
                        hintText: '예: 보관소 A동 3번 랙'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 48)),
                  onPressed: () async {
                    await ref.read(adminServiceProvider).updateBikeStorage(
                        b['id'] as String, storageCtl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  child: const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 상단 요약 대시보드 — 총보유 + 상태별 대수
  Widget _summaryCard() {
    (Color, Color) colorOf(String key) => switch (key) {
          'storage' => (AppColors.pendingBg, AppColors.pendingFg),
          'disposal' => (AppColors.grayBg, AppColors.grayFg),
          _ => (AppColors.doneBg, AppColors.doneFg),
        };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 12,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('총 보유',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              const SizedBox(width: 8),
              Text('$_total대',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final e in kBikeStateLabels.entries) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 7, horizontal: 4),
                        decoration: BoxDecoration(
                          color: colorOf(e.key).$1,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text('${_summary[e.key] ?? 0}',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colorOf(e.key).$2)),
                      ),
                      const SizedBox(height: 5),
                      Text(e.value,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sub)),
                    ],
                  ),
                ),
                if (e.key != kBikeStateLabels.keys.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM.dd');

    return Column(
      children: [
        // 상단 요약 대시보드
        if (!_loading) _summaryCard(),
        // 검색 + 필터
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: '관리번호 검색 (예: 서귀포시_20260721)',
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.faint),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: AppColors.primary),
                  onPressed: _load),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ChoiceChip(
                label: const Text('전체'),
                selected: _stateFilter == null,
                onSelected: (_) {
                  setState(() => _stateFilter = null);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              for (final e in kBikeStateLabels.entries) ...[
                ChoiceChip(
                  label: Text(e.value),
                  selected: _stateFilter == e.key,
                  onSelected: (_) {
                    setState(() => _stateFilter = e.key);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _bikes.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(
                              child: Text('수거된 자전거가 없습니다.',
                                  style: TextStyle(
                                      color: AppColors.muted))),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _bikes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final b = _bikes[i];
                            final r =
                                b['reports'] as Map<String, dynamic>?;
                            final state = b['state'] as String? ?? '';
                            return GestureDetector(
                              onTap: () => _openDetail(b),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: AppColors.shadowCard,
                                        blurRadius: 10,
                                        offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    SignedPhoto(
                                        path: r?['photo_url']
                                                as String? ??
                                            '',
                                        size: 60),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              b['code'] as String? ??
                                                  '-',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 14.5),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text(
                                            '수거 ${fmt.format(DateTime.parse(b['collected_at'] as String))}',
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors
                                                    .dateGray),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            r?['address'] as String? ??
                                                '주소 없음',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors.sub),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          if ((b['storage_location']
                                                      as String? ??
                                                  '')
                                              .isNotEmpty)
                                            Text(
                                              '📍 ${b['storage_location']}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.muted),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        StatusChip(
                                          label:
                                              kBikeStateLabels[state] ??
                                                  state,
                                          status: state == 'disposal'
                                              ? 'rejected'
                                              : (state == 'storage'
                                                  ? 'scheduled'
                                                  : 'collected'),
                                        ),
                                        const SizedBox(height: 2),
                                        GestureDetector(
                                          onTap: () => _deleteBike(b),
                                          behavior: HitTestBehavior
                                              .opaque,
                                          child: const Padding(
                                            padding: EdgeInsets.only(
                                                top: 4,
                                                left: 8,
                                                right: 2),
                                            child: Icon(
                                                Icons.delete_outline,
                                                size: 19,
                                                color:
                                                    AppColors.chevron),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
