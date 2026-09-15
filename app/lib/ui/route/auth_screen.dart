import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../const/value/app_theme.dart';
import '../../state_management/providers.dart';

/// AUTH-02: 이메일 로그인/회원가입 (Supabase Auth)
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    try {
      if (_isSignUp) {
        await auth.signUp(
            _email.text.trim(), _password.text, _name.text.trim());
      } else {
        await auth.signIn(_email.text.trim(), _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('인증 오류: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 브랜드 헤더 (BIKE LOOP 로고 + 워드마크)
                  Center(
                    child: Image.asset('assets/logo.png',
                        width: 110, height: 110),
                  ),
                  const SizedBox(height: 14),
                  const Center(child: BrandWordmark(fontSize: 30)),
                  const SizedBox(height: 6),
                  Text(
                    '우리 동네 방치 자전거를 함께 정리해요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textSub),
                  ),
                  const SizedBox(height: 36),

                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: '이름/별명'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '이름을 입력하세요'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: '이메일'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? '이메일 형식이 아닙니다'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length < 6) ? '6자 이상 입력하세요' : null,
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : Text(_isSignUp ? '가입하기' : '로그인'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp
                        ? '이미 계정이 있어요 → 로그인'
                        : '계정이 없어요 → 회원가입'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
