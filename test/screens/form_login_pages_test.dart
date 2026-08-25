import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/screens/alphapolis_login_page.dart';
import 'package:novelty/screens/form_account_login_page.dart';
import 'package:novelty/screens/hameln_login_page.dart';
import 'package:novelty/screens/novelup_login_page.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  final cases = <(Widget, String, String)>[
    (const AlphapolisLoginPage(), 'アルファポリスにログイン', 'メールアドレス'),
    (const HamelnLoginPage(), 'ハーメルンにログイン', 'ユーザーID'),
    (const NovelupLoginPage(), 'ノベルアップ＋にログイン', 'メールアドレス'),
  ];

  for (final (page, title, accountLabel) in cases) {
    testWidgets('$title は資格情報フォームを表示する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: page)),
      );

      expect(find.text(title), findsOneWidget);
      expect(find.text(accountLabel), findsOneWidget);
      expect(find.text('パスワード'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'ログイン'), findsOneWidget);
      expect(find.textContaining('成功後のセッション'), findsOneWidget);
    });
  }

  group('ログイン処理の例外', () {
    Future<void> pumpAndSubmit(
      WidgetTester tester,
      FormAccountLogin login,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FormAccountLoginPage(
              source: NovelSource.alphapolis,
              title: 'テストログイン',
              accountLabel: 'メールアドレス',
              login: login,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'メールアドレス'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'パスワード'),
        'password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
      await tester.pumpAndSettle();
    }

    testWidgets('例外が投げられても進捗表示が解除される', (tester) async {
      await pumpAndSubmit(
        tester,
        (account, password) async => throw StateError('想定外の失敗'),
      );

      // finally が無いと CircularProgressIndicator が回り続ける
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.widgetWithText(FilledButton, 'ログイン'), findsOneWidget);
      expect(find.textContaining('ログインに失敗しました'), findsOneWidget);
    });

    testWidgets('失敗結果でも進捗表示が解除される', (tester) async {
      await pumpAndSubmit(
        tester,
        (account, password) async =>
            const FormAuthLoginResult.failure('IDまたはパスワードが違います'),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('IDまたはパスワードが違います'), findsOneWidget);
    });
  });
}
