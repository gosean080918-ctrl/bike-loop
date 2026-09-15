import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'const/value/app_theme.dart';
import 'const/value/constants.dart';
import 'ui/route/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  // 카카오맵 JS 키 (지도 표시 전용)
  // ※ baseUrl(http://localhost)을 넣으면 웹뷰가 http 페이지로 취급되어
  //    카카오 지도 본체 스크립트 로드가 차단되는 문제 확인(2026-07-19) — 넣지 말 것
  AuthRepository.initialize(appKey: kKakaoJsKey);

  runApp(const ProviderScope(child: BikeReclaimApp()));
}

/// 전역 Supabase 클라이언트 접근자
final supabase = Supabase.instance.client;

class BikeReclaimApp extends StatelessWidget {
  const BikeReclaimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BIKE LOOP',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
