import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/app_user.dart';

/// AUTH-02: Supabase email auth plus profile lookup
/// The profile row is created automatically on sign-up by the handle_new_user trigger.
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
        data: {'display_name': displayName}, // the trigger copies this into profiles
      );

  Future<void> signOut() => _client.auth.signOut();

  /// The signed-in user's profile, including role, used to branch the UI (AUTH-03)
  Future<Profile?> fetchMyProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }
}
