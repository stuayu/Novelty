import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_auth_diagnostics.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novel_source.dart';

import 'narou_sync_service_test.mocks.dart';

class _TestAppDatabase extends MockAppDatabase {
  @override
  Future<T> transaction<T>(
    Future<T> Function()? action, {
    bool? requireNew = false,
  }) async => action!();
}

class _TestAuthRepository extends MockAuthRepository {
  @override
  Future<bool> runIfSessionSnapshotMatches(
    AuthSessionSnapshot? snapshot,
    Future<void> Function()? operation,
  ) async {
    if (snapshot == null || operation == null) return false;
    final current = await getSessionSnapshot();
    if (current == null ||
        current.generation != snapshot.generation ||
        current.narouid != snapshot.narouid) {
      return false;
    }
    await operation();
    return true;
  }
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _DelayedSetCookieAdapter implements HttpClientAdapter {
  final requestStarted = Completer<void>();
  final releaseResponse = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestStarted.complete();
    await releaseResponse.future;
    return ResponseBody.fromString(
      '<html></html>',
      200,
      headers: <String, List<String>>{
        'set-cookie': ['ses=old-session-rotated; Path=/; Secure'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DelayedBookmarkPageAdapter implements HttpClientAdapter {
  _DelayedBookmarkPageAdapter(this.body);

  final String body;
  final requestStarted = Completer<void>();
  final releaseResponse = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestStarted.complete();
    await releaseResponse.future;
    return ResponseBody.fromString(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

/// テスト用のフェイクHTTPアダプタ。
///
/// 実際のネットワーク通信を行わず、URLに応じたレスポンスを返す。
/// 送信されたリクエストは[requests]に記録され、テストから検証できる。
class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

@GenerateMocks([AuthRepository, AppDatabase, ApiService])
void main() {
  group('NarouSyncService', () {
    late _TestAuthRepository mockAuthRepository;
    late MockAppDatabase mockDatabase;
    late MockApiService mockApiService;
    late NarouSyncService syncService;

    setUp(() {
      mockAuthRepository = _TestAuthRepository();
      mockDatabase = _TestAppDatabase();
      mockApiService = MockApiService();
      when(
        mockAuthRepository.getSessionSnapshot(),
      ).thenAnswer((_) async {
        final cookieHeader = await mockAuthRepository.buildCookieHeader();
        if (cookieHeader == null) return null;
        return AuthSessionSnapshot(
          narouid: 'test-reader',
          username: 'テスト読者',
          cookieHeader: cookieHeader,
          generation: 1,
        );
      });
      syncService = NarouSyncService(
        authRepository: mockAuthRepository,
        db: mockDatabase,
        apiService: mockApiService,
      );
    });

    test('別アカウントへ切り替えた後に届いた旧応答のCookieを適用しない', () async {
      final repository = AuthRepository(storage: _MemorySecureStorage());
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      final adapter = _DelayedSetCookieAdapter();
      final service = NarouSyncService(
        authRepository: repository,
        db: mockDatabase,
        apiService: mockApiService,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final sync = service.syncBookmarksFromNarou();
      await adapter.requestStarted.future;
      await repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );
      adapter.releaseResponse.complete();
      await sync;

      expect(await repository.getNarouid(), 'new-reader');
      expect(await repository.getSessionCookies(), {
        'ks2': 'new-ks2',
        'ses': 'new-ses',
        'userl': 'new-userl',
      });
    });

    group('syncBookmarksFromNarou', () {
      test('メタデータ取得失敗は同期結果を保ち安全なTrace診断を残す', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'ks2-token',
          ses: 'ses-token',
          userl: 'userl-token',
          rememberSession: true,
        );
        const bookmarkHtml = '''
<li class="p-up-bookmark-item">
  <span class="p-up-bookmark-item__title">
    <a href="https://ncode.syosetu.com/n0156ia/">Title</a>
  </span>
</li>
''';
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(bookmarkHtml, 200),
        );
        final request = RequestOptions(
          path: 'https://api.syosetu.com/novelapi/api/',
        );
        when(mockApiService.fetchMultipleNovelsInfo(any)).thenThrow(
          DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response<String>(
              requestOptions: request,
              statusCode: 503,
              data: 'private response body',
            ),
          ),
        );
        when(mockDatabase.ensureNovelExists(any, any)).thenAnswer((_) async {});
        when(mockDatabase.addToLibrary(any, any)).thenAnswer((_) async => 1);
        when(
          mockDatabase.markNarouBookmarkSynced(any, any),
        ).thenAnswer((_) async {});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'novelty-narou-sync-test-',
        );
        addTearDown(() => tempDirectory.delete(recursive: true));
        final diagnosticLines = <String>[];
        final diagnostics = AppDiagnosticsLogger(
          enabled: true,
          directoryResolver: () async => tempDirectory,
          consoleSink: diagnosticLines.add,
        );
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          diagnostics: diagnostics,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final synced = await service.syncBookmarksFromNarou();
        await diagnostics.flush();

        expect(synced, ['n0156ia']);
        expect(diagnosticLines, hasLength(1));
        expect(
          diagnosticLines.single,
          contains('library-sync.metadata.failed.trace'),
        );
        expect(diagnosticLines.single, contains('"httpStatusCode":503'));
        expect(
          diagnosticLines.single,
          contains('api.syosetu.com/novelapi/api/'),
        );
        expect(
          diagnosticLines.single,
          isNot(contains('private response body')),
        );
      });

      test('ブックマークHTTP失敗は本文を含めず安全な診断情報を保持する', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'ks2-token',
          ses: 'ses-token',
          userl: 'userl-token',
          rememberSession: true,
        );
        const responseBody = 'service unavailable';
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(
            responseBody,
            503,
            headers: <String, List<String>>{
              'content-type': ['text/html; charset=utf-8'],
            },
          ),
        );
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        Object? failure;
        try {
          await service.syncBookmarksFromNarou();
          fail('HTTP 503なら同期が失敗する必要があります');
        } on NarouBookmarkFetchException catch (error) {
          failure = error;
        }

        expect(failure, isA<SiteDiagnosticException>());
        final details =
            (failure as SiteDiagnosticException).safeDiagnosticFields;
        expect(details['httpStatusCode'], 503);
        expect(details['requestMethod'], 'GET');
        expect(
          details['requestRoute'],
          'syosetu.com/favnovelmain/list/',
        );
        expect(details['contentType'], 'text/html');
        expect(details['responseBytes'], responseBody.length);
        expect(details.keys, isNot(contains('responseBody')));
      });

      test('HTTP 200でも本文が空なら空一覧の同期成功として扱わない', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'ks2-token',
          ses: 'ses-token',
          userl: 'userl-token',
          rememberSession: true,
        );
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('', 200),
        );
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        Object? failure;
        try {
          await service.syncBookmarksFromNarou();
          fail('本文のないHTTP 200応答なら同期が失敗する必要があります');
        } on NarouBookmarkFetchException catch (error) {
          failure = error;
        }

        expect(failure, isA<SiteDiagnosticException>());
        final details =
            (failure as SiteDiagnosticException).safeDiagnosticFields;
        expect(details['httpStatusCode'], 200);
        expect(details['responseBytes'], 0);
        expect(details['responseBodyEmpty'], isTrue);
      });

      test('同期中に同じセッションのCookieが更新されたら次ページへ反映する', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'ks2-old',
          ses: 'ses-old',
          userl: 'userl-old',
          rememberSession: true,
        );
        final firstPageEntries = List.generate(50, (index) {
          final ncode = 'n${(index + 1).toString().padLeft(4, '0')}aa';
          return '<li class="p-up-bookmark-item"><span '
              'class="p-up-bookmark-item__title"><a '
              'href="https://ncode.syosetu.com/$ncode/">作品</a></span></li>';
        }).join();
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.queryParameters['p'] == '2') {
            return ResponseBody.fromString('<html></html>', 200);
          }
          return ResponseBody.fromString(
            firstPageEntries,
            200,
            headers: <String, List<String>>{
              'set-cookie': ['ses=ses-rotated; Path=/; Secure'],
            },
          );
        });
        when(mockDatabase.ensureNovelExists(any, any)).thenAnswer((_) async {});
        when(mockDatabase.addToLibrary(any, any)).thenAnswer((_) async => 1);
        when(
          mockDatabase.markNarouBookmarkSynced(any, any),
        ).thenAnswer((_) async {});
        when(
          mockApiService.fetchMultipleNovelsInfo(any),
        ).thenAnswer((_) async => {});
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await service.syncBookmarksFromNarou();

        expect(fakeAdapter.requests, hasLength(2));
        expect(
          fakeAdapter.requests.map((request) => request.headers['Cookie']),
          [
            'ks2=ks2-old; ses=ses-old; userl=userl-old',
            'ks2=ks2-old; ses=ses-rotated; userl=userl-old',
          ],
        );
      });

      test('同期中にCookieが削除されたら認証切れとして返す', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'ks2-token',
          ses: 'ses-token',
          userl: 'userl-token',
          rememberSession: true,
        );
        final firstPageEntries = List.generate(50, (index) {
          final ncode = 'n${(index + 1).toString().padLeft(4, '0')}aa';
          return '<li class="p-up-bookmark-item"><span '
              'class="p-up-bookmark-item__title"><a '
              'href="https://ncode.syosetu.com/$ncode/">作品</a></span></li>';
        }).join();
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(
            firstPageEntries,
            200,
            headers: <String, List<String>>{
              'set-cookie': ['ses=; Max-Age=0; Path=/; Secure'],
            },
          ),
        );
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );
        final accountAdapter = NarouAccountSyncAdapter(
          syncService: service,
          db: mockDatabase,
          authRepository: repository,
        );

        await expectLater(
          accountAdapter.pullLibrary(),
          throwsA(isA<AccountSessionExpiredException>()),
        );

        expect(fakeAdapter.requests, hasLength(1));
        expect(await repository.getSessionSnapshot(), isNull);
        verifyNever(mockDatabase.addToLibrary(any, any));
      });

      test('ページ取得中に別アカウントへ切り替わったら次ページを送らない', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'old-reader',
          username: '旧利用者',
          ks2: 'old-ks2',
          ses: 'old-ses',
          userl: 'old-userl',
          rememberSession: true,
        );
        final firstPageEntries = List.generate(50, (index) {
          final ncode = 'n${(index + 1).toString().padLeft(4, '0')}aa';
          return '<li class="p-up-bookmark-item"><span '
              'class="p-up-bookmark-item__title"><a '
              'href="https://ncode.syosetu.com/$ncode/">作品</a></span></li>';
        }).join();
        late Future<void> newLogin;
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          newLogin = repository.saveSession(
            narouid: 'new-reader',
            username: '新利用者',
            ks2: 'new-ks2',
            ses: 'new-ses',
            userl: 'new-userl',
            rememberSession: true,
          );
          return options.uri.queryParameters['p'] == '2'
              ? ResponseBody.fromString('<html></html>', 200)
              : ResponseBody.fromString(firstPageEntries, 200);
        });
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await expectLater(
          service.syncBookmarksFromNarou(),
          throwsA(isA<NarouBookmarkFetchException>()),
        );
        await newLogin;

        expect(fakeAdapter.requests, hasLength(1));
        expect(await repository.getNarouid(), 'new-reader');
      });

      test('最終ページの応答後に別アカウントへ切り替わったらDBへ反映しない', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'old-reader',
          username: '旧利用者',
          ks2: 'old-ks2',
          ses: 'old-ses',
          userl: 'old-userl',
          rememberSession: true,
        );
        const bookmarkHtml = '''
<li class="p-up-bookmark-item">
  <span class="p-up-bookmark-item__title">
    <a href="https://ncode.syosetu.com/n0156ia/">Title</a>
  </span>
  <a href="https://ncode.syosetu.com/n0156ia/3/" class="c-button--outline">ep.3</a>
</li>
''';
        final fakeAdapter = _DelayedBookmarkPageAdapter(bookmarkHtml);
        final database = MockAppDatabase();
        when(database.ensureNovelExists(any, any)).thenAnswer((_) async {});
        when(database.addToLibrary(any, any)).thenAnswer((_) async => 1);
        when(
          database.markNarouBookmarkSynced(any, any),
        ).thenAnswer((_) async {});
        final api = MockApiService();
        when(api.fetchMultipleNovelsInfo(any)).thenAnswer((_) async => {});
        final service = NarouSyncService(
          authRepository: repository,
          db: database,
          apiService: api,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final sync = service.syncBookmarksFromNarou();
        await fakeAdapter.requestStarted.future;
        await repository.saveSession(
          narouid: 'new-reader',
          username: '新利用者',
          ks2: 'new-ks2',
          ses: 'new-ses',
          userl: 'new-userl',
          rememberSession: true,
        );
        fakeAdapter.releaseResponse.complete();

        await expectLater(sync, throwsA(isA<NarouBookmarkFetchException>()));

        verifyNever(database.ensureNovelExists(any, any));
        verifyNever(database.addToLibrary(any, any));
        verifyNever(database.markNarouBookmarkSynced(any, any));
        verifyNever(api.fetchMultipleNovelsInfo(any));
      });

      test('完全なログイン状態スナップショットがない場合はCookieだけで同期しない', () async {
        when(
          mockAuthRepository.getSessionSnapshot(),
        ).thenAnswer((_) async => null);
        when(mockAuthRepository.buildCookieHeader()).thenAnswer(
          (_) async => 'ks2=legacy; ses=session; userl=user',
        );
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        expect(await service.syncBookmarksFromNarou(), isEmpty);

        expect(fakeAdapter.requests, isEmpty);
        verifyNever(mockDatabase.addToLibrary(any, any));
      });

      test('失効応答のSet-Cookieで古いセッションCookieを置き換えない', () async {
        const originalCookie = 'ks2=old-ks2; ses=old-ses; userl=old-userl';
        const loginForm = '<form action="/login/login/"><input></form>';
        final responses = [
          (
            '',
            302,
            <String, List<String>>{
              'location': ['/login/input/'],
            },
          ),
          (loginForm, 200, <String, List<String>>{}),
          ('Unauthorized', 401, <String, List<String>>{}),
        ];

        for (final (body, status, extraHeaders) in responses) {
          final repository = AuthRepository(storage: _MemorySecureStorage());
          await repository.saveSession(
            narouid: 'reader-id',
            username: '読者',
            ks2: 'old-ks2',
            ses: 'old-ses',
            userl: 'old-userl',
            rememberSession: true,
          );
          final fakeAdapter = _FakeHttpClientAdapter(
            (_) => ResponseBody.fromString(
              body,
              status,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
                ...extraHeaders,
                'set-cookie': ['ses=anonymous; Path=/; Secure'],
              },
            ),
          );
          final service = NarouSyncService(
            authRepository: repository,
            db: mockDatabase,
            apiService: mockApiService,
            dio: Dio()..httpClientAdapter = fakeAdapter,
          );
          final accountAdapter = NarouAccountSyncAdapter(
            syncService: service,
            db: mockDatabase,
            authRepository: repository,
          );

          await expectLater(
            accountAdapter.pullLibrary(),
            throwsA(isA<AccountSessionExpiredException>()),
          );

          expect(
            fakeAdapter.requests.single.headers['Cookie'],
            originalCookie,
          );
          expect(await repository.getSessionSnapshot(), isNull);
          expect(fakeAdapter.requests, hasLength(1));
        }
      });

      test('content-typeがないログインフォーム応答のCookieを保存しない', () async {
        final repository = AuthRepository(storage: _MemorySecureStorage());
        await repository.saveSession(
          narouid: 'reader-id',
          username: '読者',
          ks2: 'old-ks2',
          ses: 'old-ses',
          userl: 'old-userl',
          rememberSession: true,
        );
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(
            '<form action="/login/login/"><input></form>',
            200,
            headers: {
              'set-cookie': ['ses=anonymous; Path=/; Secure'],
            },
          ),
        );
        final service = NarouSyncService(
          authRepository: repository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await expectLater(
          service.syncBookmarksFromNarou(),
          throwsA(isA<NarouSessionExpiredException>()),
        );

        expect(
          (await repository.getSessionSnapshot())?.cookieHeader,
          'ks2=old-ks2; ses=old-ses; userl=old-userl',
        );
      });

      test('セッションCookieがない場合は空リストを返す', () async {
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => null);

        final result = await syncService.syncBookmarksFromNarou();
        expect(result, isEmpty);
        verifyNever(mockDatabase.addToLibrary(any, any));
      });

      test('なろうへの同期応答で更新されたセッションCookieを保存する', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(
            '<html></html>',
            200,
            headers: <String, List<String>>{
              'set-cookie': ['ks2=rotated; Path=/; Secure'],
            },
          ),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=old; ses=session; userl=user');
        when(
          mockAuthRepository.updateSessionCookieHeaders(
            any,
            expectedCookieHeader: anyNamed('expectedCookieHeader'),
          ),
        ).thenAnswer((_) async {});
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        expect(await service.syncBookmarksFromNarou(), isEmpty);

        verify(
          mockAuthRepository.updateSessionCookieHeaders([
            'ks2=rotated; Path=/; Secure',
          ], expectedCookieHeader: 'ks2=old; ses=session; userl=user'),
        ).called(1);
      });

      test('共有DioへCookie更新インターセプターを一度だけ登録する', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString(
            '<html></html>',
            200,
            headers: <String, List<String>>{
              'set-cookie': ['ses=rotated; Path=/; Secure'],
            },
          ),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=old; ses=session; userl=user');
        when(
          mockAuthRepository.updateSessionCookieHeaders(
            any,
            expectedCookieHeader: anyNamed('expectedCookieHeader'),
          ),
        ).thenAnswer((_) async {});
        final sharedDio = Dio()..httpClientAdapter = fakeAdapter;
        NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: sharedDio,
        );
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: sharedDio,
        );

        await service.syncBookmarksFromNarou();

        verify(
          mockAuthRepository.updateSessionCookieHeaders(
            ['ses=rotated; Path=/; Secure'],
            expectedCookieHeader: 'ks2=old; ses=session; userl=user',
          ),
        ).called(1);
      });

      test('ブックマーク一覧を解析しライブラリに追加・同期済みにする', () async {
        const listPageHtml = '''
<li class="p-up-bookmark-item">
  <span class="p-up-bookmark-item__title">
    <a href="https://ncode.syosetu.com/n0156ia/">Title</a>
  </span>
  <a href="https://ncode.syosetu.com/n0156ia/3/" class="p-up-bookmark-item__button c-button--outline">ep.3</a>
</li>
''';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://syosetu.com/favnovelmain/list/') {
            return ResponseBody.fromString(listPageHtml, 200);
          }
          // 2ページ目は空にしてページネーションを止める
          return ResponseBody.fromString('<html></html>', 200);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.ensureNovelExists(any, any)).thenAnswer((_) async {});
        when(mockDatabase.addToLibrary(any, any)).thenAnswer((_) async => 1);
        when(
          mockDatabase.markNarouBookmarkSynced(any, any),
        ).thenAnswer((_) async {});
        when(
          mockDatabase.getReadingHistoryEntry(any, any),
        ).thenAnswer((_) async => null);
        when(mockDatabase.addToHistory(any)).thenAnswer((_) async => 1);
        when(
          mockApiService.fetchMultipleNovelsInfo(any),
        ).thenAnswer((_) async => {});
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.syncBookmarksFromNarou();

        expect(result, equals(['n0156ia']));
        verify(
          mockDatabase.ensureNovelExists(NovelSource.narou, 'n0156ia'),
        ).called(1);
        verify(
          mockDatabase.addToLibrary(NovelSource.narou, 'n0156ia'),
        ).called(1);
        verify(
          mockDatabase.markNarouBookmarkSynced(NovelSource.narou, 'n0156ia'),
        ).called(1);
      });

      test('セッション切れのログインredirectを0件の同期成功として返さない', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['/login/input/'],
            },
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await expectLater(
          service.syncBookmarksFromNarou(),
          throwsA(isA<Exception>()),
        );
        verifyNever(mockDatabase.addToLibrary(any, any));
      });

      test('セッション失効をアカウント同期の例外として返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['/login/input/'],
            },
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(
          mockAuthRepository.clearAllIfSessionCookieHeaderAndGenerationMatches(
            1,
            'ks2=x; ses=y; userl=z',
          ),
        ).thenAnswer((_) async => true);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );
        final accountSync = NarouAccountSyncAdapter(
          syncService: service,
          db: mockDatabase,
        );

        await expectLater(
          accountSync.pullLibrary(),
          throwsA(isA<AccountSessionExpiredException>()),
        );
      });

      test('ブックマーク取得失敗はExceptionとして呼び出し元へ返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('unavailable', 503),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await expectLater(
          service.syncBookmarksFromNarou(),
          throwsA(isA<Exception>()),
        );
      });

      test('一覧の同一origin redirectは安全に追跡する', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.path == '/favnovelmain/list/' &&
              options.uri.queryParameters.isEmpty) {
            return ResponseBody.fromString(
              '',
              302,
              headers: <String, List<String>>{
                'location': ['/favnovelmain/list/?canonical=1'],
              },
            );
          }
          return ResponseBody.fromString('<html></html>', 200);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.syncBookmarksFromNarou();

        expect(result, isEmpty);
        expect(fakeAdapter.requests, hasLength(2));
        expect(fakeAdapter.requests.last.uri.queryParameters['canonical'], '1');
        expect(
          fakeAdapter.requests.every(
            (request) => request.headers['Cookie'] == 'ks2=x; ses=y; userl=z',
          ),
          isTrue,
        );
      });

      test('一覧の外部origin redirect先へCookieを送らない', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['https://attacker.example/collect'],
            },
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await expectLater(
          service.syncBookmarksFromNarou(),
          throwsA(isA<Exception>()),
        );

        expect(fakeAdapter.requests, hasLength(1));
        expect(fakeAdapter.requests.single.uri.host, 'syosetu.com');
      });
    });

    group('addBookmarkToNarou', () {
      test('セッションCookieがない場合はnotLoggedInを返す', () async {
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => null);

        final result = await syncService.addBookmarkToNarou('n0156ia');
        expect(result.outcome, NarouBookmarkSyncOutcome.notLoggedIn);
      });

      test('正常系: addajax→updateajaxが成功しsuccessを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          if (url.startsWith('https://syosetu.com/favnovelmain/addajax/')) {
            return ResponseBody.fromString(
              'result({"useridfavncode":"12345",'
              '"favnovelmain_addend_token":"abcxyz","result":true})',
              200,
            );
          }
          if (url.startsWith('https://syosetu.com/favnovelmain/updateajax/')) {
            return ResponseBody.fromString('result({})', 200);
          }
          return ResponseBody.fromString('', 404);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        expect(result.useridFavncode, '12345');
        expect(result.token, 'abcxyz');
        expect(
          fakeAdapter.requests.every((request) => !request.followRedirects),
          isTrue,
        );
        final addRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString().startsWith(
            'https://syosetu.com/favnovelmain/addajax/',
          ),
        );
        // なろう本家のJSはJSONP形式（callback・キャッシュバスター付き）で
        // addajaxを呼び出しているため、同じ形式に合わせる必要がある。
        expect(addRequest.uri.queryParameters['callback'], isNotNull);
        expect(addRequest.uri.queryParameters['_'], isNotNull);
        final updateRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString().contains('updateajax'),
        );
        expect(updateRequest.uri.queryParameters['useridfavncode'], '12345');
        expect(updateRequest.uri.queryParameters['token'], 'abcxyz');
      });

      test('実際のなろうaddajaxレスポンス（JSONP・入れ子構造）を正しく解析できる', () async {
        // 実機で取得した本物のaddajaxレスポンス（個人を特定する認証情報は
        // 含まれていない）。ネストしたnovelmain/favnovelcategoryを含む
        // 複雑な構造でも、目的のフィールドだけを正しく抽出できることを確認する。
        const realAddajaxResponse = '''
jQuery112409311262883829196_1783822237947({"useridfavncode":"1119968_3231307","userid":1119968,"favncode":3231307,"categoryid":1,"isnotice":0,"memo":"","jyokyo":2,"no":0,"page":null,"created_at":"2026-07-12 11:11:33","updated_at":"2026-07-12 11:11:33","novelmain":{"ncode":3231307,"userid":1585393,"title":"タイトル","writer":"","noveltype":2,"classification":1,"created_at":"2026-07-08 12:25:15","updated_at":"2026-07-08 13:00:09"},"_favepisode_count":0,"isnoticecnt":311,"favnovelcategory":[{"useridcategoryid":"1119968_1","userid":1119968,"categoryid":1,"categoryname":"カテゴリ1","count":362,"kokaicount":362,"created_at":"2017-07-31 09:04:35","updated_at":"2026-07-12 11:10:06"}],"app_link":null,"result":true,"favnovelmain_addend_token":"3d05fae7f1247fa4a905e99f1ff1773d"});
''';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          if (url.startsWith('https://syosetu.com/favnovelmain/addajax/')) {
            return ResponseBody.fromString(realAddajaxResponse, 200);
          }
          return ResponseBody.fromString('result({})', 200);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        expect(result.useridFavncode, '1119968_3231307');
        expect(result.token, '3d05fae7f1247fa4a905e99f1ff1773d');
        final updateRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString().contains('updateajax'),
        );
        expect(
          updateRequest.uri.queryParameters['useridfavncode'],
          '1119968_3231307',
        );
        expect(
          updateRequest.uri.queryParameters['token'],
          '3d05fae7f1247fa4a905e99f1ff1773d',
        );
      });

      test('なろう側で既にブックマーク済みの場合はsuccessを返す', () async {
        // ブックマーク済みページではjs-bookmark_urlの代わりに
        // js-bookmark_updateconf_urlが存在する。
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_updateconf_url" '
              'value="https://syosetu.com/favnovelmain/updateconfajax/'
              'useridfavncode/1119968_3231307/">',
              200,
            );
          }
          return ResponseBody.fromString('', 404);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        // addajaxは呼ばれない
        expect(fakeAdapter.requests, hasLength(1));
      });

      test('js-bookmark_urlが存在しない場合はfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
      });

      test('外部ドメインのaddajax URLへ認証Cookieを送信しない', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://attacker.example/collect">',
              200,
            );
          }
          return ResponseBody.fromString(
            'result({"useridfavncode":"12345",'
            '"favnovelmain_addend_token":"abcxyz","result":true})',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=secret; ses=secret; userl=secret');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
        expect(fakeAdapter.requests, hasLength(1));
        expect(
          fakeAdapter.requests.any(
            (request) => request.uri.host == 'attacker.example',
          ),
          isFalse,
        );
      });

      test('作品ページの同一origin redirectを追跡してブックマークを登録する', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.host == 'ncode.syosetu.com' &&
              !options.uri.queryParameters.containsKey('canonical')) {
            return ResponseBody.fromString(
              '',
              302,
              headers: <String, List<String>>{
                'location': ['/n0156ia/?canonical=1'],
              },
            );
          }
          if (options.uri.host == 'ncode.syosetu.com') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          if (options.uri.path == '/favnovelmain/addajax/') {
            return ResponseBody.fromString(
              'result({"useridfavncode":"12345",'
              '"favnovelmain_addend_token":"abcxyz","result":true})',
              200,
            );
          }
          return ResponseBody.fromString('', 200);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        expect(fakeAdapter.requests, hasLength(4));
        expect(fakeAdapter.requests[1].uri.queryParameters['canonical'], '1');
        expect(
          fakeAdapter.requests
              .take(2)
              .every(
                (request) =>
                    request.headers['Cookie'] == 'ks2=x; ses=y; userl=z',
              ),
          isTrue,
        );
      });

      test('作品ページの外部origin redirect先へCookieを送らない', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['https://attacker.example/collect'],
            },
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=secret; ses=secret; userl=secret');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
        expect(fakeAdapter.requests, hasLength(1));
        expect(fakeAdapter.requests.single.uri.host, 'ncode.syosetu.com');
      });

      test(
        'addajaxが4xxを返した場合はfailedを返す',
        () async {
          // 4xxはサーバー側の状態を保証できないため失敗として扱う。
          final fakeAdapter = _FakeHttpClientAdapter((options) {
            final url = options.uri.toString();
            if (url == 'https://ncode.syosetu.com/n0156ia/') {
              return ResponseBody.fromString(
                '<input class="js-bookmark_url" '
                'value="https://syosetu.com/favnovelmain/addajax/'
                '?ncode=n0156ia">',
                200,
              );
            }
            return ResponseBody.fromString('error', 400);
          });
          when(
            mockAuthRepository.buildCookieHeader(),
          ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
          final service = NarouSyncService(
            authRepository: mockAuthRepository,
            db: mockDatabase,
            apiService: mockApiService,
            dio: Dio()..httpClientAdapter = fakeAdapter,
          );

          final result = await service.addBookmarkToNarou('n0156ia');

          expect(result.outcome, NarouBookmarkSyncOutcome.failed);
        },
      );

      test('addajaxレスポンスにトークンが含まれない場合はfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 200);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
        expect(result.useridFavncode, isNull);
        expect(result.token, isNull);
      });

      test('addajaxレスポンスのresultがfalseの場合はfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          return ResponseBody.fromString(
            'result({"result":false,"res_mes":"登録できません"})',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
      });

      test('updateajaxが失敗してもaddajaxが成功していればsuccessを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          if (url.startsWith('https://syosetu.com/favnovelmain/addajax/')) {
            return ResponseBody.fromString(
              'result({"useridfavncode":"12345",'
              '"favnovelmain_addend_token":"abcxyz","result":true})',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 500);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        expect(result.useridFavncode, '12345');
        expect(result.token, 'abcxyz');
      });

      test('addajax自体が到達不能な場合はfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/?ncode=n0156ia">',
              200,
            );
          }
          return ResponseBody.fromString('error', 500);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
      });
    });

    group('removeBookmarkFromNarou', () {
      test('セッションCookieがない場合はnotLoggedInを返す', () async {
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => null);

        final result = await syncService.removeBookmarkFromNarou('n0156ia');
        expect(result, NarouBookmarkSyncOutcome.notLoggedIn);
      });

      test('updateconf→deleteajaxの順で削除用トークンを使って解除する', () async {
        // ブックマーク済みの作品ページ（js-bookmark_urlは存在しない）
        const bookmarkedPageHtml = '''
<input type="hidden" class="js-bookmark_updateconf_url"
  value="https://syosetu.com/favnovelmain/updateconfajax/useridfavncode/1119968_3231307/">
<input type="hidden" class="js-del_bookmark_url"
  value="https://syosetu.com/favnovelmain/deleteajax/useridfavncode/1119968_3231307/">
''';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(bookmarkedPageHtml, 200);
          }
          if (url.contains('updateconfajax')) {
            return ResponseBody.fromString(
              'result({"result":true,'
              '"favnovelmain_delconf_token":"delconf-token"});',
              200,
            );
          }
          if (url.contains('deleteajax')) {
            return ResponseBody.fromString(
              'result({"result":true,"res_mes":""});',
              200,
            );
          }
          return ResponseBody.fromString('', 404);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.success);
        expect(fakeAdapter.requests, hasLength(3));
        final deleteRequest = fakeAdapter.requests.last;
        expect(
          deleteRequest.uri.toString(),
          startsWith(
            'https://syosetu.com/favnovelmain/deleteajax/'
            'useridfavncode/1119968_3231307/',
          ),
        );
        // 削除にはupdateconfで取得した専用トークンを使う
        expect(deleteRequest.uri.queryParameters['token'], 'delconf-token');
        expect(deleteRequest.uri.queryParameters['callback'], isNotNull);
        expect(deleteRequest.uri.queryParameters['_'], isNotNull);
      });

      test('なろう側が未ブックマークの場合は解除不要としてsuccessを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/'
              '?ncode=n0156ia">',
              200,
            );
          }
          return ResponseBody.fromString('', 404);
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.success);
        // 作品ページの取得のみでdeleteajaxは呼ばれない
        expect(fakeAdapter.requests, hasLength(1));
      });

      test('updateconfが削除用トークンを返さない場合はfailedを返す', () async {
        const bookmarkedPageHtml = '''
<input type="hidden" class="js-bookmark_updateconf_url"
  value="https://syosetu.com/favnovelmain/updateconfajax/useridfavncode/1119968_3231307/">
<input type="hidden" class="js-del_bookmark_url"
  value="https://syosetu.com/favnovelmain/deleteajax/useridfavncode/1119968_3231307/">
''';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(bookmarkedPageHtml, 200);
          }
          return ResponseBody.fromString(
            'result({"result":false,"res_mes":"エラー"});',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });

      test('外部ドメインのupdateconf URLへ認証Cookieを送信しない', () async {
        const bookmarkedPageHtml = '''
<input type="hidden" class="js-bookmark_updateconf_url"
  value="https://attacker.example/collect">
<input type="hidden" class="js-del_bookmark_url"
  value="https://syosetu.com/favnovelmain/deleteajax/useridfavncode/12345/">
''';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() == 'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(bookmarkedPageHtml, 200);
          }
          return ResponseBody.fromString(
            'result({"result":true,"favnovelmain_delconf_token":"token"})',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=secret; ses=secret; userl=secret');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
        expect(fakeAdapter.requests, hasLength(1));
        expect(
          fakeAdapter.requests.any(
            (request) => request.uri.host == 'attacker.example',
          ),
          isFalse,
        );
      });

      test('deleteajaxが例外を投げるとfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('error', 500),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });
    });

    group('setShioriIfLoggedIn', () {
      test('セッションCookieがない場合は何もしない', () async {
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => null);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verifyNever(mockDatabase.getNarouFavToken(any, any));
      });

      test('トークン情報が無い場合はしおりを設定しない', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(
          mockDatabase.getNarouFavToken(NovelSource.narou, 'n0156ia'),
        ).thenAnswer((_) async => null);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        expect(result, isFalse);
        verify(
          mockDatabase.getNarouFavToken(NovelSource.narou, 'n0156ia'),
        ).called(1);
      });

      test('エピソードページの最新トークンでichiupdateajaxを呼び出す', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.toString() ==
              'https://ncode.syosetu.com/n0156ia/1/') {
            return ResponseBody.fromString(
              '<input name="auto_siori" data-primary="1119968_3212720"> '
              '<input name="token" value="fresh-token">',
              200,
            );
          }
          return ResponseBody.fromString(
            'jQuery123456({"result":true,"res_mes":""});',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );

        expect(result, isTrue);
        expect(fakeAdapter.requests, hasLength(2));
        final request = fakeAdapter.requests.last;
        expect(
          request.uri.toString(),
          startsWith(
            'https://syosetu.com/favnovelmain/ichiupdateajax/'
            'useridfavncode/1119968_3212720/no/1/',
          ),
        );
        expect(
          request.uri.queryParameters['token'],
          'fresh-token',
        );
        expect(request.uri.queryParameters['callback'], isNotNull);
        expect(request.uri.queryParameters['_'], isNotNull);
      });

      test('エピソードページの同一origin redirect後に最新トークンを使う', () async {
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          if (options.uri.host == 'ncode.syosetu.com' &&
              !options.uri.queryParameters.containsKey('canonical')) {
            return ResponseBody.fromString(
              '',
              302,
              headers: <String, List<String>>{
                'location': ['/n0156ia/1/?canonical=1'],
              },
            );
          }
          if (options.uri.host == 'ncode.syosetu.com') {
            return ResponseBody.fromString(
              '<input name="auto_siori" data-primary="1119968_3212720"> '
              '<input name="token" value="fresh-token">',
              200,
            );
          }
          return ResponseBody.fromString(
            'jQuery123456({"result":true,"res_mes":""});',
            200,
          );
        });
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );

        expect(result, isTrue);
        expect(fakeAdapter.requests, hasLength(3));
        expect(fakeAdapter.requests[1].uri.queryParameters['canonical'], '1');
      });

      test('ichiupdateajaxが例外を投げても静かに無視する', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('error', 500),
        );
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(
          mockDatabase.getNarouFavToken(NovelSource.narou, 'n0156ia'),
        ).thenAnswer(
          (_) async => const NarouFavToken(
            useridFavncode: '1119968_3212720',
            token: '3d05fae7f1247fa4a905e99f1ff1773d',
          ),
        );
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        // 例外がスローされずに完了すればよい
        await service.setShioriIfLoggedIn(ncode: 'n0156ia', episode: 1);
      });
    });

    group('NarouBookmarkEntry', () {
      test('正しく生成される', () {
        const entry = NarouBookmarkEntry(ncode: 'n0156ia', shioriEpisode: 5);
        expect(entry.ncode, equals('n0156ia'));
        expect(entry.shioriEpisode, equals(5));
      });

      test('しおり位置なしで生成される', () {
        const entry = NarouBookmarkEntry(ncode: 'n0156ia');
        expect(entry.ncode, equals('n0156ia'));
        expect(entry.shioriEpisode, isNull);
      });
    });
  });
}
