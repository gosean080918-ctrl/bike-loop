import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';

/// ADM-09: dashboard — collection output, reuse performance, operating efficiency
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
          Center(child: Text('Could not load statistics: $e')),
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
              // -- The four headline metrics --
              Row(children: [
                _metric('Reports', '${d['reportTotal']}',
                    AppColors.primarySoft, AppColors.primary),
                const SizedBox(width: 10),
                _metric('Collected', '${d['collected']}',
                    AppColors.doneBg, AppColors.doneFg),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _metric('Jobs', '${d['jobCount']}',
                    AppColors.pendingBg, AppColors.pendingFg),
                const SizedBox(width: 10),
                _metric(
                    'Avg. time',
                    (d['avgLeadDays'] as double) == 0
                        ? '-'
                        : '${(d['avgLeadDays'] as double).toStringAsFixed(1)}d',
                    AppColors.grayBg,
                    AppColors.grayFg),
              ]),
              const SizedBox(height: 20),

              // -- Reuse performance --
              _card(
                title: 'Circulation',
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
                        const Text('recycle rate',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.sub)),
                        const Spacer(),
                        Text(
                            '${d['recycled']} saved · ${d['disposed']} disposed',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Reuse vs disposal ratio bar
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
                    const Text('Share saved through repair, donation or reuse',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // -- Inventory state --
              _card(
                title: 'Inventory (${d['bikeTotal']} total)',
                child: Column(
                  children: [
                    for (final e in kBikeStateLabels.entries)
                      _bar(e.value, byState[e.key] ?? 0,
                          d['bikeTotal'] as int),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // -- Report processing status --
              _card(
                title: 'Report status',
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

              // -- Distribution of report types --
              _card(
                title: 'Report types',
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

              // -- Operating efficiency --
              _card(
                title: 'Efficiency',
                child: Column(
                  children: [
                    _kv('Total distance',
                        '${(d['totalDistanceKm'] as double).toStringAsFixed(1)} km'),
                    _kv('Total time',
                        '${(d['totalDurationMin'] as double).round()} min'),
                    _kv(
                        'Per job',
                        (d['jobCount'] as int) == 0
                            ? '-'
                            : '${((d['totalDistanceKm'] as double) / (d['jobCount'] as int)).toStringAsFixed(1)} km'),
                    _kv(
                        'Per bicycle',
                        (d['collected'] as int) == 0
                            ? '-'
                            : '${((d['totalDistanceKm'] as double) / (d['collected'] as int)).toStringAsFixed(1)} km'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text('Routes: OR-Tools optimization on Kakao road data',
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
