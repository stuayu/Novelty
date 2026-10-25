import 'package:flutter/foundation.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/models/remote_library_entry.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/hameln_web_cookie_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/form_account_sync_adapter.dart';
import 'package:novelty/sites/hameln/hameln_favorite_parser.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/novel_source.dart';

/// ハーメルンの認証状態とお気に入り同期を共通表現へ接続するAdapter。
class HamelnAccountSyncAdapter extends FormAccountSyncAdapter {
  /// コンストラクタ。
  HamelnAccountSyncAdapter({
    required super.sessionRepository,
    required HamelnAuthService authService,
    required AppDatabase db,
    required HamelnSite site,
    required HamelnWebCookieService webCookieService,
    HamelnFavoriteParser parser = const HamelnFavoriteParser(),
  }) : _authService = authService,
       _db = db,
       _site = site,
       _webCookieService = webCookieService,
       _parser = parser,
       super(
         source: NovelSource.hameln,
         validateSession: authService.isSessionValidForCookieHeader,
         clearSession: authService.logout,
       );

  final HamelnAuthService _authService;
  final AppDatabase _db;
  final HamelnSite _site;
  final HamelnWebCookieService _webCookieService;
  final HamelnFavoriteParser _parser;

  /// お気に入り小説をローカルライブラリへ取り込む。
  ///
  /// 既存の詳細情報を一覧ページの値で上書きせず、新規登録数を返す。
  @override
  Future<int> pullLibrary() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final snapshot = await sessionRepository.getSessionSnapshot();
      if (snapshot == null ||
          !await _authService.isSessionValidForCookieHeader(
            snapshot.cookieHeader,
          )) {
        throw const AccountSessionExpiredException(
          clearSessionOnCatch: false,
        );
      }

      await _webCookieService.restoreToWebView();
      final entries = await _fetchFavoriteEntries(snapshot.cookieHeader);
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
      throw const FormatException('同期中に認証情報が更新されたため処理を中断しました');
    }
    throw const FormatException('お気に入りの同期を完了できませんでした');
  }

  Future<List<RemoteLibraryEntry>> _fetchFavoriteEntries(
    String cookieHeader,
  ) async {
    final String html;
    try {
      html = await _site.fetchFavoriteLibraryPage(cookieHeader);
    } on HamelnHttpException catch (error) {
      if (error.statusCode == 401) {
        throw const AccountSessionExpiredException(
          clearSessionOnCatch: false,
        );
      }
      rethrow;
    }
    try {
      return _parser.parse(html);
    } on FormatException catch (error) {
      throw FormatException(
        'ハーメルンのお気に入り一覧を解析できません: ${error.message}',
      );
    }
  }

  Future<int> _importEntries(List<RemoteLibraryEntry> entries) async {
    var importedCount = 0;
    for (final entry in entries) {
      final wasInLibrary = await _db.isInLibrary(source, entry.workId);
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
      '[HamelnSync] お気に入り同期完了 '
      '取得=${entries.length}件 新規=$importedCount件',
    );
    return importedCount;
  }
}
