import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/app_user.dart';
import '../const/model/report.dart';
import '../service/admin_service.dart';
import '../service/auth_service.dart';
import '../service/location_service.dart';
import '../service/report_service.dart';
import '../service/settings_service.dart';

// Service singletons
final authServiceProvider = Provider((ref) => AuthService());
final reportServiceProvider = Provider((ref) => ReportService());
final locationServiceProvider = Provider((ref) => LocationService());
final adminServiceProvider = Provider((ref) => AdminService());
final settingsServiceProvider = Provider((ref) => SettingsService());

/// Depot settings; invalidate the provider to refresh after a change
final depotProvider = FutureProvider<DepotConfig>(
    (ref) => ref.watch(settingsServiceProvider).load());

/// Auth state stream (Supabase Auth)
final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authServiceProvider).authState);

/// The currently signed-in user, for convenience
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider); // recompute on sign-in and sign-out
  return ref.watch(authServiceProvider).currentUser;
});

/// The user's profile, including role, used to branch admin features
final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).fetchMyProfile();
});

/// Map tab: the list of active reports (refreshable)
final activeReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(reportServiceProvider).fetchActive());

/// The user's own report history
final myReportsProvider = FutureProvider<List<Report>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(<Report>[]);
  return ref.watch(reportServiceProvider).fetchMyReports(user.id);
});

// ---------- Admin ----------

/// Reports awaiting review (submitted)
final pendingReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(adminServiceProvider).fetchByStatus('submitted'));

/// Approved reports: candidates for collection
final approvedReportsProvider = FutureProvider<List<Report>>(
    (ref) => ref.watch(adminServiceProvider).fetchByStatus('approved'));

/// Collection jobs, including their visit order and the underlying reports
final jobsProvider = FutureProvider<List<Map<String, dynamic>>>(
    (ref) => ref.watch(adminServiceProvider).fetchJobs());

/// ADM-09 dashboard statistics
final dashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ref.watch(adminServiceProvider).fetchDashboard());
