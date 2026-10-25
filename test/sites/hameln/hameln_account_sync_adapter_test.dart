import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/hameln_web_cookie_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/hameln/hameln_account_sync_adapter.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

class _MemorySessionRepository extends FormAuthSessionRepository {
  _MemorySessionRepository({
    this.cookieHeader = 'autologin=valid; sson=valid',
  }) : super(source: NovelSource.hameln);

  String? cookieHeader;
  int generation = 1;
  bool cleared = false;

  @override
  Future<Map<String, String>> getCookies() async => {
    for (final cookie in (cookieHeader ?? '').split(';'))
      if (cookie.trim().contains('='))
        cookie.trim().split('=').first: cookie.trim().split('=').last,
  };

  @override
  Future<String?> getAccountId() async => 'reader-id';

  @override
  Future<FormAuthSessionSnapshot?> getSessionSnapshot() async {
    final current = cookieHeader;
    if (current == null) return null;
    return FormAuthSessionSnapshot(
      accountId: 'reader-id',
      cookieHeader: current,
      generation: generation,
    );
  }

  @override
  Future<bool> runIfSessionSnapshotMatches(
    FormAuthSessionSnapshot snapshot,
    Future<void> Function() operation,
  ) async {
    final current = await getSessionSnapshot();
    if (current == null ||
        current.generation != snapshot.generation ||
        current.cookieHeader != snapshot.cookieHeader ||
        current.accountId != snapshot.accountId) {
      return false;
    }
    await operation();
    return true;
  }

  @override
  Future<bool> clearAllIfSessionCookieHeaderAndGenerationMatches(
    int expectedGeneration,
    String expectedCookieHeader,
  ) async {
    if (generation != expectedGeneration ||
        cookieHeader != expectedCookieHeader) {
      return false;
    }
    await clearAll();
    return true;
  }

  @override
  Future<void> clearAll() async {
    cookieHeader = null;
    generation++;
    cleared = true;
  }
}

class _FavoritesHttpAdapter implements HttpClientAdapter {
  _FavoritesHttpAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  String fixture(String name) =>
      File('test/fixtures/hameln/$name').readAsStringSync();

  group('HamelnAccountSyncAdapter pullLibrary', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    HamelnAccountSyncAdapter buildAdapter(
      _FavoritesHttpAdapter httpAdapter,
      _MemorySessionRepository repository, {
      List<Cookie>? restoredCookies,
    }) {
      final dio = Dio()..httpClientAdapter = httpAdapter;
      final site = HamelnSite(
        dio: dio,
        rateLimiter: RequestRateLimiter(interval: Duration.zero),
      );
      final webCookieService = HamelnWebCookieService(
        sessionRepository: repository,
        cookieSetter: (cookie) async {
          restoredCookies?.add(cookie);
        },
      );
      return HamelnAccountSyncAdapter(
        sessionRepository: repository,
        authService: HamelnAuthService(
          sessionRepository: repository,
          dio: dio,
        ),
        db: db,
        site: site,
        webCookieService: webCookieService,
      );
    }

    test('公式お気に入り一覧を取得し、CookieをWebViewへ復元して取り込む', () async {
      final repository = _MemorySessionRepository();
      final httpAdapter = _FavoritesHttpAdapter(fixture('favorites.html'));
      final restoredCookies = <Cookie>[];
      final adapter = buildAdapter(
        httpAdapter,
        repository,
        restoredCookies: restoredCookies,
      );

      expect(await adapter.pullLibrary(), 1);

      final request = httpAdapter.requests.single;
      expect(request.uri.toString(), 'https://syosetu.org/?mode=favo');
      expect(request.headers['Cookie'], repository.cookieHeader);
      expect(restoredCookies.map((cookie) => cookie.name), [
        'autologin',
        'sson',
      ]);
      expect(await db.isInLibrary(NovelSource.hameln, '429419'), isTrue);
      final novel = await db.getNovel(NovelSource.hameln, '429419');
      expect(novel?.title, '機械仕掛けの竜と相棒の物語');
      expect(novel?.writer, '作者名');

      expect(await adapter.pullLibrary(), 0);
    });

    test('既存の詳細情報をお気に入り一覧の最小情報で上書きしない', () async {
      await db.insertNovel(
        const NovelInfo(
          source: NovelSource.hameln,
          workId: '429419',
          title: '詳細ページから取得したタイトル',
          writer: '詳細ページから取得した作者',
          story: '詳細あらすじ',
        ).toDbCompanion(),
      );
      final repository = _MemorySessionRepository();
      final adapter = buildAdapter(
        _FavoritesHttpAdapter(fixture('favorites.html')),
        repository,
      );

      await adapter.pullLibrary();

      final novel = await db.getNovel(NovelSource.hameln, '429419');
      expect(novel?.title, '詳細ページから取得したタイトル');
      expect(novel?.story, '詳細あらすじ');
    });

    test('一覧の解析に失敗しても保存済み認証情報を削除しない', () async {
      final repository = _MemorySessionRepository();
      final adapter = buildAdapter(
        _FavoritesHttpAdapter('<html><title>ログイン</title></html>'),
        repository,
      );

      await expectLater(adapter.pullLibrary(), throwsFormatException);

      expect(repository.cookieHeader, 'autologin=valid; sson=valid');
      expect(repository.cleared, isFalse);
    });

    test('セッションCookieがなければ同期せず保存情報も削除しない', () async {
      final repository = _MemorySessionRepository(cookieHeader: 'uaid=guest');
      final adapter = buildAdapter(
        _FavoritesHttpAdapter(fixture('favorites.html')),
        repository,
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(
          isA<AccountSessionExpiredException>().having(
            (error) => error.clearSessionOnCatch,
            'clearSessionOnCatch',
            isFalse,
          ),
        ),
      );

      expect(repository.cleared, isFalse);
    });

    test('HTTP 401でも保存済み認証情報を自動削除しない', () async {
      final repository = _MemorySessionRepository();
      final adapter = buildAdapter(
        _FavoritesHttpAdapter('', statusCode: 401),
        repository,
      );

      await expectLater(
        adapter.pullLibrary(),
        throwsA(
          isA<AccountSessionExpiredException>().having(
            (error) => error.clearSessionOnCatch,
            'clearSessionOnCatch',
            isFalse,
          ),
        ),
      );

      expect(repository.cookieHeader, 'autologin=valid; sson=valid');
    });
  });
}
