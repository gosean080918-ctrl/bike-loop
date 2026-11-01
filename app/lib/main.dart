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

  // Kakao Maps JavaScript key (map display only)
  // NOTE: passing baseUrl (http://localhost) makes the WebView treat this as an
  //    http page, which blocks the main Kakao Maps script (found 2026-07-19) — do not set it
  AuthRepository.initialize(appKey: kKakaoJsKey);

  runApp(const ProviderScope(child: BikeReclaimApp()));
}

/// Global accessor for the Supabase client
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
