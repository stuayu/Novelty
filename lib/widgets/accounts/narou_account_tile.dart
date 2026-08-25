import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/novel_source.dart';

/// 「もっと」画面に表示する小説家になろうアカウント欄。
class NarouAccountTile extends ConsumerWidget {
  /// コンストラクタ。
  const NarouAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const source = NovelSource.narou;
    final authAsync = ref.watch(accountAuthStateProvider(source));
    return authAsync.when(
      data: (authState) {
        if (!authState.isLoggedIn) {
          return ListTile(
            leading: const Icon(Icons.login),
            title: const Text('小説家になろう'),
            subtitle: const Text('未ログイン・ブックマーク同期としおり連携'),
            trailing: const Text('ログイン'),
            onTap: () => const LoginRoute().push<void>(context),
          );
        }

        return ExpansionTile(
          leading: const Icon(Icons.account_circle),
          title: const Text('小説家になろう'),
          subtitle: Text(authState.displayName ?? 'ログイン済み'),
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('ブックマークを同期'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final adapter = ref.read(accountSyncRegistryProvider)[source];
                final count = await adapter?.pullLibrary() ?? 0;
                messenger.showSnackBar(
                  SnackBar(content: Text('$count 件のブックマークを同期しました')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final adapter = ref.read(accountSyncRegistryProvider)[source];
                await adapter?.logout();
                ref.invalidate(accountAuthStateProvider(source));
                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('ログアウトしました')),
                );
              },
            ),
          ],
        );
      },
      loading: () => const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('小説家になろう'),
        subtitle: Text('認証状態を確認中...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('小説家になろう'),
        subtitle: Text('認証状態を確認できませんでした: $error'),
      ),
    );
  }
}
