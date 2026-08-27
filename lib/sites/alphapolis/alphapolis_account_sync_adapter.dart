import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/alphapolis/alphapolis_favorite_parser.dart';
import 'package:novelty/sites/form_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';

/// お気に入り小説一覧。
const _favoriteNovelUrl =
    'https://www.alphapolis.co.jp/mypage/favorite/index/novel';

/// 取得するページ数の安全弁。1ページ40件のため十分な余裕がある。
const _maxFavoritePages = 100;

/// アルファポリスの認証状態とお気に入り同期を共通表現へ接続するAdapter。
class AlphapolisAccountSyncAdapter extends FormAccountSyncAdapter {
  /// コンストラクタ。
  AlphapolisAccountSyncAdapter({
    required super.sessionRepository,
    required AlphapolisAuthService authService,
    required AppDatabase db,
    Dio? dio,
    AlphapolisFavoriteParser? parser,
    RequestRateLimiter? rateLimiter,
  }) : _db = db,
       _dio = dio ?? createNoveltyDio(rateLimiter: rateLimiter),
       _parser = parser ?? AlphapolisFavoriteParser(),
       super(
         source: NovelSource.alphapolis,
         validateSession: authService.isSessionValid,
         clearSession: authService.logout,
       );

  final AppDatabase _db;
  final Dio _dio;
  final AlphapolisFavoriteParser _parser;

  /// お気に入り小説をローカルライブラリへ取り込む。
  ///
  /// 新しくライブラリへ追加した作品数を返す。
  @override
  Future<int> pullLibrary() async {
    final cookieHeader = await sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) {
      throw const AccountSessionExpiredException();
    }

    final seenWorkIds = <String>{};
    var importedCount = 0;
    var page = 1;
    var lastPage = 1;

    while (page <= lastPage && page <= _maxFavoritePages) {
      final parsed = _parser.parse(await _fetchPage(page, cookieHeader));
      lastPage = parsed.lastPage;

      for (final entry in parsed.entries) {
        if (!seenWorkIds.add(entry.workId)) continue;

        final wasInLibrary = await _db.isInLibrary(source, entry.workId);

        // 一覧由来の最小メタデータで既存の詳細メタデータを上書きしない。
        // 未登録の作品だけ最小レコードを作る。
        if (await _db.getNovel(source, entry.workId) == null) {
          await _db.insertNovel(
            NovelInfo(
              source: source,
              workId: entry.workId,
              title: entry.title,
              writer: entry.writer,
            ).toDbCompanion(),
          );
        }

        await _db.addToLibrary(source, entry.workId);
        if (!wasInLibrary) importedCount++;
      }

      page++;
    }

    debugPrint(
      '[AlphapolisSync] お気に入り同期完了 '
      '取得=${seenWorkIds.length}件 新規=$importedCount件',
    );
    return importedCount;
  }

  /// お気に入り一覧の指定ページを取得する。
  Future<String> _fetchPage(int page, String cookieHeader) async {
    final url = page == 1
        ? _favoriteNovelUrl
        : '$_favoriteNovelUrl?page=$page';

    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: <String, Object>{
          'Cookie': cookieHeader,
          'User-Agent': noveltyUserAgent,
        },
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.plain,
      ),
    );

    // 未ログイン時はログインページへ戻される。
    if (response.headers.value('location') != null) {
      throw const AccountSessionExpiredException();
    }

    final body = response.data;
    if (response.statusCode != 200 || body == null || body.isEmpty) {
      throw const FormatException('お気に入り一覧を取得できませんでした');
    }
    return body;
  }
}
