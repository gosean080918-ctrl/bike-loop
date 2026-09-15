import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../state_management/providers.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

/// AUTH-01: 스플래시 + 로그인 여부 분기
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      data: (_) {
        final user = ref.watch(currentUserProvider);
        return user == null ? const AuthScreen() : const HomeScreen();
      },
      loading: () => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', width: 130, height: 130),
              const SizedBox(height: 16),
              const BrandWordmark(fontSize: 28),
              const SizedBox(height: 28),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.6, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('초기화 오류: $e')),
      ),
    );
  }
}
