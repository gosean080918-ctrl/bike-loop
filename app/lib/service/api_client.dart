import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 최적화 서버 호출 공통 클라이언트 (2026-09-15, 일반 공개 대비)
///
/// [왜 있는가]
/// 서버의 /address · /search 는 카카오 REST 키를 대신 호출해 준다.
/// 인증 없이 열어두면 서버 주소를 아는 누구나 남의 할당량을 태울 수 있어,
/// 서버가 '로그인한 사용자'만 받도록 바뀌었다(server/auth.py).
/// 그래서 앱의 모든 서버 호출에는 Supabase 로그인 토큰이 붙어야 한다.
///
/// 호출부에서 헤더를 매번 조립하면 빠뜨리기 쉬우므로 여기로 모았다.
class ApiClient {
  /// 현재 로그인 세션의 액세스 토큰. 로그아웃 상태면 null.
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

  /// 서버가 401을 돌려줬을 때 사용자에게 보여줄 안내 문구.
  /// (토큰 만료 등 — 다시 로그인하면 해결된다)
  static const String authErrorMessage = '로그인이 만료되었습니다. 다시 로그인해주세요.';
}
