import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/alphapolis/alphapolis_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

class _FakeSessionRepository extends FormAuthSessionRepository {
  _FakeSessionRepository(this.cookieHeader)
    : super(source: NovelSource.alphapolis);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;

  @override
  Future<void> clearAll() async {}
}

/// リクエストURLに応じた応答を返すHTTPアダプター。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(
  String body,
  int status, {
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      ...?headers,
    },
  );
}

void main() {
  String fixture(String name) =>
      File('test/fixtures/alphapolis/$name').readAsStringSync();

  group('AlphapolisAccountSyncAdapter pullLibrary', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    AlphapolisAccountSyncAdapter buildAdapter(
      _StubAdapter httpAdapter, {
      String? cookieHeader = 'alpl_v2_front_session=valid',
    }) {
      final repository = _FakeSessionRepository(cookieHeader);
      final dio = Dio()..httpClientAdapter = httpAdapter;
      return AlphapolisAccountSyncAdapter(
        sessionRepository: repository,
        authService: AlphapolisAuthService(
          sessionRepository: repository,
          dio: dio,
        ),
        db: db,
        dio: dio,
      );
    }

    test('全ページを辿ってライブラリへ取り込む', () async {
      final httpAdapter = _StubAdapter((options) {
        final page = options.uri.queryParameters['page'];
        return _html(
          fixture(
            page == '2'
                ? 'favorite_novel_page2.html'
                : 'favorite_novel_page1.html',
          ),
          200,
        );
      });
      final adapter = buildAdapter(httpAdapter);

      expect(await adapter.pullLibrary(), 3);

      expect(httpAdapter.requests.length, 2);
      expect(httpAdapter.requests.first.uri.queryParameters['page'], isNull);
      expect(httpAdapter.requests[1].uri.queryParameters['page'], '2');
      expect(
        httpAdapter.requests.first.headers['Cookie'],
        'alpl_v2_front_session=valid',
      );

      expect(
        await db.isInLibrary(NovelSource.alphapolis, '78147770-288151080'),
        isTrue,
      );
      expect(
        await db.isInLibrary(NovelSource.alphapolis, '784290940-355109340'),
        isTrue,
      );

      final novel = await db.getNovel(
        NovelSource.alphapolis,
        '78147770-288151080',
      );
      expect(novel?.title, '最初の作品');
      expect(novel?.writer, '作者A');
    });

    test('取り込み済みの作品は新規件数に数えない', () async {
      final httpAdapter = _StubAdapter(
        (_) => _html(fixture('favorite_novel_page2.html'), 200),
      );
      final adapter = buildAdapter(httpAdapter);

      expect(await adapter.pullLibrary(), 1);
      expect(await adapter.pullLibrary(), 0);
    });

    test('既存の詳細メタデータを一覧の値で上書きしない', () async {
      await db.insertNovel(
        const NovelInfo(
          source: NovelSource.alphapolis,
          workId: '784290940-355109340',
          title: '詳細ページ由来のタイトル',
          writer: '詳細ページ由来の作者',
          story: 'あらすじ',
        ).toDbCompanion(),
      );
      final adapter = buildAdapter(
        _StubAdapter((_) => _html(fixture('favorite_novel_page2.html'), 200)),
      );

      await adapter.pullLibrary();

      final novel = await db.getNovel(
        NovelSource.alphapolis,
        '784290940-355109340',
      );
      expect(novel?.title, '詳細ページ由来のタイトル');
      expect(novel?.story, 'あらすじ');
    });

    test('保存Cookieが無ければセッション失効', () async {
      final adapter = buildAdapter(
        _StubAdapter((_) => _html('', 200)),
        cookieHeader: null,
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(isA<AccountSessionExpiredException>()),
      );
    });

    test('ログインページへredirectされればセッション失効', () async {
      final adapter = buildAdapter(
        _StubAdapter(
          (_) => _html(
            '',
            302,
            headers: {
              'location': ['https://www.alphapolis.co.jp/login'],
            },
          ),
        ),
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(isA<AccountSessionExpiredException>()),
      );
    });
  });
}
