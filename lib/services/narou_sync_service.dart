import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:html/parser.dart' as parser;
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/api_service.dart';
import 'package:novelty/services/narou_auth_service.dart';
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
      await db.ensureNovelExists(ncode);
      // ローカルライブラリに追加（すでに存在する場合は無視）
      await db.addToLibrary(ncode);
      // なろう側で確認済みのブックマークのため同期済みとして記録する
      await db.markNarouBookmarkSynced(ncode);
      syncedNcodes.add(ncode);

      // しおり位置をローカル履歴と比較して新しい方を採用する
      if (entry.shioriEpisode != null) {
        final localHistory = await db.getReadingHistoryByNcode(ncode);
        final localEpisode = localHistory?.lastEpisodeId;
        if (localEpisode == null ||
            entry.shioriEpisode! > localEpisode) {
          await db.addToHistory(
            ReadingHistoryCompanion(
              ncode: drift.Value(ncode),
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
  /// エピソードページにある `js-bookmark_url` hidden inputから
  /// addajax URLを取得し、ブックマーク登録を行う。
  Future<NarouBookmarkSyncOutcome> addBookmarkToNarou(String ncode) async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return NarouBookmarkSyncOutcome.notLoggedIn;

    try {
      // 小説トップページからブックマーク追加URLを取得する
      final novelUrl =
          'https://ncode.syosetu.com/${ncode.toNormalizedNcode()}/';
      final addajaxUrl = await _fetchBookmarkAddUrl(novelUrl, cookieHeader);
      if (addajaxUrl == null) return NarouBookmarkSyncOutcome.failed;

      // Step 1: addajax を呼んでトークンを取得する
      final addResponse = await _dio.get<String>(
        addajaxUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
            'Referer': novelUrl,
          },
          responseType: ResponseType.plain,
        ),
      );

      // Step 2: updateajax でブックマークを確定する（デフォルト設定）
      final tokenData = _extractAddajaxToken(addResponse.data ?? '');
      if (tokenData == null) return NarouBookmarkSyncOutcome.failed;

      final updateResponse = await _dio.get<dynamic>(
        '$_updateajaxUrl?callback=result',
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

      return updateResponse.statusCode == 200
          ? NarouBookmarkSyncOutcome.success
          : NarouBookmarkSyncOutcome.failed;
    } on Exception {
      return NarouBookmarkSyncOutcome.failed;
    }
  }

  /// 小説ページから `js-bookmark_url` の値（addajax URL）を取得する。
  Future<String?> _fetchBookmarkAddUrl(
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
      // 最初の js-bookmark_url hidden input を取得
      final input = doc.querySelector('input.js-bookmark_url');
      return input?.attributes['value'];
    } on Exception {
      return null;
    }
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

  // -----------------------------------------------------------------------
  // しおり同期（アプリ既読 → なろう）
  // -----------------------------------------------------------------------

  /// ログイン済みかつ対象小説がブックマーク済みの場合に、
  /// なろうのしおり位置を更新する。
  ///
  /// - `_updateHistory` が呼ばれるたびにバックグラウンドで実行する。
  /// - ログアウト中や失敗した場合は静かに無視する。
  Future<void> setShioriIfLoggedIn({
    required String ncode,
    required int episode,
  }) async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return;

    // なろう側で実際にブックマーク登録が完了しているか確認
    final isSynced = await db.isNarouBookmarkSynced(ncode);
    if (!isSynced) return;

    await _setShioriOnNarou(
      ncode: ncode,
      episode: episode,
      cookieHeader: cookieHeader,
    );
  }

  /// なろうのしおりを指定エピソードに設定する。
  ///
  /// エピソードページを認証Cookie付きでフェッチし、
  /// ページ内の `siori_url` または `auto_siori` データからしおりURLを取得して
  /// リクエストを送信する。
  Future<void> _setShioriOnNarou({
    required String ncode,
    required int episode,
    required String cookieHeader,
  }) async {
    final episodeUrl =
        'https://ncode.syosetu.com/${ncode.toNormalizedNcode()}/$episode/';
    try {
      final response = await _dio.get<String>(
        episodeUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
            'Referer': 'https://ncode.syosetu.com/${ncode.toNormalizedNcode()}/',
          },
          responseType: ResponseType.plain,
        ),
      );
      if (response.data == null) return;

      final html = response.data;
      if (html == null) return;
      final doc = parser.parse(html);

      // しおりURLを取得（手動しおり: GETリクエスト）
      final sioriInput = doc.querySelector('input[name="siori_url"]');
      final sioriUrl = sioriInput?.attributes['value'];
      if (sioriUrl != null) {
        await _dio.get<dynamic>(
          '$sioriUrl&callback=result',
          options: Options(
            headers: {
              'User-Agent': narouUserAgent,
              'Cookie': cookieHeader,
              'Referer': episodeUrl,
            },
          ),
        );
        return;
      }

      // 自動しおり: POSTリクエスト（現在位置 > Narouしおり位置の場合のみ）
      final autoSioriInput = doc.querySelector('input[name="auto_siori"]');
      if (autoSioriInput != null) {
        final url = autoSioriInput.attributes['data-url'];
        final no = autoSioriInput.attributes['data-no'];
        final primary = autoSioriInput.attributes['data-primary'];
        final token = autoSioriInput.attributes['data-token'];
        final favno = autoSioriInput.attributes['data-favno'];

        if (url == null || no == null || token == null) return;

        // auto_sioriはno > favnoの場合のみ更新する
        final noInt = int.tryParse(no) ?? 0;
        final favnoInt = int.tryParse(favno ?? '0') ?? 0;
        if (noInt <= favnoInt) return;

        await _dio.post<dynamic>(
          url,
          data: {
            'no': no,
            'primary': primary ?? '0',
            'token': token,
          },
          options: Options(
            headers: {
              'User-Agent': narouUserAgent,
              'Cookie': cookieHeader,
              'Referer': episodeUrl,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          ),
        );
      }
    } on Exception {
      // しおり設定の失敗はサイレントに無視する（本文読み込みに影響させない）
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
