import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_sync_service.dart';

import 'narou_sync_service_test.mocks.dart';

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
    late MockAuthRepository mockAuthRepository;
    late MockAppDatabase mockDatabase;
    late MockApiService mockApiService;
    late NarouSyncService syncService;

    setUp(() {
      mockAuthRepository = MockAuthRepository();
      mockDatabase = MockAppDatabase();
      mockApiService = MockApiService();
      syncService = NarouSyncService(
        authRepository: mockAuthRepository,
        db: mockDatabase,
        apiService: mockApiService,
      );
    });

    group('syncBookmarksFromNarou', () {
      test('セッションCookieがない場合は空リストを返す', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        final result = await syncService.syncBookmarksFromNarou();
        expect(result, isEmpty);
        verifyNever(mockDatabase.addToLibrary(any));
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.ensureNovelExists(any)).thenAnswer((_) async {});
        when(mockDatabase.addToLibrary(any)).thenAnswer((_) async => 1);
        when(
          mockDatabase.markNarouBookmarkSynced(any),
        ).thenAnswer((_) async {});
        when(
          mockDatabase.getReadingHistoryByNcode(any),
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
        verify(mockDatabase.ensureNovelExists('n0156ia')).called(1);
        verify(mockDatabase.addToLibrary('n0156ia')).called(1);
        verify(mockDatabase.markNarouBookmarkSynced('n0156ia')).called(1);
      });
    });

    group('addBookmarkToNarou', () {
      test('セッションCookieがない場合はnotLoggedInを返す', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        final result = await syncService.addBookmarkToNarou('n0156ia');
        expect(result, NarouBookmarkSyncOutcome.notLoggedIn);
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
              '"favnovelmain_addend_token":"abcxyz"})',
              200,
            );
          }
          if (url.startsWith('https://syosetu.com/favnovelmain/updateajax/')) {
            return ResponseBody.fromString('result({})', 200);
          }
          return ResponseBody.fromString('', 404);
        });
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.success);
        final updateRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString().contains('updateajax'),
        );
        expect(updateRequest.uri.queryParameters['useridfavncode'], '12345');
        expect(updateRequest.uri.queryParameters['token'], 'abcxyz');
      });

      test('js-bookmark_urlが存在しない場合はfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });

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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });

      test('updateajaxが200以外の場合はfailedを返す', () async {
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
              '"favnovelmain_addend_token":"abcxyz"})',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 500);
        });
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.addBookmarkToNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });
    });

    group('setShioriIfLoggedIn', () {
      test('セッションCookieがない場合は何もしない', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verifyNever(mockDatabase.isNarouBookmarkSynced(any));
      });

      test('なろう未同期の場合はしおりを設定しない', () async {
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isNarouBookmarkSynced('n0156ia'))
            .thenAnswer((_) async => false);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verify(mockDatabase.isNarouBookmarkSynced('n0156ia')).called(1);
      });

      test('手動しおり: siori_urlへGETリクエストが送られる', () async {
        const sioriUrl =
            'https://syosetu.com/favnovelmain/sioriupdate/'
            '?ncode=n0156ia&no=1';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/1/') {
            return ResponseBody.fromString(
              '<input name="siori_url" value="$sioriUrl">',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 200);
        });
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isNarouBookmarkSynced('n0156ia'))
            .thenAnswer((_) async => true);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await service.setShioriIfLoggedIn(ncode: 'n0156ia', episode: 1);

        final sioriRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString().startsWith(sioriUrl),
        );
        expect(sioriRequest.method, 'GET');
      });

      test('自動しおり: no>favnoの場合はdata-urlへPOSTされる', () async {
        const autoSioriUrl = 'https://syosetu.com/favnovelmain/autosiori/';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/1/') {
            return ResponseBody.fromString(
              '<input name="auto_siori" data-url="$autoSioriUrl" '
              'data-no="5" data-primary="0" data-token="tok123" '
              'data-favno="2">',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 200);
        });
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isNarouBookmarkSynced('n0156ia'))
            .thenAnswer((_) async => true);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await service.setShioriIfLoggedIn(ncode: 'n0156ia', episode: 1);

        final postRequest = fakeAdapter.requests.firstWhere(
          (r) => r.uri.toString() == autoSioriUrl,
        );
        expect(postRequest.method, 'POST');
        expect(postRequest.data, isA<Map<String, dynamic>>());
        final body = postRequest.data as Map<String, dynamic>;
        expect(body['no'], '5');
        expect(body['token'], 'tok123');
      });

      test('自動しおり: no<=favnoの場合はPOSTされない', () async {
        const autoSioriUrl = 'https://syosetu.com/favnovelmain/autosiori/';
        final fakeAdapter = _FakeHttpClientAdapter((options) {
          final url = options.uri.toString();
          if (url == 'https://ncode.syosetu.com/n0156ia/1/') {
            return ResponseBody.fromString(
              '<input name="auto_siori" data-url="$autoSioriUrl" '
              'data-no="1" data-primary="0" data-token="tok123" '
              'data-favno="2">',
              200,
            );
          }
          return ResponseBody.fromString('result({})', 200);
        });
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isNarouBookmarkSynced('n0156ia'))
            .thenAnswer((_) async => true);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await service.setShioriIfLoggedIn(ncode: 'n0156ia', episode: 1);

        expect(
          fakeAdapter.requests.any((r) => r.uri.toString() == autoSioriUrl),
          isFalse,
        );
      });

      test('siori_url・auto_sioriどちらも無い場合は何も送信しない', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.isNarouBookmarkSynced('n0156ia'))
            .thenAnswer((_) async => true);
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        await service.setShioriIfLoggedIn(ncode: 'n0156ia', episode: 1);

        // エピソードページの取得(1件)のみで、それ以外のリクエストは発生しない
        expect(fakeAdapter.requests, hasLength(1));
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
