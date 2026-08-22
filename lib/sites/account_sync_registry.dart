import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/kakuyomu_webview_support.dart';

/// サイトごとのアカウント同期アダプターを提供するレジストリ。
///
/// 対応していないサイトは Map に登録しない。呼び出し側は `registry[source]`
/// が null の場合、同期機能なしとしてローカル処理だけを継続する。
final accountSyncRegistryProvider = Provider<Map<NovelSource, AccountSyncAdapter>>(
  (ref) {
    final adapters = <NovelSource, AccountSyncAdapter>{
      NovelSource.narou: NarouAccountSyncAdapter(
        syncService: ref.watch(narouSyncServiceProvider),
        db: ref.watch(appDatabaseProvider),
      ),
    };

    // Phase 4 のリモート操作は Headless WebView を使用する。
    // 未対応OSでは従来どおりローカル操作だけを許可する。
    if (isKakuyomuWebViewSupported) {
      adapters[NovelSource.kakuyomu] = ref.watch(
        kakuyomuAccountSyncAdapterProvider,
      );
    }

    return adapters;
  },
);
