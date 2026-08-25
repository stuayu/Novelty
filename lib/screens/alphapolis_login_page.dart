import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/screens/form_account_login_page.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

/// アルファポリスのログイン画面。
class AlphapolisLoginPage extends ConsumerWidget {
  /// コンストラクタ。
  const AlphapolisLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormAccountLoginPage(
      source: NovelSource.alphapolis,
      title: 'アルファポリスにログイン',
      accountLabel: 'メールアドレス',
      login: (accountId, password) => ref
          .read(alphapolisAuthServiceProvider)
          .login(email: accountId, password: password),
    );
  }
}
