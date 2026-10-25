import 'dart:async';
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
    '<html><body>マイページ</body></html>',
    200,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', status);

  @override
  void close({bool force = false}) {}
}

class _DelayedAuthCheckAdapter implements HttpClientAdapter {
  final requestStarted = Completer<void>();
  final releaseResponse = Completer<void>();
  final cookieHeaders = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cookieHeaders.add(options.headers['Cookie'] as String?);
    if (cookieHeaders.length == 1) {
      requestStarted.complete();
      await releaseResponse.future;
    }
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['/mypage'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryRepository extends FormAuthSessionRepository {
  _MemoryRepository(NovelSource source)
    : _accountId = '${source.dbId}-user',
      super(source: source) {
    if (source == NovelSource.hameln) _cookieHeader = 'sson=session';
  }

  String? _accountId;
  String _cookieHeader = 'opaque=session';
  int _generation = 0;
  bool cleared = false;

  @override
  Future<String?> buildCookieHeader() async => _cookieHeader;

  @override
  Future<FormAuthSessionSnapshot?> getSessionSnapshot() async {
    final accountId = _accountId;
    if (accountId == null) return null;
    return FormAuthSessionSnapshot(
      accountId: accountId,
      cookieHeader: _cookieHeader,
      generation: _generation,
    );
  }

  // ハーメルンはCloudflare対策でHTTP確認ができず、保存済みCookieの内容で
  // ログイン状態を判定する。Secure Storageへ触れないようここで返す。
  @override
  Future<Map<String, String>> getCookies() async => const <String, String>{
    'sson': 'session',
  };

  @override
  Future<String?> getAccountId() async => _accountId;

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    _accountId = accountId;
    _cookieHeader = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    _generation++;
  }

  @override
  Future<void> clearAll() async {
    cleared = true;
    _accountId = null;
    _cookieHeader = '';
    _generation++;
  }

  @override
  Future<bool> clearAllIfSessionCookieHeaderAndGenerationMatches(
    int expectedGeneration,
    String expectedCookieHeader,
  ) async {
    final current = await getSessionSnapshot();
    if (current == null ||
        current.generation != expectedGeneration ||
        current.cookieHeader != expectedCookieHeader) {
      return false;
    }
    await clearAll();
    return true;
  }
}

void main() {
  test('一時的な通信障害ではフォーム認証Cookieを保持して未確認状態にする', () async {
    final repository = _MemoryRepository(NovelSource.alphapolis);
    final dio = Dio()..httpClientAdapter = _StatusAdapter(503);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final adapter = AlphapolisAccountSyncAdapter(
      sessionRepository: repository,
      authService: AlphapolisAuthService(
        sessionRepository: repository,
        dio: dio,
      ),
      db: db,
      dio: dio,
    );

    final state = await adapter.getAuthState();

    expect(state.hasSession, isTrue);
    expect(state.isLoggedIn, isFalse);
    expect(state.isVerified, isFalse);
    expect(state.accountId, 'alphapolis-user');
    expect(repository.cleared, isFalse);
  });

  test('検証中に再ログインしたら新しいCookieとアカウントで再検証する', () async {
    final repository = _MemoryRepository(NovelSource.alphapolis);
    final httpAdapter = _DelayedAuthCheckAdapter();
    final dio = Dio()..httpClientAdapter = httpAdapter;
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final adapter = AlphapolisAccountSyncAdapter(
      sessionRepository: repository,
      authService: AlphapolisAuthService(
        sessionRepository: repository,
        dio: dio,
      ),
      db: db,
      dio: dio,
    );

    final stateFuture = adapter.getAuthState();
    await httpAdapter.requestStarted.future;
    await repository.saveSession(
      accountId: 'new-reader',
      cookies: const {'session': 'new-cookie'},
    );
    httpAdapter.releaseResponse.complete();
    final state = await stateFuture;

    expect(httpAdapter.cookieHeaders, ['opaque=session', 'session=new-cookie']);
    expect(state.isLoggedIn, isTrue);
    expect(state.accountId, 'new-reader');
  });

  test('認証切れを確認したら同じ世代のCookieだけを削除する', () async {
    final repository = _MemoryRepository(NovelSource.alphapolis);
    final dio = Dio()..httpClientAdapter = _StatusAdapter(401);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final adapter = AlphapolisAccountSyncAdapter(
      sessionRepository: repository,
      authService: AlphapolisAuthService(
        sessionRepository: repository,
        dio: dio,
      ),
      db: db,
      dio: dio,
    );

    final state = await adapter.getAuthState();

    expect(state.isLoggedIn, isFalse);
    expect(state.hasSession, isFalse);
    expect(repository.cleared, isTrue);
  });

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
