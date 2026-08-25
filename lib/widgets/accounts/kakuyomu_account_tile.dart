import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// 「もっと」画面に表示するカクヨムアカウント欄。
class KakuyomuAccountTile extends ConsumerWidget {
  /// コンストラクタ。
  const KakuyomuAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const source = NovelSource.kakuyomu;
    final sessionAsync = ref.watch(accountAuthStateProvider(source));
    return sessionAsync.when(
      data: (authState) {
        if (!authState.isLoggedIn) {
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
              title: const Text('フォロー作品・閲覧履歴を同期'),
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
          onPressed: () => ref.invalidate(accountAuthStateProvider(source)),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final success = await const KakuyomuLoginRoute().push<bool>(context);
    ref.invalidate(accountAuthStateProvider(NovelSource.kakuyomu));
    if (success != true || !context.mounted) return;
    await _syncFollowedWorks(context, ref);
  }

  Future<void> _syncFollowedWorks(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await ref
          .read(kakuyomuAccountSyncAdapterProvider)
          .pullLibrary();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$count 件の作品を同期しました')),
      );
    } on KakuyomuSessionExpiredException {
      try {
        await ref.read(kakuyomuAccountSyncAdapterProvider).logout();
      } on Exception {
        // 永続Cookieの削除に失敗しても認証状態は再評価する。
      }
      ref.invalidate(accountAuthStateProvider(NovelSource.kakuyomu));
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('カクヨムのログイン期限が切れました。再ログインしてください'),
        ),
      );
    } on Exception {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('カクヨム作品・閲覧履歴の同期に失敗しました')),
      );
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(kakuyomuAccountSyncAdapterProvider).logout();
    ref.invalidate(accountAuthStateProvider(NovelSource.kakuyomu));
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('カクヨムからログアウトしました')),
    );
  }
}
