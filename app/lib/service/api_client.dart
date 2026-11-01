import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared client for calls to the optimization server (2026-09-15, added before the public launch)
///
/// [Why this exists]
/// The server's /address and /search call the Kakao REST API on our behalf.
/// Left unauthenticated, anyone who knows the server URL could burn our quota, so
/// the server now accepts signed-in users only (server/auth.py).
/// Every server call from the app therefore carries the Supabase access token.
///
/// Assembling that header at each call site is easy to forget, so it is centralised here.
class ApiClient {
  /// The current session's access token; null when signed out.
  static String? get _token =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  static Map<String, String> get _headers {
    final t = _token;
    return {
      'Accept': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  static Future<http.Response> get(Uri url, {Duration? timeout}) {
    final req = http.get(url, headers: _headers);
    return timeout == null ? req : req.timeout(timeout);
  }

  static Future<http.Response> postJson(
    Uri url,
    String body, {
    Duration? timeout,
  }) {
    final req = http.post(
      url,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: body,
    );
    return timeout == null ? req : req.timeout(timeout);
  }

  /// Message shown to the user when the server returns 401.
  /// (usually an expired token: signing in again fixes it)
  static const String authErrorMessage = 'Your session expired. Please sign in again.';
}
