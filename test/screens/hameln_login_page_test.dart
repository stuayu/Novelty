import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/screens/hameln_login_page.dart';
import 'package:novelty/utils/hameln_webview_support.dart';

void main() {
  testWidgets('WebView非対応環境では利用不可メッセージを表示する', (tester) async {
    if (isHamelnWebViewSupported) return;

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: HamelnLoginPage()),
      ),
    );

    expect(find.text('ハーメルンアカウント連携は現在このOSでは利用できません。'), findsOneWidget);
    expect(find.byType(Form), findsNothing);
  });
}
