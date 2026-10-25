import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/screens/login_page.dart';
import 'package:novelty/services/narou_auth_service.dart';

import '../helpers/clipboard.dart';

class _MfaAuthService extends NarouAuthService {
  _MfaAuthService({
    this.retainMfaAfterVerification = false,
    this.diagnosticsEnabledForTest = false,
    this.diagnosticsTraceEnabledForTest = false,
  }) : super(authRepository: AuthRepository());

  String? submittedCode;
  bool loginCalled = false;
  bool? rememberSession;
  bool challengeCancelled = false;
  Error? loginError;
  final bool retainMfaAfterVerification;
  final bool diagnosticsEnabledForTest;
  final bool diagnosticsTraceEnabledForTest;
  bool delayLogin = false;
  final loginStarted = Completer<void>();
  final loginCompletion = Completer<NarouLoginResult>();
  final diagnosticEvents = <String>[];
  final diagnosticTraces = <Map<String, Object?>>[];

  @override
  bool get diagnosticsEnabled => diagnosticsEnabledForTest;

  @override
  bool get diagnosticsTraceEnabled => diagnosticsTraceEnabledForTest;

  @override
  Future<String?> diagnosticsLogFilePath() async =>
      diagnosticsTraceEnabledForTest
      ? '/tmp/narou_auth_trace.jsonl'
      : diagnosticsEnabledForTest
      ? '/tmp/narou_auth_diagnostics.jsonl'
      : null;

  @override
  void recordDiagnosticEvent(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    diagnosticEvents.add(event);
  }

  @override
  void recordDiagnosticTrace(
    String operationId,
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    diagnosticTraces.add(<String, Object?>{'event': event, ...fields});
  }

  @override
  void cancelMfaChallenge() => challengeCancelled = true;

  @override
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
    bool rememberSession = true,
  }) async {
    loginCalled = true;
    this.rememberSession = rememberSession;
    if (loginError != null) throw loginError!;
    if (delayLogin) {
      loginStarted.complete();
      return loginCompletion.future;
    }
    return const NarouLoginResult.mfaRequired();
  }

  @override
  Future<NarouLoginResult> verifyMfaCode(String code) async {
    submittedCode = code;
    if (retainMfaAfterVerification) {
      return const NarouLoginResult.failure(
        '認証コードを確認できませんでした',
        canRetryMfa: true,
      );
    }
    return const NarouLoginResult.failure(
      '認証コードを確認できません。最初からログインしてください。',
    );
  }
}

void main() {
  testWidgets('MFA待ちではパスワードを消し安全な確認コード入力へ切り替える', (tester) async {
    final authService = _MfaAuthService(retainMfaAfterVerification: true);
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
    expect(authService.rememberSession, isTrue);
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

  testWidgets('失効したMFAチャレンジでは資格情報ログインへ戻す', (tester) async {
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
    await tester.enterText(find.byKey(const Key('narou-mfa-code')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '認証コードを確認'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('narou-mfa-code')), findsNothing);
    expect(authService.challengeCancelled, isTrue);
    expect(
      find.widgetWithText(TextFormField, 'ユーザーIDまたはメールアドレス'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'パスワード'), findsOneWidget);
  });

  testWidgets('永続ログインのチェックを外すと短期セッションを指定する', (tester) async {
    final authService = _MfaAuthService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          narouAuthServiceProvider.overrideWithValue(authService),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    final rememberCheckbox = find.byKey(const Key('narou-remember-session'));
    expect(tester.widget<CheckboxListTile>(rememberCheckbox).value, isTrue);
    expect(
      find.textContaining('ログインIDとセッション情報はSecure Storageに保存されます。'),
      findsOneWidget,
    );
    await tester.tap(rememberCheckbox);
    await tester.pump();
    expect(
      find.textContaining('ログインIDとセッション情報はアプリを閉じるまで保持し、終了時に破棄します。'),
      findsOneWidget,
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

    expect(authService.rememberSession, isFalse);
  });

  testWidgets('MFA画面を閉じると保留中チャレンジを破棄する', (tester) async {
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
    expect(find.byKey(const Key('narou-mfa-code')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(authService.challengeCancelled, isTrue);
  });

  testWidgets('パスワード送信中に画面を閉じても認証処理をキャンセルする', (tester) async {
    final authService = _MfaAuthService()..delayLogin = true;
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
    await tester.pump();
    await authService.loginStarted.future;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(authService.challengeCancelled, isTrue);

    authService.loginCompletion.complete(const NarouLoginResult.mfaRequired());
    await tester.pumpAndSettle();
  });

  testWidgets('開発時はログイン前からTraceログのパスをコピーできる', (tester) async {
    final clipboard = installClipboardMock(tester);
    addTearDown(clipboard.dispose);
    final authService = _MfaAuthService(
      diagnosticsEnabledForTest: true,
      diagnosticsTraceEnabledForTest: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          narouAuthServiceProvider.overrideWithValue(authService),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    expect(authService.diagnosticEvents, contains('login-screen.opened'));
    final copyButton = find.byKey(const Key('narou-copy-diagnostics-path'));
    expect(copyButton, findsOneWidget);
    expect(find.text('Traceログのパスをコピー'), findsOneWidget);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    clipboard.expectCopiedText('/tmp/narou_auth_trace.jsonl');
  });

  testWidgets('ログイン画面で捕捉した例外をTraceログへ残す', (tester) async {
    final authService = _MfaAuthService(
      diagnosticsEnabledForTest: true,
      diagnosticsTraceEnabledForTest: true,
    )..loginError = StateError('adapter failed');
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

    final errorTrace = authService.diagnosticTraces.singleWhere(
      (entry) => entry['event'] == 'login.provider.error',
      orElse: () => <String, Object?>{},
    );
    expect(errorTrace['error'], contains('adapter failed'));
    expect(errorTrace['stackTrace'], contains('NarouLogin.login'));
  });
}
