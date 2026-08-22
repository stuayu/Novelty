import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/router/router.dart';
import 'package:novelty/screens/kakuyomu_login_page.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/utils/settings_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// "もっと"ページ（設定ハブ）のウィジェット。
class MorePage extends ConsumerStatefulWidget {
  /// コンストラクタ
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: SvgPicture.asset(
                    'assets/app_icon/base.svg',
                    width: 120,
                    height: 120,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildQuickActions(settingsAsync),
              const Divider(),
              _buildAccountSection(),
              const Divider(),
              _buildFeaturesSection(),
              const Divider(),
              _buildSettingsSection(),
              const Divider(),
              _buildAppInfoSection(),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(AsyncValue<AppSettings> settingsAsync) {
    return Column(
      children: [
        settingsAsync.when(
          data: (settings) => SwitchListTile(
            secondary: const Icon(Icons.cloud_off),
            title: const Text('オフラインモード'),
            subtitle: const Text('通信を行わず、保存済みのコンテンツのみ利用します'),
            value: settings.isOfflineMode,
            onChanged: (value) async {
              await ref
                  .read(settingsProvider.notifier)
                  .setIsOfflineMode(isOfflineMode: value);
            },
          ),
          loading: () => const ListTile(
            leading: CircularProgressIndicator(),
            title: Text('読み込み中...'),
          ),
          error: (err, stack) => ListTile(title: Text('Error: $err')),
        ),
        settingsAsync.when(
          data: (settings) => SwitchListTile(
            secondary: const Icon(Icons.visibility_off),
            title: const Text('シークレットモード'),
            subtitle: const Text('閲覧履歴の記録を一時停止します'),
            value: settings.isIncognito,
            onChanged: (value) async {
              await ref
                  .read(settingsProvider.notifier)
                  .setIsIncognito(isIncognito: value);
            },
          ),
          loading: () => const ListTile(
            leading: CircularProgressIndicator(),
            title: Text('読み込み中...'),
          ),
          error: (err, stack) => ListTile(title: Text('Error: $err')),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('アカウント'),
        _buildNarouAccountSection(),
        const Divider(indent: 56),
        _buildKakuyomuAccountSection(),
      ],
    );
  }

  Widget _buildNarouAccountSection() {
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
                await ref.read(authProvider.notifier).logout();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ログアウトしました')),
                  );
                }
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
      error: (e, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('小説家になろう'),
        subtitle: Text('認証状態を確認できませんでした: $e'),
      ),
    );
  }

  Widget _buildKakuyomuAccountSection() {
    final sessionAsync = ref.watch(kakuyomuSessionValidProvider);
    return sessionAsync.when(
      data: (isLoggedIn) {
        if (!isLoggedIn) {
          return ListTile(
            leading: const Icon(Icons.login),
            title: const Text('カクヨム'),
            subtitle: const Text('未ログイン・公式ログイン画面を使用します'),
            trailing: const Text('ログイン'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final success = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (context) => const KakuyomuLoginPage(),
                ),
              );
              ref.invalidate(kakuyomuSessionValidProvider);
              if (success == true && mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('カクヨムにログインしました')),
                );
              }
            },
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
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final count = await ref
                      .read(kakuyomuAccountSyncAdapterProvider)
                      .pullLibrary();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('$count 件のフォロー作品を追加しました')),
                  );
                } on Exception {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('フォロー作品の同期に失敗しました')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(kakuyomuAuthServiceProvider).logout();
                ref.invalidate(kakuyomuSessionValidProvider);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('カクヨムからログアウトしました')),
                  );
                }
              },
            ),
          ],
        );
      },
      loading: () => const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('カクヨム'),
        subtitle: Text('認証状態を確認中...'),
      ),
      error: (e, _) => ListTile(
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

  Widget _buildFeaturesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('機能'),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('ダウンロードキュー'),
          onTap: () => const DownloadsRoute().go(context),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('設定'),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('一般設定'),
          onTap: () => const AppearanceSettingsRoute().go(context),
        ),
        ListTile(
          leading: const Icon(Icons.chrome_reader_mode_outlined),
          title: const Text('閲覧設定'),
          onTap: () => const ReaderSettingsRoute().go(context),
        ),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('データとストレージ'),
          onTap: () => const DataStorageRoute().go(context),
        ),
      ],
    );
  }

  Widget _buildAppInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('アプリ情報'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('アプリについて'),
          onTap: () => const AboutRoute().go(context),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('ヘルプ'),
          onTap: () async {
            const url = 'https://novelty.l4ph.moe/help';
            if (!await launchUrl(Uri.parse(url))) {
              throw Exception('Could not launch $url');
            }
          },
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
