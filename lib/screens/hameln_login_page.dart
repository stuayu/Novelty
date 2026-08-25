import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/screens/form_account_login_page.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

/// ハーメルンのログイン画面。
class HamelnLoginPage extends ConsumerWidget {
  /// コンストラクタ。
  const HamelnLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormAccountLoginPage(
      source: NovelSource.hameln,
      title: 'ハーメルンにログイン',
      accountLabel: 'ユーザーID',
      login: (accountId, password) => ref
          .read(hamelnAuthServiceProvider)
          .login(id: accountId, password: password),
    );
  }
}
