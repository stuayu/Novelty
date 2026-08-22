import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// サイトごとのアカウント同期アダプターを提供するレジストリ。
///
/// 対応していないサイトは Map に登録しない。呼び出し側は `registry[source]`
/// が null の場合、同期機能なしとしてローカル処理だけを継続する。
final accountSyncRegistryProvider =
    Provider<Map<NovelSource, AccountSyncAdapter>>(
      (ref) => <NovelSource, AccountSyncAdapter>{
        NovelSource.narou: NarouAccountSyncAdapter(
          syncService: ref.watch(narouSyncServiceProvider),
          db: ref.watch(appDatabaseProvider),
        ),
        NovelSource.kakuyomu: ref.watch(kakuyomuAccountSyncAdapterProvider),
      },
    );
