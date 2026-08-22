import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/router/router.dart';

/// 「もっと」画面に表示する小説家になろうアカウント欄。
class NarouAccountTile extends ConsumerWidget {
  /// コンストラクタ。
  const NarouAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);
    return authAsync.when(
      data: (user) {
        if (user == null) {
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
          subtitle: Text(user.username),
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('ブックマークを同期'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final count = await ref
                    .read(authProvider.notifier)
                    .syncBookmarks();
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
                await ref.read(authProvider.notifier).logout();
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
