import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/services/novelup_auth_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/alphapolis/alphapolis_account_sync_adapter.dart';
import 'package:novelty/sites/hameln/hameln_account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/sites/novelup/novelup_account_sync_adapter.dart';

/// なろうのアカウント同期アダプター。
final narouAccountSyncAdapterProvider = Provider<NarouAccountSyncAdapter>(
  (ref) => NarouAccountSyncAdapter(
    syncService: ref.watch(narouSyncServiceProvider),
    db: ref.watch(appDatabaseProvider),
    authRepository: ref.watch(authRepositoryProvider),
    authService: ref.watch(narouAuthServiceProvider),
  ),
);

/// アルファポリスのアカウント同期アダプター。
final alphapolisAccountSyncAdapterProvider =
    Provider<AlphapolisAccountSyncAdapter>(
      (ref) => AlphapolisAccountSyncAdapter(
        sessionRepository: ref.watch(
          formAuthSessionRepositoryProvider(NovelSource.alphapolis),
        ),
        authService: ref.watch(alphapolisAuthServiceProvider),
      ),
    );

/// ハーメルンのアカウント同期アダプター。
final hamelnAccountSyncAdapterProvider = Provider<HamelnAccountSyncAdapter>(
  (ref) => HamelnAccountSyncAdapter(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.hameln),
    ),
    authService: ref.watch(hamelnAuthServiceProvider),
  ),
);

/// ノベルアップ＋のアカウント同期アダプター。
final novelupAccountSyncAdapterProvider = Provider<NovelupAccountSyncAdapter>(
  (ref) => NovelupAccountSyncAdapter(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.novelup),
    ),
    authService: ref.watch(novelupAuthServiceProvider),
  ),
);

/// サイトごとのアカウント同期アダプターを提供するレジストリ。
///
/// 対応していないサイトは Map に登録しない。呼び出し側は `registry[source]`
/// が null の場合、同期機能なしとしてローカル処理だけを継続する。
final accountSyncRegistryProvider =
    Provider<Map<NovelSource, AccountSyncAdapter>>(
      (ref) => <NovelSource, AccountSyncAdapter>{
        NovelSource.narou: ref.watch(narouAccountSyncAdapterProvider),
        NovelSource.kakuyomu: ref.watch(kakuyomuAccountSyncAdapterProvider),
        NovelSource.alphapolis: ref.watch(
          alphapolisAccountSyncAdapterProvider,
        ),
        NovelSource.hameln: ref.watch(hamelnAccountSyncAdapterProvider),
        NovelSource.novelup: ref.watch(novelupAccountSyncAdapterProvider),
      },
    );
