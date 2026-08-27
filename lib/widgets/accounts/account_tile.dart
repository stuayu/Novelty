import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/novel_source.dart';

/// ログイン画面を開き、ログイン成功時は `true` を返す処理。
typedef AccountLoginAction = Future<bool?> Function(BuildContext context);

/// サイト固有のアカウントタイル表示設定。
class AccountTileConfiguration {
  /// コンストラクタ。
  const AccountTileConfiguration({
    required this.source,
    required this.login,
    required this.loggedOutSubtitle,
    required this.syncLabel,
    required this.syncSuccessNoun,
    required this.syncFailureMessage,
    required this.sessionExpiredMessage,
    required this.logoutMessage,
    this.syncSubtitle,
    this.syncAfterLogin = false,
    this.syncEnabled = true,
  });

  /// 対象サイト。
  final NovelSource source;

  /// サイト固有のログイン画面を開く処理。
  final AccountLoginAction login;

  /// 未ログイン時の説明。
  final String loggedOutSubtitle;

  /// 同期メニューのラベル。
  final String syncLabel;

  /// 同期メニューの補足。
  final String? syncSubtitle;

  /// 同期成功メッセージで件数の後ろに表示する対象名。
  final String syncSuccessNoun;

  /// 同期失敗時のメッセージ。
  final String syncFailureMessage;

  /// セッション失効時のメッセージ。
  final String sessionExpiredMessage;

  /// ログアウト完了時のメッセージ。
  final String logoutMessage;

  /// ログイン成功直後に同期するか。
  final bool syncAfterLogin;

  /// 同期操作を表示するか。
  final bool syncEnabled;
}

Future<bool?> _openNarouLogin(BuildContext context) async {
  await const LoginRoute().push<void>(context);
  return null;
}

Future<bool?> _openKakuyomuLogin(BuildContext context) =>
    const KakuyomuLoginRoute().push<bool>(context);

Future<bool?> _openAlphapolisLogin(BuildContext context) =>
    const AlphapolisLoginRoute().push<bool>(context);

Future<bool?> _openHamelnLogin(BuildContext context) =>
    const HamelnLoginRoute().push<bool>(context);

Future<bool?> _openEstarLogin(BuildContext context) =>
    const EstarLoginRoute().push<bool>(context);

Future<bool?> _openNovelupLogin(BuildContext context) =>
    const NovelupLoginRoute().push<bool>(context);

/// ログイン画面が実装済みのサイトに対するアカウントタイル設定。
const Map<NovelSource, AccountTileConfiguration> _accountTileConfigurations = {
  NovelSource.narou: AccountTileConfiguration(
    source: NovelSource.narou,
    login: _openNarouLogin,
    loggedOutSubtitle: '未ログイン・ブックマーク同期としおり連携',
    syncLabel: 'ブックマークを同期',
    syncSuccessNoun: '件のブックマーク',
    syncFailureMessage: '小説家になろうのブックマーク同期に失敗しました',
    sessionExpiredMessage: '小説家になろうのログイン期限が切れました。再ログインしてください',
    logoutMessage: '小説家になろうからログアウトしました',
  ),
  NovelSource.kakuyomu: AccountTileConfiguration(
    source: NovelSource.kakuyomu,
    login: _openKakuyomuLogin,
    loggedOutSubtitle: '未ログイン・公式ログイン画面を使用します',
    syncLabel: 'フォロー作品・閲覧履歴を同期',
    syncSubtitle: 'カクヨムでフォロー中の作品をNoveltyへ追加します',
    syncSuccessNoun: '件の作品',
    syncFailureMessage: 'カクヨム作品・閲覧履歴の同期に失敗しました',
    sessionExpiredMessage: 'カクヨムのログイン期限が切れました。再ログインしてください',
    logoutMessage: 'カクヨムからログアウトしました',
    syncAfterLogin: true,
  ),
  NovelSource.alphapolis: AccountTileConfiguration(
    source: NovelSource.alphapolis,
    login: _openAlphapolisLogin,
    loggedOutSubtitle: '未ログイン・フォーム認証',
    syncLabel: 'お気に入りを同期',
    syncSuccessNoun: '作品',
    syncFailureMessage: 'アルファポリスのお気に入り同期に失敗しました',
    sessionExpiredMessage: 'アルファポリスのログイン期限が切れました',
    logoutMessage: 'アルファポリスからログアウトしました',
  ),
  NovelSource.hameln: AccountTileConfiguration(
    source: NovelSource.hameln,
    login: _openHamelnLogin,
    loggedOutSubtitle: '未ログイン・フォーム認証',
    syncLabel: '同期未対応',
    syncSuccessNoun: '件',
    syncFailureMessage: 'ハーメルンの同期機能は未対応です',
    sessionExpiredMessage: 'ハーメルンのログイン期限が切れました',
    logoutMessage: 'ハーメルンからログアウトしました',
    syncEnabled: false,
  ),
  NovelSource.estar: AccountTileConfiguration(
    source: NovelSource.estar,
    login: _openEstarLogin,
    loggedOutSubtitle: '未ログイン・公式ログイン画面を使用します',
    syncLabel: '同期未対応',
    syncSuccessNoun: '件',
    syncFailureMessage: 'エブリスタの同期機能は未対応です',
    sessionExpiredMessage: 'エブリスタのログイン期限が切れました',
    logoutMessage: 'エブリスタからログアウトしました',
    syncEnabled: false,
  ),
  NovelSource.novelup: AccountTileConfiguration(
    source: NovelSource.novelup,
    login: _openNovelupLogin,
    loggedOutSubtitle: '未ログイン・フォーム認証',
    syncLabel: '同期未対応',
    syncSuccessNoun: '件',
    syncFailureMessage: 'ノベルアップ＋の同期機能は未対応です',
    sessionExpiredMessage: 'ノベルアップ＋のログイン期限が切れました',
    logoutMessage: 'ノベルアップ＋からログアウトしました',
    syncEnabled: false,
  ),
};

/// [source] に対応するログイン画面と表示設定を解決する。
///
/// ログイン画面が未実装のサイトでは `null` を返す。
AccountTileConfiguration? accountTileConfigurationFor(NovelSource source) =>
    _accountTileConfigurations[source];

/// サイト横断のアカウント連携タイル。
class AccountTile extends ConsumerWidget {
  /// コンストラクタ。
  const AccountTile({required this.configuration, super.key});

  /// サイト固有の表示・ログイン設定。
  final AccountTileConfiguration configuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = configuration.source;
    final authAsync = ref.watch(accountAuthStateProvider(source));
    return authAsync.when(
      data: (authState) {
        if (!authState.isLoggedIn) {
          return ListTile(
            leading: const Icon(Icons.login),
            title: Text(source.label),
            subtitle: Text(configuration.loggedOutSubtitle),
            trailing: const Text('ログイン'),
            onTap: () => _login(context, ref),
          );
        }

        return ExpansionTile(
          leading: const Icon(Icons.account_circle),
          title: Text(source.label),
          subtitle: Text(authState.displayName ?? 'ログイン済み'),
          children: [
            if (configuration.syncEnabled)
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(configuration.syncLabel),
                subtitle: configuration.syncSubtitle == null
                    ? null
                    : Text(configuration.syncSubtitle!),
                onTap: () => _sync(context, ref),
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () => _logout(context, ref),
            ),
          ],
        );
      },
      loading: () => ListTile(
        leading: const CircularProgressIndicator(),
        title: Text(source.label),
        subtitle: const Text('認証状態を確認中...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(source.label),
        subtitle: Text('認証状態を確認できませんでした: $error'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(accountAuthStateProvider(source)),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final success = await configuration.login(context);
    ref.invalidate(accountAuthStateProvider(configuration.source));
    if (success != true || !configuration.syncAfterLogin || !context.mounted) {
      return;
    }
    await _sync(context, ref);
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = configuration.source;
    final adapter = ref.read(accountSyncRegistryProvider)[source];
    if (adapter == null) return;

    try {
      final count = await adapter.pullLibrary();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$count ${configuration.syncSuccessNoun}を同期しました'),
        ),
      );
    } on AccountSessionExpiredException {
      try {
        await adapter.logout();
      } on Exception {
        // 認証情報の削除に失敗しても認証状態は再評価する。
      }
      ref.invalidate(accountAuthStateProvider(source));
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(configuration.sessionExpiredMessage)),
      );
    } on Exception {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(configuration.syncFailureMessage)),
      );
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final source = configuration.source;
    final adapter = ref.read(accountSyncRegistryProvider)[source];
    await adapter?.logout();
    ref.invalidate(accountAuthStateProvider(source));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(configuration.logoutMessage)),
    );
  }
}
