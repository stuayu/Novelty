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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        final addRequest = fakeAdapter.requests.firstWhere(
          (r) =>
              r.uri.toString().startsWith(
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
          if (options.uri.toString() ==
              'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_updateconf_url" '
              'value="https://syosetu.com/favnovelmain/updateconfajax/'
              'useridfavncode/1119968_3231307/">',
              200,
            );
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

        expect(result.outcome, NarouBookmarkSyncOutcome.success);
        // addajaxは呼ばれない
        expect(fakeAdapter.requests, hasLength(1));
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

        expect(result.outcome, NarouBookmarkSyncOutcome.failed);
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
          when(mockAuthRepository.buildCookieHeader())
              .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
          if (options.uri.toString() ==
              'https://ncode.syosetu.com/n0156ia/') {
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
          if (options.uri.toString() ==
              'https://ncode.syosetu.com/n0156ia/') {
            return ResponseBody.fromString(
              '<input class="js-bookmark_url" '
              'value="https://syosetu.com/favnovelmain/addajax/'
              '?ncode=n0156ia">',
              200,
            );
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        final service = NarouSyncService(
          authRepository: mockAuthRepository,
          db: mockDatabase,
          apiService: mockApiService,
          dio: Dio()..httpClientAdapter = fakeAdapter,
        );

        final result = await service.removeBookmarkFromNarou('n0156ia');

        expect(result, NarouBookmarkSyncOutcome.failed);
      });

      test('deleteajaxが例外を投げるとfailedを返す', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('error', 500),
        );
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        await syncService.setShioriIfLoggedIn(
          ncode: 'n0156ia',
          episode: 1,
        );
        verifyNever(mockDatabase.getNarouFavToken(any));
      });

      test('トークン情報が無い場合はしおりを設定しない', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('<html></html>', 200),
        );
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.getNarouFavToken('n0156ia'))
            .thenAnswer((_) async => null);
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
        verify(mockDatabase.getNarouFavToken('n0156ia')).called(1);
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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
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

      test('ichiupdateajaxが例外を投げても静かに無視する', () async {
        final fakeAdapter = _FakeHttpClientAdapter(
          (_) => ResponseBody.fromString('error', 500),
        );
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => 'ks2=x; ses=y; userl=z');
        when(mockDatabase.getNarouFavToken('n0156ia')).thenAnswer(
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
