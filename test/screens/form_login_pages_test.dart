import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/screens/alphapolis_login_page.dart';
import 'package:novelty/screens/hameln_login_page.dart';
import 'package:novelty/screens/novelup_login_page.dart';

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
}
