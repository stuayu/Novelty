import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/screens/form_account_login_page.dart';
import 'package:novelty/services/novelup_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

/// ノベルアップ＋のログイン画面。
class NovelupLoginPage extends ConsumerWidget {
  /// コンストラクタ。
  const NovelupLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormAccountLoginPage(
      source: NovelSource.novelup,
      title: 'ノベルアップ＋にログイン',
      accountLabel: 'メールアドレス',
      login: (accountId, password) => ref
          .read(novelupAuthServiceProvider)
          .login(mail: accountId, password: password),
    );
  }
}
