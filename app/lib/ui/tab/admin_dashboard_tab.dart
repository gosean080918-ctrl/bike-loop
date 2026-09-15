import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';

/// ADM-09: 대시보드 — 수거 실적 + 순환(재생) 성과 + 운영 효율
class AdminDashboardTab extends ConsumerWidget {
  const AdminDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          const SizedBox(height: 100),
          Center(child: Text('통계 조회 실패: $e')),
        ]),
        data: (d) {
          final byStatus = (d['byStatus'] as Map).cast<String, int>();
          final byCondition =
              (d['byCondition'] as Map).cast<String, int>();
          final byState = (d['byState'] as Map).cast<String, int>();
          final rate = d['recycleRate'] as double;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              // ── 핵심 지표 4개 ──
              Row(children: [
                _metric('총 신고', '${d['reportTotal']}건',
                    AppColors.primarySoft, AppColors.primary),
                const SizedBox(width: 10),
                _metric('수거 완료', '${d['collected']}대',
                    AppColors.doneBg, AppColors.doneFg),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _metric('수거 작업', '${d['jobCount']}회',
                    AppColors.pendingBg, AppColors.pendingFg),
                const SizedBox(width: 10),
                _metric(
                    '평균 처리',
                    (d['avgLeadDays'] as double) == 0
                        ? '-'
                        : '${(d['avgLeadDays'] as double).toStringAsFixed(1)}일',
                    AppColors.grayBg,
                    AppColors.grayFg),
              ]),
              const SizedBox(height: 20),

              // ── 순환 성과 (대회 어필 포인트) ──
              _card(
                title: '순환 성과',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${rate.round()}%',
                            style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                letterSpacing: -1)),
                        const SizedBox(width: 8),
                        const Text('재생률',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.sub)),
                        const Spacer(),
                        Text(
                            '재생 ${d['recycled']}대 · 폐기 ${d['disposed']}대',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 재생 vs 폐기 비율 바
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 10,
                        child: Row(children: [
                          Expanded(
                            flex: (rate * 10).round().clamp(0, 1000),
                            child: Container(color: AppColors.primary),
                          ),
                          Expanded(
                            flex: ((100 - rate) * 10)
                                .round()
                                .clamp(0, 1000),
                            child: Container(
                                color: const Color(0xFFDDE5DC)),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('수리·기부·재사용으로 살린 비율입니다',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 재고 상태 ──
              _card(
                title: '재고 현황 (총 ${d['bikeTotal']}대)',
                child: Column(
                  children: [
                    for (final e in kBikeStateLabels.entries)
                      _bar(e.value, byState[e.key] ?? 0,
                          d['bikeTotal'] as int),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 신고 처리 현황 ──
              _card(
                title: '신고 처리 현황',
                child: Column(
                  children: [
                    for (final e in kStatusLabels.entries)
                      if ((byStatus[e.key] ?? 0) > 0)
                        _bar(e.value, byStatus[e.key] ?? 0,
                            d['reportTotal'] as int),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 신고 유형 분포 ──
              _card(
                title: '신고 유형 분포',
                child: Column(
                  children: [
                    for (final e in kConditionLabels.entries)
                      if ((byCondition[e.key] ?? 0) > 0)
                        _bar(e.value, byCondition[e.key] ?? 0,
                            d['reportTotal'] as int),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 운영 효율 ──
              _card(
                title: '운영 효율',
                child: Column(
                  children: [
                    _kv('누적 이동거리',
                        '${(d['totalDistanceKm'] as double).toStringAsFixed(1)} km'),
                    _kv('누적 작업시간',
                        '${(d['totalDurationMin'] as double).round()} 분'),
                    _kv(
                        '작업당 평균 거리',
                        (d['jobCount'] as int) == 0
                            ? '-'
                            : '${((d['totalDistanceKm'] as double) / (d['jobCount'] as int)).toStringAsFixed(1)} km'),
                    _kv(
                        '자전거 1대당 이동',
                        (d['collected'] as int) == 0
                            ? '-'
                            : '${((d['totalDistanceKm'] as double) / (d['collected'] as int)).toStringAsFixed(1)} km'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text('※ 경로는 OR-Tools 최적화 + 카카오 도로 기준입니다',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.muted)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value, Color bg, Color fg) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg.withOpacity(0.8))),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: fg)),
            ],
          ),
        ),
      );

  Widget _card({required String title, required Widget child}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _bar(String label, int value, int total) {
    final ratio = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.sub)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  Expanded(
                    flex: (ratio * 1000).round().clamp(1, 1000),
                    child: Container(color: AppColors.primary),
                  ),
                  Expanded(
                    flex: ((1 - ratio) * 1000).round().clamp(0, 1000),
                    child: Container(color: const Color(0xFFEDF1ED)),
                  ),
                ]),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text('$value',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.sub)),
            Text(v,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
          ],
        ),
      );
}
