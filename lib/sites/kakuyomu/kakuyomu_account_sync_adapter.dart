import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_follow_service.dart';
import 'package:novelty/services/kakuyomu_reading_progress_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_followed_works_parser.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';

const _initialFollowedWorksUrl =
    'https://kakuyomu.jp/my/antenna/works/all?order=last_read_at';

/// カクヨムの保存済みセッションが失効している場合の例外。
class KakuyomuSessionExpiredException implements Exception {
  /// コンストラクタ。
  const KakuyomuSessionExpiredException();

  @override
  String toString() => 'KakuyomuSessionExpiredException';
}

/// フォロー一覧1ページのHTTP取得結果。
class KakuyomuFollowedWorksHttpResponse {
  /// コンストラクタ。
  const KakuyomuFollowedWorksHttpResponse({
    required this.statusCode,
    required this.realUri,
    this.body,
  });

  /// HTTPステータスコード。
  final int statusCode;

  /// リダイレクト後の最終URL。
  final Uri realUri;

  /// HTML本文。
  final String? body;
}

/// テスト時にHTTP取得を差し替えるためのコールバック。
typedef KakuyomuFollowedWorksPageFetcher =
    Future<KakuyomuFollowedWorksHttpResponse> Function(
      Uri url,
      String cookieHeader,
    );

/// リモートのフォロー操作をテスト時に差し替えるためのコールバック。
typedef KakuyomuRemoteFollowOperation =
    Future<AccountSyncOutcome> Function(String workId);

/// ローカル話数から目次キャッシュの公式episode URLを解決するコールバック。
typedef KakuyomuEpisodeUrlResolver =
    Future<String?> Function(String workId, int episode);

/// リモート読書位置操作をテスト時に差し替えるためのコールバック。
typedef KakuyomuRemoteReadingProgressOperation =
    Future<bool> Function({
      required String workId,
      required String episodeId,
      required String position,
    });

/// カクヨムのリモート読書位置取得をテスト時に差し替えるコールバック。
typedef KakuyomuRemoteReadingStateOperation =
    Future<KakuyomuRemoteReadingState> Function(String workId);

/// カクヨムの目次取得をテスト時に差し替えるコールバック。
typedef KakuyomuEpisodeListResolver =
    Future<List<Episode>> Function(
      String workId,
    );

/// カクヨム同期アダプターのProvider。
final kakuyomuAccountSyncAdapterProvider = Provider<KakuyomuAccountSyncAdapter>(
  (ref) {
    final followService = ref.watch(kakuyomuFollowServiceProvider);
    final readingProgressService = ref.watch(
      kakuyomuReadingProgressServiceProvider,
    );
    final kakuyomuSite = ref.watch(
      novelSiteRegistryProvider,
    )[NovelSource.kakuyomu]!;
    return KakuyomuAccountSyncAdapter(
      sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
      db: ref.watch(appDatabaseProvider),
      followWork: followService.followWork,
      unfollowWork: followService.unfollowWork,
      pushReadingProgress: readingProgressService.record,
      fetchRemoteReadingState: readingProgressService.fetchRemoteState,
      episodeListResolver: kakuyomuSite.fetchToc,
    );
  },
);

/// カクヨムのアカウント同期アダプター。
///
/// フォロー一覧の取り込みは認証済みHTMLをDioで取得し、追加・解除は
/// 現行カクヨムWeb版のGraphQL mutationをDioで直接呼び出す。
/// 読書位置は現行episode viewerが利用するhistory HTTP endpointへ同期する。
class KakuyomuAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  KakuyomuAccountSyncAdapter({
    required KakuyomuSessionRepository sessionRepository,
    required AppDatabase db,
    Dio? dio,
    KakuyomuFollowedWorksParser? parser,
    KakuyomuFollowedWorksPageFetcher? pageFetcher,
    KakuyomuRemoteFollowOperation? followWork,
    KakuyomuRemoteFollowOperation? unfollowWork,
    KakuyomuEpisodeUrlResolver? episodeUrlResolver,
    KakuyomuRemoteReadingProgressOperation? pushReadingProgress,
    KakuyomuRemoteReadingStateOperation? fetchRemoteReadingState,
    KakuyomuEpisodeListResolver? episodeListResolver,
    KakuyomuRateLimiter? rateLimiter,
  }) : _sessionRepository = sessionRepository,
       _db = db,
       _dio = dio ?? Dio(),
       _parser = parser ?? KakuyomuFollowedWorksParser(),
       _pageFetcher = pageFetcher,
       _followWork = followWork,
       _unfollowWork = unfollowWork,
       _episodeUrlResolver = episodeUrlResolver,
       _pushReadingProgress = pushReadingProgress,
       _fetchRemoteReadingState = fetchRemoteReadingState,
       _episodeListResolver = episodeListResolver,
       _rateLimiter = rateLimiter ?? KakuyomuRateLimiter();

  final KakuyomuSessionRepository _sessionRepository;
  final AppDatabase _db;
  final Dio _dio;
  final KakuyomuFollowedWorksParser _parser;
  final KakuyomuFollowedWorksPageFetcher? _pageFetcher;
  final KakuyomuRemoteFollowOperation? _followWork;
  final KakuyomuRemoteFollowOperation? _unfollowWork;
  final KakuyomuEpisodeUrlResolver? _episodeUrlResolver;
  final KakuyomuRemoteReadingProgressOperation? _pushReadingProgress;
  final KakuyomuRemoteReadingStateOperation? _fetchRemoteReadingState;
  final KakuyomuEpisodeListResolver? _episodeListResolver;
  final KakuyomuRateLimiter _rateLimiter;

  @override
  NovelSource get source => NovelSource.kakuyomu;

  Future<KakuyomuFollowedWorksHttpResponse> _fetchPage(
    Uri url,
    String cookieHeader,
  ) async {
    final override = _pageFetcher;
    if (override != null) return override(url, cookieHeader);

    // 実サイトへの連続アクセスは既存のカクヨム取得処理と同じ1秒間隔にする。
    await _rateLimiter.wait();
    final response = await _dio.get<String>(
      url.toString(),
      options: Options(
        headers: <String, Object>{
          'Cookie': cookieHeader,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36',
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.plain,
      ),
    );

    return KakuyomuFollowedWorksHttpResponse(
      statusCode: response.statusCode ?? 0,
      realUri: response.realUri,
      body: response.data,
    );
  }

  @override
  Future<int> pullLibrary() async {
    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) {
      throw const KakuyomuSessionExpiredException();
    }

    final seenPageUrls = <Uri>{};
    final seenWorkIds = <String>{};
    var currentUrl = Uri.parse(_initialFollowedWorksUrl);
    var importedCount = 0;

    // フォロー上限が大きいためページ数を無制限にはしない。
    // 通常のページサイズを大幅に超える500ページを安全弁とする。
    for (var page = 0; page < 500; page++) {
      if (!seenPageUrls.add(currentUrl)) break;

      final response = await _fetchPage(currentUrl, cookieHeader);
      if (response.statusCode >= 400 || response.statusCode <= 0) break;

      final finalUri = response.realUri;
      if (finalUri.path.startsWith('/auth/login') ||
          finalUri.path == '/login') {
        throw const KakuyomuSessionExpiredException();
      }

      final body = response.body;
      if (body == null || body.isEmpty) break;

      final parsed = _parser.parse(body, baseUri: finalUri);
      if (parsed.isGuestPage) {
        throw const KakuyomuSessionExpiredException();
      }

      for (final entry in parsed.entries) {
        if (!seenWorkIds.add(entry.workId)) continue;

        final wasInLibrary = await _db.isInLibrary(source, entry.workId);
        final existingNovel = await _db.getNovel(source, entry.workId);

        // 一覧ページ由来の最小メタデータで、既存の詳細メタデータを
        // null上書きしない。未登録作品だけ最小レコードを作成する。
        if (existingNovel == null) {
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

        // 読書履歴は付加同期。取得失敗でもフォロー同期を継続する。
        await _syncRemoteReadingProgress(entry.workId);
      }

      final next = parsed.nextPageUrl;
      if (next == null) break;
      currentUrl = next;
    }

    return importedCount;
  }

  Future<void> _syncRemoteReadingProgress(String workId) async {
    final fetchState = _fetchRemoteReadingState;
    if (fetchState == null) return;

    try {
      final state = await fetchState(workId);
      final remoteEpisodeId = state.episodeId;
      if (!state.isAvailable || remoteEpisodeId == null) return;

      var episodes = await _db.getEpisodes(source, workId);
      if (episodes.isEmpty && _episodeListResolver != null) {
        episodes = await _episodeListResolver(workId);
        await _db.upsertEpisodes(
          episodes
              .map(
                (episode) => EpisodeListEntriesCompanion(
                  source: Value(source),
                  workId: Value(workId),
                  episodeId: Value(episode.index ?? 0),
                  subtitle: Value(episode.subtitle ?? ''),
                  url: Value(episode.url ?? ''),
                  publishedAt: Value(episode.update ?? ''),
                  revisedAt: Value(episode.revised ?? ''),
                ),
              )
              .toList(),
        );
      }

      final localEpisode = episodes.where((episode) {
        final url = episode.url;
        return url != null &&
            extractKakuyomuEpisodeId(workId: workId, url: url) ==
                remoteEpisodeId;
      }).firstOrNull;
      final localEpisodeIndex = localEpisode?.index;
      if (localEpisodeIndex == null || localEpisodeIndex < 1) return;

      await _db.addToHistory(
        ReadingHistoryCompanion(
          source: Value(source),
          workId: Value(workId),
          lastEpisodeId: Value(localEpisodeIndex),
        ),
      );
    } on Exception {
      // 履歴同期失敗はローカル読書・ライブラリ同期へ影響させない。
    }
  }

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) {
    final operation = _followWork;
    return operation == null
        ? Future<AccountSyncOutcome>.value(AccountSyncOutcome.failed)
        : operation(workId);
  }

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) {
    final operation = _unfollowWork;
    return operation == null
        ? Future<AccountSyncOutcome>.value(AccountSyncOutcome.failed)
        : operation(workId);
  }

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
    String? position,
  }) async {
    // Novelty は現在エピソードを先頭から開くため、詳細段落位置が無い場合は
    // 現行カクヨムviewerが同じ状態で使う :root を送る。
    final remotePosition = position ?? ':root';

    final resolver = _episodeUrlResolver;
    final episodeUrl = resolver != null
        ? await resolver(workId, episode)
        : await _db.getEpisodeUrl(source, workId, episode);
    if (episodeUrl == null || episodeUrl.isEmpty) return false;

    final remoteEpisodeId = extractKakuyomuEpisodeId(
      workId: workId,
      url: episodeUrl,
    );
    if (remoteEpisodeId == null) return false;

    final operation = _pushReadingProgress;
    if (operation == null) return false;
    return operation(
      workId: workId,
      episodeId: remoteEpisodeId,
      position: remotePosition,
    );
  }
}
