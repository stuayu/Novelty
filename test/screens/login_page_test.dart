import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/screens/login_page.dart';
import 'package:novelty/services/narou_auth_service.dart';

class _MfaAuthService extends NarouAuthService {
  _MfaAuthService() : super(authRepository: AuthRepository());

  String? submittedCode;
  bool loginCalled = false;

  @override
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
  }) async {
    loginCalled = true;
    return const NarouLoginResult.mfaRequired();
  }

  @override
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    submittedCode = code;
    return const NarouLoginResult.failure('認証コードを確認できませんでした');
  }
}

void main() {
  testWidgets('MFA待ちではパスワードを消し安全な確認コード入力へ切り替える', (tester) async {
    final authService = _MfaAuthService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          narouAuthServiceProvider.overrideWithValue(authService),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'ユーザーIDまたはメールアドレス'),
      'reader@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'パスワード'),
      'secret-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    expect(authService.loginCalled, isTrue);
    expect(find.text('二段階認証'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'パスワード'), findsNothing);
    final codeTextField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('narou-mfa-code')),
        matching: find.byType(TextField),
      ),
    );
    expect(codeTextField.obscureText, isTrue);
    expect(codeTextField.autofillHints, contains(AutofillHints.oneTimeCode));

    await tester.enterText(
      find.byKey(const Key('narou-mfa-code')),
      '123456',
    );
    await tester.tap(find.widgetWithText(FilledButton, '認証コードを確認'));
    await tester.pumpAndSettle();

    expect(authService.submittedCode, '123456');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('narou-mfa-code')),
          )
          .controller!
          .text,
      isEmpty,
    );

    expect(find.text('最初からやり直す'), findsOneWidget);
    await tester.tap(find.text('最初からやり直す'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'ユーザーIDまたはメールアドレス'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('narou-mfa-code')), findsNothing);
  });
}
