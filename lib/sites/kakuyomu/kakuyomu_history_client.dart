import 'package:dio/dio.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_history_parser.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_session_exception.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';
import 'package:riverpod/riverpod.dart';

export 'kakuyomu_session_exception.dart';

const _readingHistoriesUrl = 'https://kakuyomu.jp/my/antenna/reading_histories';

/// カクヨム閲覧履歴HTTP取得結果。
class KakuyomuHistoryHttpResponse {
  /// コンストラクタ。
  const KakuyomuHistoryHttpResponse({
    required this.statusCode,
    required this.realUri,
    this.body,
  });

  /// HTTPステータスコード。
  final int statusCode;

  /// リダイレクト後のURL。
  final Uri realUri;

  /// HTML本文。
  final String? body;
}

/// 閲覧履歴ページHTTP取得差し替え。
typedef KakuyomuHistoryPageFetcher =
    Future<KakuyomuHistoryHttpResponse> Function(
      Uri url,
      String cookieHeader,
    );

/// カクヨム閲覧履歴クライアント。
class KakuyomuHistoryClient {
  /// コンストラクタ。
  KakuyomuHistoryClient({
    required KakuyomuSessionRepository sessionRepository,
    Dio? dio,
    KakuyomuHistoryParser? parser,
    KakuyomuHistoryPageFetcher? pageFetcher,
  }) : _sessionRepository = sessionRepository,
       _dio = dio ?? Dio(),
       _parser = parser ?? KakuyomuHistoryParser(),
       _pageFetcher = pageFetcher;

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;
  final KakuyomuHistoryParser _parser;
  final KakuyomuHistoryPageFetcher? _pageFetcher;

  /// セッションが失効している場合の例外。
  static const sessionExpired = KakuyomuSessionExpiredException();

  /// すべての閲覧履歴を取得する。
  Future<List<KakuyomuHistoryEntry>> fetchAll() async {
    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) {
      throw sessionExpired;
    }

    final entries = <KakuyomuHistoryEntry>[];
    final seenPages = <Uri>{};
    var url = Uri.parse(_readingHistoriesUrl);
    for (var page = 0; page < 500; page++) {
      if (!seenPages.add(url)) break;
      final response = await _fetchPage(url, cookieHeader);
      if (response.statusCode >= 400 || response.statusCode <= 0) {
        throw StateError('カクヨム閲覧履歴の取得に失敗しました');
      }
      if (_isLoginPage(response.realUri)) throw sessionExpired;

      final body = response.body;
      if (body == null || body.isEmpty) {
        throw StateError('カクヨム閲覧履歴の本文が空です');
      }
      final parsed = _parser.parse(body, baseUri: response.realUri);
      if (parsed.isGuestPage) throw sessionExpired;
      for (final entry in parsed.entries) {
        if (entry.episodeId != null) {
          entries.add(entry);
          continue;
        }
        final resumeUrl = entry.resumeReadingUrl;
        if (resumeUrl == null) continue;
        final resolved = await _fetchPage(resumeUrl, cookieHeader);
        if (_isLoginPage(resolved.realUri)) throw sessionExpired;
        final episodeId = extractKakuyomuEpisodeId(
          workId: entry.workId,
          url: resolved.realUri.toString(),
        );
        if (episodeId == null) continue;
        entries.add(
          KakuyomuHistoryEntry(
            source: entry.source,
            workId: entry.workId,
            episodeId: episodeId,
            resumeReadingUrl: resumeUrl,
            title: entry.title,
            episodeTitle: entry.episodeTitle,
            lastReadAt: entry.lastReadAt,
          ),
        );
      }
      final next = parsed.nextPageUrl;
      if (next == null) break;
      url = next;
    }
    return entries;
  }

  Future<KakuyomuHistoryHttpResponse> _fetchPage(
    Uri url,
    String cookieHeader,
  ) async {
    final override = _pageFetcher;
    if (override != null) return override(url, cookieHeader);
    final response = await _dio.get<String>(
      url.toString(),
      options: Options(
        headers: <String, Object>{
          'Cookie': cookieHeader,
          'User-Agent': 'Mozilla/5.0',
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 600,
        responseType: ResponseType.plain,
      ),
    );
    return KakuyomuHistoryHttpResponse(
      statusCode: response.statusCode ?? 0,
      realUri: response.realUri,
      body: response.data,
    );
  }

  bool _isLoginPage(Uri uri) {
    return uri.host == 'kakuyomu.jp' &&
        (uri.path.startsWith('/auth/login') || uri.path == '/login');
  }
}

/// カクヨム閲覧履歴クライアントのProvider。
final kakuyomuHistoryClientProvider = Provider<KakuyomuHistoryClient>((ref) {
  return KakuyomuHistoryClient(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
  );
});
