import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/novelup_auth_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/alphapolis/alphapolis_account_sync_adapter.dart';
import 'package:novelty/sites/hameln/hameln_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/sites/novelup/novelup_account_sync_adapter.dart';

class _RedirectAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '',
    302,
    headers: {
      'location': ['/account'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _MemoryRepository extends FormAuthSessionRepository {
  _MemoryRepository(NovelSource source)
    : _accountId = '${source.dbId}-user',
      super(source: source);

  String? _accountId;
  bool cleared = false;

  @override
  Future<String?> buildCookieHeader() async => 'opaque=session';

  // ハーメルンはCloudflare対策でHTTP確認ができず、保存済みCookieの内容で
  // ログイン状態を判定する。Secure Storageへ触れないようここで返す。
  @override
  Future<Map<String, String>> getCookies() async => const <String, String>{
    'sson': 'session',
  };

  @override
  Future<String?> getAccountId() async => _accountId;

  @override
  Future<void> clearAll() async {
    cleared = true;
    _accountId = null;
  }
}

void main() {
  final cases =
      <
        (
          NovelSource,
          AccountSyncAdapter Function(_MemoryRepository repository, Dio dio),
          bool supportsPullLibrary,
        )
      >[
        (
          NovelSource.alphapolis,
          (repository, dio) => AlphapolisAccountSyncAdapter(
            sessionRepository: repository,
            authService: AlphapolisAuthService(
              sessionRepository: repository,
              dio: dio,
            ),
            db: AppDatabase.memory(),
            dio: dio,
          ),
          true,
        ),
        (
          NovelSource.hameln,
          (repository, dio) => HamelnAccountSyncAdapter(
            sessionRepository: repository,
            authService: HamelnAuthService(
              sessionRepository: repository,
              dio: dio,
            ),
          ),
          false,
        ),
        (
          NovelSource.novelup,
          (repository, dio) => NovelupAccountSyncAdapter(
            sessionRepository: repository,
            authService: NovelupAuthService(
              sessionRepository: repository,
              dio: dio,
            ),
          ),
          false,
        ),
      ];

  for (final (source, createAdapter, supportsPullLibrary) in cases) {
    group('${source.name} AccountSyncAdapter', () {
      late _MemoryRepository repository;
      late AccountSyncAdapter adapter;

      setUp(() {
        repository = _MemoryRepository(source);
        final dio = Dio()..httpClientAdapter = _RedirectAdapter();
        adapter = createAdapter(repository, dio);
      });

      test('認証済み状態とアカウントIDを共通表現で返す', () async {
        final state = await adapter.getAuthState();

        expect(adapter.source, source);
        expect(state.source, source);
        expect(state.isLoggedIn, isTrue);
        expect(state.accountId, '${source.dbId}-user');
        expect(state.displayName, '${source.dbId}-user');
        expect(await adapter.isLoggedIn(), isTrue);
      });

      test('logoutで保存セッションを削除する', () async {
        await adapter.logout();

        expect(repository.cleared, isTrue);
      });

      test('未確認の同期メソッドはUnsupportedError', () async {
        if (!supportsPullLibrary) {
          await expectLater(adapter.pullLibrary(), throwsUnsupportedError);
        }
        await expectLater(
          adapter.addToRemoteLibrary('work'),
          throwsUnsupportedError,
        );
        await expectLater(
          adapter.removeFromRemoteLibrary('work'),
          throwsUnsupportedError,
        );
        await expectLater(
          adapter.pushReadingProgress(workId: 'work', episode: 1),
          throwsUnsupportedError,
        );
      });
    });
  }
}
