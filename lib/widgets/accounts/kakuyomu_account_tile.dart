import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/screens/kakuyomu_login_page.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';

/// 「もっと」画面に表示するカクヨムアカウント欄。
class KakuyomuAccountTile extends ConsumerWidget {
  /// コンストラクタ。
  const KakuyomuAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(kakuyomuSessionValidProvider);
    return sessionAsync.when(
      data: (isLoggedIn) {
        if (!isLoggedIn) {
          return ListTile(
            leading: const Icon(Icons.login),
            title: const Text('カクヨム'),
            subtitle: const Text('未ログイン・公式ログイン画面を使用します'),
            trailing: const Text('ログイン'),
            onTap: () => _login(context, ref),
          );
        }

        return ExpansionTile(
          leading: const Icon(Icons.account_circle),
          title: const Text('カクヨム'),
          subtitle: const Text('ログイン済み'),
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('フォロー作品を同期'),
              subtitle: const Text('カクヨムでフォロー中の作品をNoveltyへ追加します'),
              onTap: () => _syncFollowedWorks(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () => _logout(context, ref),
            ),
          ],
        );
      },
      loading: () => const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('カクヨム'),
        subtitle: Text('認証状態を確認中...'),
      ),
      error: (_, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('カクヨム'),
        subtitle: const Text('認証状態を確認できませんでした'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(kakuyomuSessionValidProvider),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const KakuyomuLoginPage(),
      ),
    );
    ref.invalidate(kakuyomuSessionValidProvider);
    if (success != true || !context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('カクヨムにログインしました')),
    );
  }

  Future<void> _syncFollowedWorks(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await ref
          .read(kakuyomuAccountSyncAdapterProvider)
          .pullLibrary();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$count 件のフォロー作品を追加しました')),
      );
    } on KakuyomuSessionExpiredException {
      try {
        await ref.read(kakuyomuAuthServiceProvider).logout();
      } on Exception {
        // 永続Cookieの削除に失敗しても認証状態は再評価する。
      }
      ref.invalidate(kakuyomuSessionValidProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('カクヨムのログイン期限が切れました。再ログインしてください'),
        ),
      );
    } on Exception {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('フォロー作品の同期に失敗しました')),
      );
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(kakuyomuAuthServiceProvider).logout();
    ref.invalidate(kakuyomuSessionValidProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('カクヨムからログアウトしました')),
    );
  }
}
