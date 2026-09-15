import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/app_user.dart';

/// AUTH-02: Supabase Auth (이메일) + 프로필 조회
/// 프로필 행은 회원가입 시 DB 트리거(handle_new_user)가 자동 생성.
class AuthService {
  final _client = Supabase.instance.client;

  Stream<AuthState> get authState => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signUp(String email, String password, String displayName) =>
      _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName}, // 트리거가 profiles에 복사
      );

  Future<void> signOut() => _client.auth.signOut();

  /// 내 프로필 (role 포함 — 화면 분기용, AUTH-03)
  Future<Profile?> fetchMyProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }
}
