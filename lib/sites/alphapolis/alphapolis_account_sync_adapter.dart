import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/remote_library_entry.dart';
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
         validateSessionStatus:
             authService.validateSessionStatusForCookieHeader,
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
    for (var attempt = 0; attempt < 2; attempt++) {
      final snapshot = await sessionRepository.getSessionSnapshot();
      if (snapshot == null) {
        throw const AccountSessionExpiredException(
          clearSessionOnCatch: false,
        );
      }

      try {
        final entries = await _fetchFavoriteEntries(snapshot.generation);
        final current = await sessionRepository.getSessionSnapshot();
        if (current == null) {
          throw const AccountSessionExpiredException(
            clearSessionOnCatch: false,
          );
        }
        if (current.generation != snapshot.generation) {
          throw const FormatException(
            '同期中に認証情報が更新されたため処理を中断しました',
          );
        }
        if (current.cookieHeader != snapshot.cookieHeader) {
          if (attempt == 0) continue;
          throw const FormatException(
            '同期中に認証Cookieが更新されたため処理を中断しました',
          );
        }

        var importedCount = 0;
        final imported = await sessionRepository.runIfSessionSnapshotMatches(
          snapshot,
          () async {
            importedCount = await _db.transaction(
              () => _importEntries(entries),
            );
          },
        );
        if (imported) return importedCount;

        final latest = await sessionRepository.getSessionSnapshot();
        if (latest == null) {
          throw const AccountSessionExpiredException(
            clearSessionOnCatch: false,
          );
        }
        if (attempt == 0 &&
            latest.generation == snapshot.generation &&
            latest.cookieHeader != snapshot.cookieHeader) {
          continue;
        }
        throw const FormatException(
          '同期中に認証情報が更新されたため処理を中断しました',
        );
      } on AccountSessionExpiredException {
        final cleared = await sessionRepository
            .clearAllIfSessionCookieHeaderAndGenerationMatches(
              snapshot.generation,
              snapshot.cookieHeader,
            );
        if (cleared) {
          throw const AccountSessionExpiredException(
            clearSessionOnCatch: false,
          );
        }

        final current = await sessionRepository.getSessionSnapshot();
        if (current == null) {
          throw const AccountSessionExpiredException(
            clearSessionOnCatch: false,
          );
        }
        if (attempt == 0 &&
            current.generation == snapshot.generation &&
            current.cookieHeader != snapshot.cookieHeader) {
          continue;
        }
        throw const FormatException(
          '同期中に認証情報が更新されたため失効応答を破棄しました',
        );
      }
    }
    throw const FormatException('お気に入りの同期を完了できませんでした');
  }

  Future<List<RemoteLibraryEntry>> _fetchFavoriteEntries(
    int expectedGeneration,
  ) async {
    final entriesById = <String, RemoteLibraryEntry>{};
    var page = 1;
    var lastPage = 1;

    while (page <= lastPage && page <= _maxFavoritePages) {
      final snapshot = await sessionRepository.getSessionSnapshot();
      if (snapshot == null) {
        throw const AccountSessionExpiredException(
          clearSessionOnCatch: false,
        );
      }
      if (snapshot.generation != expectedGeneration) {
        throw const FormatException(
          '同期中に認証情報が更新されたため処理を中断しました',
        );
      }

      final parsed = _parser.parse(
        await _fetchPage(page, snapshot.cookieHeader),
      );
      lastPage = parsed.lastPage;
      for (final entry in parsed.entries) {
        entriesById.putIfAbsent(entry.workId, () => entry);
      }
      page++;
    }
    return entriesById.values.toList(growable: false);
  }

  Future<int> _importEntries(List<RemoteLibraryEntry> entries) async {
    var importedCount = 0;
    for (final entry in entries) {
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

    debugPrint(
      '[AlphapolisSync] お気に入り同期完了 '
      '取得=${entries.length}件 新規=$importedCount件',
    );
    return importedCount;
  }

  /// お気に入り一覧の指定ページを取得する。
  Future<String> _fetchPage(int page, String cookieHeader) async {
    final url = page == 1 ? _favoriteNovelUrl : '$_favoriteNovelUrl?page=$page';

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

    if (response.statusCode == 401) {
      throw const AccountSessionExpiredException();
    }
    final location = response.headers.value('location');
    if (location != null) {
      if (_isLoginRedirect(location)) {
        throw const AccountSessionExpiredException();
      }
      throw const FormatException('お気に入り一覧が想定外のURLへ転送されました');
    }

    final body = response.data;
    if (response.statusCode != 200 || body == null || body.isEmpty) {
      throw const FormatException('お気に入り一覧を取得できませんでした');
    }
    return body;
  }

  bool _isLoginRedirect(String location) {
    final target = Uri.parse(_favoriteNovelUrl).resolve(location);
    return target.scheme == 'https' &&
        target.host == 'www.alphapolis.co.jp' &&
        target.port == 443 &&
        target.userInfo.isEmpty &&
        (target.path == '/login' || target.path == '/login/');
  }
}
