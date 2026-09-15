import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/app_user.dart';
import '../const/model/report.dart';
import '../service/admin_service.dart';
import '../service/auth_service.dart';
import '../service/location_service.dart';
import '../service/report_service.dart';
import '../service/settings_service.dart';

// 서비스 싱글턴
final authServiceProvider = Provider((ref) => AuthService());
final reportServiceProvider = Provider((ref) => ReportService());
final locationServiceProvider = Provider((ref) => LocationService());
final adminServiceProvider = Provider((ref) => AdminService());
final settingsServiceProvider = Provider((ref) => SettingsService());

/// 출발지/복귀지 설정 (변경 시 invalidate로 갱신)
final depotProvider = FutureProvider<DepotConfig>(
    (ref) => ref.watch(settingsServiceProvider).load());

/// 로그인 상태 스트림 (Supabase Auth)
final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authServiceProvider).authState);

/// 현재 로그인 유저 (편의)
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider); // 로그인/로그아웃 시 재계산
  return ref.watch(authServiceProvider).currentUser;
});

/// 내 프로필 (role 포함 — 관리자 분기용)
final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).fetchMyProfile();
});

/// 지도 탭: 활성 신고 목록 (refresh 가능)
final activeReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(reportServiceProvider).fetchActive());

/// 내 신고 이력
final myReportsProvider = FutureProvider<List<Report>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(<Report>[]);
  return ref.watch(reportServiceProvider).fetchMyReports(user.id);
});

// ---------- 관리자 ----------

/// 검토 대기(submitted) 신고
final pendingReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(adminServiceProvider).fetchByStatus('submitted'));

/// 승인됨(approved) — 수거 대상 후보
final approvedReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(adminServiceProvider).fetchByStatus('approved'));

/// 수거 작업 목록(방문순서+신고 포함)
final jobsProvider = FutureProvider<List<Map<String, dynamic>>>(
    (ref) => ref.watch(adminServiceProvider).fetchJobs());

/// ADM-09 대시보드 통계
final dashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ref.watch(adminServiceProvider).fetchDashboard());
