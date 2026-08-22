import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/ncode_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'narou_sync_service.g.dart';

/// なろうへのブックマーク登録処理の結果。
enum NarouBookmarkSyncOutcome {
  /// なろうにログインしていないため同期対象外。
  notLoggedIn,

  /// 同期に成功した。
  success,

  /// ログイン済みだが同期に失敗した。
  failed,
}

/// [NarouSyncService.addBookmarkToNarou]の結果。
///
/// [outcome]が[NarouBookmarkSyncOutcome.success]の場合、
/// [useridFavncode]・[token]にしおり更新(`ichiupdateajax`)で
/// 再利用するトークン情報が入る。
class NarouBookmarkSyncResult {
  /// コンストラクタ。
  const NarouBookmarkSyncResult({
    required this.outcome,
    this.useridFavncode,
    this.token,
  });

  /// 処理結果。
  final NarouBookmarkSyncOutcome outcome;

  /// なろう本家のブックマークID（"{userid}_{favncode}"形式）。
  final String? useridFavncode;

  /// なろう本家のブックマーク操作用トークン。
  final String? token;
}

@Riverpod(keepAlive: true)
/// なろう同期サービスのプロバイダー。
NarouSyncService narouSyncService(Ref ref) {
  return NarouSyncService(
    authRepository: ref.watch(authRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
    apiService: ref.watch(apiServiceProvider),
  );
}

/// なろうとのブックマーク同期・しおり同期を行うサービス。
///
/// セキュリティ設計：
/// - 認証が必要な操作のみにCookieを付与する。
/// - 小説情報取得 (`api.syosetu.com`)・検索では認証Cookieを使用しない。
class NarouSyncService {
  /// コンストラクタ。
  ///
  /// [dio]を指定しない場合は新しい[Dio]インスタンスを使用する。
  /// テストではフェイクの[HttpClientAdapter]を設定した[Dio]を注入できる。
  NarouSyncService({
    required this.authRepository,
    required this.db,
    required this.apiService,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// 認証情報リポジトリ。
  final AuthRepository authRepository;

  /// データベース。
  final AppDatabase db;

  /// 小説APIサービス（認証なし）。
  final ApiService apiService;

  /// なろうへのHTTPリクエストに使用するDioインスタンス。
  final Dio _dio;

  static const _bookmarkListBase =
      'https://syosetu.com/favnovelmain/list/';
  static const _updateajaxUrl =
      'https://syosetu.com/favnovelmain/updateajax/';

  // -----------------------------------------------------------------------
  // ブックマーク同期（なろう → ローカル）
  // -----------------------------------------------------------------------

  /// なろうのブックマーク一覧を取得してローカルライブラリに同期する。
  ///
  /// - なろうにブックマークされている小説をローカルライブラリに追加する。
  /// - 各小説のしおり位置（既読エピソード）もローカル履歴に反映する。
  /// - 小説本文のキャッシュ取得は行わない。
  ///
  /// 戻り値：同期した小説のncodeリスト。
  Future<List<String>> syncBookmarksFromNarou() async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return [];

    final entries = await _fetchAllBookmarkEntries(cookieHeader);
    if (entries.isEmpty) return [];

    final syncedNcodes = <String>[];
    for (final entry in entries) {
      final ncode = entry.ncode;
      // LibraryEntriesの外部キー制約のため、先にNovelsテーブルにレコードを確保する
      await db.ensureNovelExists(NovelSource.narou, ncode);
      // ローカルライブラリに追加（すでに存在する場合は無視）
      await db.addToLibrary(NovelSource.narou, ncode);
      // なろう側で確認済みのブックマークのため同期済みとして記録する
      await db.markNarouBookmarkSynced(NovelSource.narou, ncode);
      syncedNcodes.add(ncode);

      // しおり位置をローカル履歴と比較して新しい方を採用する
      if (entry.shioriEpisode != null) {
        final localHistory = await db.getReadingHistoryEntry(
          NovelSource.narou,
          ncode,
        );
        final localEpisode = localHistory?.lastEpisodeId;
        if (localEpisode == null ||
            entry.shioriEpisode! > localEpisode) {
          await db.addToHistory(
            ReadingHistoryCompanion(
              source: drift.Value(NovelSource.narou),
              workId: drift.Value(ncode),
              lastEpisodeId: drift.Value(entry.shioriEpisode),
              viewedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
        }
      }
    }

    // APIから小説メタデータを一括取得してDBを更新する（認証Cookie不要）
    await _fetchAndStoreNovelMetadata(syncedNcodes);

    return syncedNcodes;
  }

  /// 小説メタデータをAPIから一括取得してNovelsテーブルに保存する。
  Future<void> _fetchAndStoreNovelMetadata(List<String> ncodes) async {
    if (ncodes.isEmpty) return;
    try {
      final novelMap = await apiService.fetchMultipleNovelsInfo(ncodes);
      for (final info in novelMap.values) {
        if (info.ncode != null) {
          await db.insertNovel(info.toDbCompanion());
        }
      }
    } on Exception {
      // メタデータ取得失敗はサイレントに無視する（ライブラリ登録には影響させない）
    }
  }

  /// ブックマーク一覧ページを全ページ走査してエントリーを取得する。
  Future<List<NarouBookmarkEntry>> _fetchAllBookmarkEntries(
    String cookieHeader,
  ) async {
    final allEntries = <NarouBookmarkEntry>[];
    var page = 1;
    while (true) {
      final entries = await _fetchBookmarkPage(cookieHeader, page);
      if (entries.isEmpty) break;
      allEntries.addAll(entries);
      if (entries.length < 50) {
        // 1ページあたり50件未満なら最終ページ
        break;
      }
      page++;
    }
    return allEntries;
  }

  /// ブックマーク一覧ページ1ページ分を取得・解析する。
  Future<List<NarouBookmarkEntry>> _fetchBookmarkPage(
    String cookieHeader,
    int page,
  ) async {
    final url = page == 1
        ? _bookmarkListBase
        : '$_bookmarkListBase?p=$page';
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
          },
          responseType: ResponseType.plain,
        ),
      );
      if (response.data == null) return [];
      return _parseBookmarkListHtml(response.data!);
    } on Exception {
      return [];
    }
  }

  /// ブックマーク一覧HTMLを解析してエントリーリストを返す。
  ///
  /// 解析対象のHTML構造：
  /// ```html
  /// <li class="p-up-bookmark-item">
  ///   <a href="https://ncode.syosetu.com/{ncode}/">タイトル</a>
  ///   <a href="https://ncode.syosetu.com/{ncode}/{ep}/" class="c-button--outline">
  ///     ep.{ep}  ← しおり位置
  ///   </a>
  /// </li>
  /// ```
  List<NarouBookmarkEntry> _parseBookmarkListHtml(String html) {
    final doc = parser.parse(html);
    final items = doc.querySelectorAll('.p-up-bookmark-item');
    final entries = <NarouBookmarkEntry>[];

    for (final item in items) {
      // タイトルリンクからncodeを抽出
      final titleLink = item.querySelector('.p-up-bookmark-item__title a');
      final href = titleLink?.attributes['href'] ?? '';
      final ncodeMatch = RegExp(
        r'https://ncode\.syosetu\.com/([^/]+)/',
      ).firstMatch(href);
      if (ncodeMatch == null) continue;
      final ncode = (ncodeMatch.group(1) ?? '').toLowerCase();

      // しおり位置ボタン（outline style = 現在のしおり位置）からエピソード番号を取得
      final shioriBtn = item.querySelector(
        '.p-up-bookmark-item__button.c-button--outline',
      );
      final shioriHref = shioriBtn?.attributes['href'] ?? '';
      final shioriMatch = RegExp(
        r'https://ncode\.syosetu\.com/[^/]+/(\d+)/',
      ).firstMatch(shioriHref);
      final shioriEpisode = shioriMatch != null
          ? int.tryParse(shioriMatch.group(1) ?? '')
          : null;

      entries.add(
        NarouBookmarkEntry(ncode: ncode, shioriEpisode: shioriEpisode),
      );
    }
    return entries;
  }

  // -----------------------------------------------------------------------
  // ブックマーク追加（ローカル → なろう）
  // -----------------------------------------------------------------------

  /// なろうに小説をブックマーク登録する。
  ///
  /// 作品ページにある `js-bookmark_url` hidden inputから
  /// addajax URLを取得し、ブックマーク登録を行う。
  /// なろう側で既にブックマーク済みの場合（`js-bookmark_url`の代わりに
  /// `js-bookmark_updateconf_url`が存在する場合）は成功として扱う。
  Future<NarouBookmarkSyncResult> addBookmarkToNarou(String ncode) async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) {
      return const NarouBookmarkSyncResult(
        outcome: NarouBookmarkSyncOutcome.notLoggedIn,
      );
    }

    try {
      // 小説トップページからブックマーク追加URLを取得する
      final novelUrl =
          'https://ncode.syosetu.com/${ncode.toNormalizedNcode()}/';
      final pageState = await _fetchBookmarkPageState(novelUrl, cookieHeader);
      final addajaxUrl = pageState?.addUrl;
      if (addajaxUrl == null) {
        if (pageState?.updateconfUrl != null) {
          debugPrint(
            '[NarouSync] addBookmarkToNarou($ncode): '
            'なろう側で既にブックマーク済みのため登録をスキップします',
          );
          return const NarouBookmarkSyncResult(
            outcome: NarouBookmarkSyncOutcome.success,
          );
        }
        debugPrint(
          '[NarouSync] addBookmarkToNarou($ncode): '
          'js-bookmark_urlが見つかりませんでした ($novelUrl)',
        );
        return const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        );
      }

      // Step 1: addajax を呼び、レスポンスのresultとトークンを検証する。
      // なろう本家のJSはJSONP形式（callback・キャッシュバスター付き）で
      // このURLを<script>タグ経由で呼び出しているため、同じ形式に合わせる。
      final addResponse = await _dio.get<String>(
        addajaxUrl,
        queryParameters: {
          'callback': 'result',
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
            'Referer': novelUrl,
          },
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      debugPrint(
        '[NarouSync] addBookmarkToNarou($ncode): '
        'addajax status=${addResponse.statusCode}',
      );

      final addData = _decodeJsonp(addResponse.data ?? '');
      if (addData?['result'] != true) {
        debugPrint(
          '[NarouSync] addBookmarkToNarou($ncode): '
          'addajaxが失敗を返しました',
        );
        return const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        );
      }

      // Step 2: updateajax で公開設定を確定する（ベストエフォート）。
      final tokenData = _extractAddajaxToken(addResponse.data ?? '');
      if (tokenData == null) {
        debugPrint(
          '[NarouSync] addBookmarkToNarou($ncode): '
          'addajaxレスポンスからトークンを抽出できませんでした',
        );
        return const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        );
      }

      try {
        final updateResponse = await _dio.get<dynamic>(
          _updateajaxUrl,
          queryParameters: {
            'useridfavncode': tokenData.useridfavncode,
            'token': tokenData.token,
            'isnotice': '1', // 更新通知ON
            'jyokyo': '2',  // 公開
            'categoryid': '1',
            'callback': 'result',
          },
          options: Options(
            headers: {
              'User-Agent': narouUserAgent,
              'Cookie': cookieHeader,
              'Referer': novelUrl,
            },
          ),
        );
        debugPrint(
          '[NarouSync] addBookmarkToNarou($ncode): '
          'updateajax status=${updateResponse.statusCode}',
        );
      } on Exception catch (e) {
        debugPrint(
          '[NarouSync] addBookmarkToNarou($ncode): '
          '設定確定(updateajax)で例外が発生しましたが、'
          'ブックマーク自体は登録済みとみなします: $e',
        );
      }
      return NarouBookmarkSyncResult(
        outcome: NarouBookmarkSyncOutcome.success,
        useridFavncode: tokenData.useridfavncode,
        token: tokenData.token,
      );
    } on Exception catch (e) {
      debugPrint('[NarouSync] addBookmarkToNarou($ncode): 例外発生: $e');
      return const NarouBookmarkSyncResult(
        outcome: NarouBookmarkSyncOutcome.failed,
      );
    }
  }

  /// なろうのブックマークを解除する。
  ///
  /// なろう本家のJS（novel_bookmarkmenu.js）と同じ手順で解除する：
  /// 1. 作品ページから `js-bookmark_updateconf_url`（設定変更用URL）と
  ///    `js-del_bookmark_url`（削除用URL）を取得する。
  /// 2. 設定変更用URLを呼び、削除用トークン
  ///    (`favnovelmain_delconf_token`) を取得する。
  /// 3. 削除用URLへトークンを付与してリクエストする。
  ///
  /// 登録時の`favnovelmain_addend_token`は削除には使用できない。
  Future<NarouBookmarkSyncOutcome> removeBookmarkFromNarou(
    String ncode,
  ) async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return NarouBookmarkSyncOutcome.notLoggedIn;

    try {
      final normalizedNcode = ncode.toNormalizedNcode();
      final novelUrl = 'https://ncode.syosetu.com/$normalizedNcode/';
      final pageState = await _fetchBookmarkPageState(novelUrl, cookieHeader);
      if (pageState == null) {
        debugPrint(
          '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
          '作品ページを取得できませんでした',
        );
        return NarouBookmarkSyncOutcome.failed;
      }

      final updateconfUrl = pageState.updateconfUrl;
      if (updateconfUrl == null) {
        if (pageState.addUrl != null) {
          // js-bookmark_urlのみ存在する場合、なろう側は未ブックマーク状態。
          debugPrint(
            '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
            'なろう側は未ブックマークのため解除不要',
          );
          return NarouBookmarkSyncOutcome.success;
        }
        debugPrint(
          '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
          'js-bookmark_updateconf_urlが見つかりませんでした',
        );
        return NarouBookmarkSyncOutcome.failed;
      }

      // 削除用トークンを取得する（本家JSの「ブックマーク設定変更」相当）。
      final confData = await _getJsonp(
        updateconfUrl,
        cookieHeader,
        referer: novelUrl,
      );
      final delconfToken = confData?['favnovelmain_delconf_token'];
      if (confData?['result'] != true ||
          delconfToken is! String ||
          delconfToken.isEmpty) {
        debugPrint(
          '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
          '削除用トークンを取得できませんでした '
          'res_mes=${confData?['res_mes']}',
        );
        return NarouBookmarkSyncOutcome.failed;
      }

      final delUrl = pageState.delUrl;
      if (delUrl == null) {
        debugPrint(
          '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
          'js-del_bookmark_urlが見つかりませんでした',
        );
        return NarouBookmarkSyncOutcome.failed;
      }

      final data = await _getJsonp(
        delUrl,
        cookieHeader,
        referer: novelUrl,
        extraQuery: {'token': delconfToken},
      );
      if (data?['result'] == true) {
        return NarouBookmarkSyncOutcome.success;
      }
      debugPrint(
        '[NarouSync] removeBookmarkFromNarou($normalizedNcode): '
        'result=${data?['result']} res_mes=${data?['res_mes']}',
      );
      return NarouBookmarkSyncOutcome.failed;
    } on Exception catch (e) {
      debugPrint('[NarouSync] removeBookmarkFromNarou: 例外発生: $e');
      return NarouBookmarkSyncOutcome.failed;
    }
  }

  /// 作品ページからブックマーク関連hidden inputの状態を取得する。
  ///
  /// - 未ブックマーク時: `js-bookmark_url`（addajax URL）が存在する。
  /// - ブックマーク済み時: `js-bookmark_updateconf_url`（設定変更用URL）と
  ///   `js-del_bookmark_url`（削除用URL）が存在する。
  Future<_BookmarkPageState?> _fetchBookmarkPageState(
    String novelUrl,
    String cookieHeader,
  ) async {
    try {
      final response = await _dio.get<String>(
        novelUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
          },
          responseType: ResponseType.plain,
        ),
      );
      final data = response.data;
      if (data == null) return null;
      final doc = parser.parse(data);

      String? valueOf(String selector) {
        final value = doc.querySelector(selector)?.attributes['value'];
        if (value == null || value.isEmpty) return null;
        // 相対URLの場合に備えてなろうのドメインで解決する
        return Uri.parse('https://syosetu.com/').resolve(value).toString();
      }

      return _BookmarkPageState(
        addUrl: valueOf('.js-bookmark_url'),
        updateconfUrl: valueOf('.js-bookmark_updateconf_url'),
        delUrl: valueOf('.js-del_bookmark_url'),
      );
    } on Exception {
      return null;
    }
  }

  /// なろうのJSONPエンドポイントへ認証付きGETを行い、デコード結果を返す。
  Future<Map<String, dynamic>?> _getJsonp(
    String url,
    String cookieHeader, {
    required String referer,
    Map<String, String> extraQuery = const {},
  }) async {
    final response = await _dio.get<String>(
      url,
      queryParameters: {
        ...extraQuery,
        'callback': 'result',
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
      options: Options(
        headers: {
          'User-Agent': narouUserAgent,
          'Cookie': cookieHeader,
          'Referer': referer,
        },
        responseType: ResponseType.plain,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    return _decodeJsonp(response.data ?? '');
  }

  /// addajax レスポンスからトークン情報を抽出する。
  _AddajaxTokenData? _extractAddajaxToken(String responseBody) {
    // JSONP形式 "callback({...})" または JSON形式 "{...}" を処理する
    var json = responseBody.trim();
    // JSONP wrapper を除去
    final jsonpMatch = RegExp(r'^\w+\((.+)\)\s*$', dotAll: true).firstMatch(json);
    if (jsonpMatch != null) {
      json = jsonpMatch.group(1)!;
    }
    try {
      // 簡易的なJSONパース（useridfavncode と favnovelmain_addend_token を抽出）
      final useridfavncodeMatch =
          RegExp(r'"useridfavncode"\s*:\s*"([^"]+)"').firstMatch(json);
      final tokenMatch =
          RegExp(r'"favnovelmain_addend_token"\s*:\s*"([^"]+)"')
              .firstMatch(json);
      // xidfavncode（R18作品の場合）も考慮
      final xidfavncodeMatch =
          RegExp(r'"xidfavncode"\s*:\s*"([^"]+)"').firstMatch(json);

      final useridfavncode = useridfavncodeMatch?.group(1) ??
          xidfavncodeMatch?.group(1);
      final token = tokenMatch?.group(1);

      if (useridfavncode == null || token == null) return null;
      return _AddajaxTokenData(
        useridfavncode: useridfavncode,
        token: token,
      );
    } on Exception {
      return null;
    }
  }

  /// JSONまたはJSONPレスポンスをMapへ変換する。
  Map<String, dynamic>? _decodeJsonp(String responseBody) {
    var jsonText = responseBody.trim();
    final jsonpMatch = RegExp(
      r'^[^(]+\((.*)\)\s*;?$',
      dotAll: true,
    ).firstMatch(jsonText);
    if (jsonpMatch != null) {
      jsonText = jsonpMatch.group(1)!;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // しおり同期（アプリ既読 → なろう）
  // -----------------------------------------------------------------------

  static const _ichiupdateajaxBase =
      'https://syosetu.com/favnovelmain/ichiupdateajax/';

  /// ログイン済みかつ対象小説がブックマーク済みの場合に、
  /// なろうのしおり位置を更新する。
  ///
  /// - `_updateHistory` が呼ばれるたびにバックグラウンドで実行する。
  /// - ログアウト中や失敗した場合は静かに無視する。
  /// - エピソードページから最新の`useridFavncode`・`token`を取得し、
  ///   `ichiupdateajax`エンドポイントへリクエストする。
  /// - HTMLから取得できない場合のみ、登録時に保存した値へフォールバックする。
  Future<bool> setShioriIfLoggedIn({
    required String ncode,
    required int episode,
  }) async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) {
      debugPrint('[NarouSync] setShioriIfLoggedIn($ncode): 未ログインのためスキップ');
      return false;
    }

    final normalizedNcode = ncode.toNormalizedNcode();
    final episodeUrl =
        'https://ncode.syosetu.com/$normalizedNcode/$episode/';

    // しおり用トークンは変化する可能性があるため、閲覧エピソードの
    // HTMLから最新値を取得する。これにより、なろうから同期した既存の
    // ブックマークでもしおりを更新できる。
    String? useridFavncode;
    String? token;
    try {
      final pageResponse = await _dio.get<String>(
        episodeUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
          },
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
          responseType: ResponseType.plain,
        ),
      );
      final doc = parser.parse(pageResponse.data ?? '');
      useridFavncode = doc
          .querySelector('input[name="auto_siori"]')
          ?.attributes['data-primary'];
      token = doc.querySelector('input[name="token"]')?.attributes['value'];
    } on Exception catch (e) {
      debugPrint(
        '[NarouSync] setShioriIfLoggedIn($ncode): '
        'エピソードページからトークンを取得できませんでした: $e',
      );
    }

    // HTML構造変更時の後方互換として、登録時に保存した値へフォールバックする。
    if (useridFavncode == null || token == null) {
      final savedToken = await db.getNarouFavToken(
        NovelSource.narou,
        normalizedNcode,
      );
      useridFavncode ??= savedToken?.useridFavncode;
      token ??= savedToken?.token;
    }

    if (useridFavncode == null || token == null) {
      debugPrint(
        '[NarouSync] setShioriIfLoggedIn($ncode): '
        'しおり用トークン情報が無いためスキップ',
      );
      return false;
    }

    try {
      final url =
          '$_ichiupdateajaxBase'
          'useridfavncode/$useridFavncode/no/$episode/';
      final response = await _dio.get<String>(
        url,
        queryParameters: {
          'token': token,
          'callback': 'result',
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
            'Referer': episodeUrl,
          },
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      debugPrint(
        '[NarouSync] setShiori($ncode, ep$episode): '
        'ichiupdateajax status=${response.statusCode}',
      );
      final data = _decodeJsonp(response.data ?? '');
      return data?['result'] == true;
    } on Exception catch (e) {
      // しおり設定の失敗はサイレントに無視する（本文読み込みに影響させない）
      debugPrint('[NarouSync] setShiori($ncode, ep$episode): 例外発生: $e');
      return false;
    }
  }
}

/// ブックマーク一覧エントリーを表すクラス。
class NarouBookmarkEntry {
  /// コンストラクタ。
  const NarouBookmarkEntry({
    required this.ncode,
    this.shioriEpisode,
  });

  /// 小説のncode（小文字）。
  final String ncode;

  /// なろう上のしおり位置（最後に読んだエピソード番号）。
  final int? shioriEpisode;
}

/// addajaxレスポンスから取得するトークンデータ。
class _AddajaxTokenData {
  const _AddajaxTokenData({
    required this.useridfavncode,
    required this.token,
  });

  final String useridfavncode;
  final String token;
}

/// 作品ページのブックマーク関連hidden inputの状態。
class _BookmarkPageState {
  const _BookmarkPageState({
    this.addUrl,
    this.updateconfUrl,
    this.delUrl,
  });

  /// ブックマーク追加用URL（未ブックマーク時のみ存在）。
  final String? addUrl;

  /// ブックマーク設定変更用URL（ブックマーク済み時のみ存在）。
  final String? updateconfUrl;

  /// ブックマーク削除用URL（ブックマーク済み時のみ存在）。
  final String? delUrl;
}
