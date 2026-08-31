import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

final _numericIdPattern = RegExp(r'^\d+$');
final _positionPattern = RegExp(r'^(?::root|#p[0-9]+)$');

/// カクヨムviewerの読書履歴HTTPリクエスト。
class KakuyomuReadingProgressRequest {
  /// コンストラクタ。
  const KakuyomuReadingProgressRequest({
    required this.url,
    required this.position,
    required this.cookieHeader,
  });

  /// viewer HTML の `data-viewer-history-path` と同形のURL。
  final Uri url;

  /// `:root` または `#pN` 形式の読書位置。
  final String position;

  /// Secure Storageから構築したCookieヘッダー。
  final String cookieHeader;
}

/// カクヨムviewerの読書履歴HTTPレスポンス。
class KakuyomuReadingProgressResponse {
  /// コンストラクタ。
  const KakuyomuReadingProgressResponse({required this.statusCode});

  /// HTTPステータスコード。
  final int statusCode;
}

/// カクヨム作品ページから取得したリモート読書位置。
class KakuyomuRemoteReadingState {
  /// コンストラクタ。
  const KakuyomuRemoteReadingState({
    required this.isAvailable,
    this.episodeId,
  });

  /// 認証済み作品ページを取得・解析できたか。
  final bool isAvailable;

  /// 最後に読んだリモートエピソードID。履歴なしの場合はnull。
  final String? episodeId;
}

/// リモート読書位置取得のHTTPレスポンス。
class KakuyomuRemoteReadingStateHttpResponse {
  /// コンストラクタ。
  const KakuyomuRemoteReadingStateHttpResponse({
    required this.statusCode,
    required this.realUri,
    this.body,
  });

  /// HTTPステータスコード。
  final int statusCode;

  /// リダイレクト後の最終URL。
  final Uri realUri;

  /// 作品ページ本文。
  final String? body;
}

/// テスト時にviewer履歴HTTP通信を差し替えるためのコールバック。
typedef KakuyomuReadingProgressTransport =
    Future<KakuyomuReadingProgressResponse> Function(
      KakuyomuReadingProgressRequest request,
    );

/// リモート読書位置取得をテスト時に差し替えるコールバック。
typedef KakuyomuRemoteReadingStateFetcher =
    Future<KakuyomuRemoteReadingStateHttpResponse> Function(
      Uri url,
      String cookieHeader,
    );

/// カクヨム読書履歴同期サービスのProvider。
final kakuyomuReadingProgressServiceProvider =
    Provider<KakuyomuReadingProgressService>((ref) {
      return KakuyomuReadingProgressService(
        sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
        rateLimiter: ref.watch(
          siteRateLimiterProvider(NovelSource.kakuyomu),
        ),
      );
    });

/// カクヨムの「続きから読む」位置をネイティブHTTPで記録するサービス。
///
/// 現行エピソードviewerが実際に行う通信を再現し、WebViewやブラウザ実行環境は
/// 使用しない。viewerは本文要素の `data-viewer-history-path` が示す
/// `/works/{workId}/episodes/{episodeId}/history` へ、`position` をPOSTする。
class KakuyomuReadingProgressService {
  /// コンストラクタ。
  KakuyomuReadingProgressService({
    required KakuyomuSessionRepository sessionRepository,
    Dio? dio,
    KakuyomuReadingProgressTransport? transport,
    KakuyomuRemoteReadingStateFetcher? remoteStateFetcher,
    RequestRateLimiter? rateLimiter,
  }) : _sessionRepository = sessionRepository,
       _dio = _createRateLimitedDio(
         dio,
         rateLimiter ??
             RequestRateLimiter(interval: const Duration(seconds: 1)),
       ),
       _transport = transport,
       _remoteStateFetcher = remoteStateFetcher;

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;
  final KakuyomuReadingProgressTransport? _transport;
  final KakuyomuRemoteReadingStateFetcher? _remoteStateFetcher;

  static Dio _createRateLimitedDio(
    Dio? dio,
    RequestRateLimiter rateLimiter,
  ) {
    return dio == null
        ? createNoveltyDio(rateLimiter: rateLimiter)
        : attachNoveltyRateLimiter(dio, rateLimiter);
  }

  /// 指定したremote episodeの読書位置を記録する。
  ///
  /// [position] はviewer実装で確認済みの `:root` または `#pN` のみ許可する。
  /// 保存済みCookieが無い場合や通信失敗時は `false` を返し、読書UIへ例外を
  /// 伝播させない。
  Future<bool> record({
    required String workId,
    required String episodeId,
    required String position,
  }) async {
    if (!_numericIdPattern.hasMatch(workId) ||
        !_numericIdPattern.hasMatch(episodeId) ||
        !_positionPattern.hasMatch(position)) {
      return false;
    }

    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) return false;

    final url = Uri.https(
      'kakuyomu.jp',
      '/works/$workId/episodes/$episodeId/history',
    );
    final request = KakuyomuReadingProgressRequest(
      url: url,
      position: position,
      cookieHeader: cookieHeader,
    );

    try {
      final override = _transport;
      final response = override != null
          ? await override(request)
          : await _post(request, workId: workId, episodeId: episodeId);
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    }
  }

  /// カクヨム作品ページから最後に読んだリモートエピソードを取得する。
  ///
  /// 履歴なしは取得成功（[KakuyomuRemoteReadingState.isAvailable]がtrue）とし、
  /// 認証失敗・通信失敗・解析失敗は取得不能として返す。
  Future<KakuyomuRemoteReadingState> fetchRemoteState(String workId) async {
    if (!_numericIdPattern.hasMatch(workId)) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }

    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }

    final url = Uri.https('kakuyomu.jp', '/works/$workId');
    try {
      final override = _remoteStateFetcher;
      final response = override != null
          ? await override(url, cookieHeader)
          : await _fetchRemoteState(url, cookieHeader);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const KakuyomuRemoteReadingState(isAvailable: false);
      }
      if (!_isTrustedKakuyomuWorkUri(response.realUri, workId)) {
        return const KakuyomuRemoteReadingState(isAvailable: false);
      }

      final body = response.body;
      if (body == null || body.isEmpty) {
        return const KakuyomuRemoteReadingState(isAvailable: false);
      }
      return _parseRemoteState(body, workId);
    } on Exception {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
  }

  Future<KakuyomuReadingProgressResponse> _post(
    KakuyomuReadingProgressRequest request, {
    required String workId,
    required String episodeId,
  }) async {
    final response = await _dio.post<Object?>(
      request.url.toString(),
      data: <String, Object?>{'position': request.position},
      options: Options(
        headers: <String, Object>{
          'Cookie': request.cookieHeader,
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': 'https://kakuyomu.jp',
          'Referer': 'https://kakuyomu.jp/works/$workId/episodes/$episodeId',
        },
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 600,
        responseType: ResponseType.plain,
      ),
    );

    return KakuyomuReadingProgressResponse(
      statusCode: response.statusCode ?? 0,
    );
  }

  Future<KakuyomuRemoteReadingStateHttpResponse> _fetchRemoteState(
    Uri url,
    String cookieHeader,
  ) async {
    final response = await _dio.get<String>(
      url.toString(),
      options: Options(
        headers: <String, Object>{
          'Cookie': cookieHeader,
          'User-Agent': noveltyUserAgent,
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 600,
        responseType: ResponseType.plain,
      ),
    );
    return KakuyomuRemoteReadingStateHttpResponse(
      statusCode: response.statusCode ?? 0,
      realUri: response.realUri,
      body: response.data,
    );
  }

  KakuyomuRemoteReadingState _parseRemoteState(String body, String workId) {
    final script = html_parser
        .parse(body)
        .querySelector('script#__NEXT_DATA__')
        ?.text;
    if (script == null || script.isEmpty) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }

    final json = jsonDecode(script);
    if (json is! Map<String, dynamic>) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    final props = json['props'];
    final pageProps = props is Map<String, dynamic> ? props['pageProps'] : null;
    final apollo = pageProps is Map<String, dynamic>
        ? pageProps['__APOLLO_STATE__']
        : null;
    if (apollo is! Map<String, dynamic>) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }

    final work = apollo['Work:$workId'];
    if (work is! Map<String, dynamic>) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    final history = work['visitorReadingHistory'];
    if (history == null) {
      return const KakuyomuRemoteReadingState(isAvailable: true);
    }
    if (history is! Map<String, dynamic>) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    final historyRef = history['__ref'];
    final historyEntity = historyRef is String ? apollo[historyRef] : null;
    if (historyEntity is! Map<String, dynamic>) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    final episode = historyEntity['episodeUnion'];
    final episodeRef = episode is Map<String, dynamic>
        ? episode['__ref']
        : null;
    if (episodeRef is! String || !episodeRef.startsWith('Episode:')) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    final episodeId = episodeRef.substring('Episode:'.length);
    if (!_numericIdPattern.hasMatch(episodeId)) {
      return const KakuyomuRemoteReadingState(isAvailable: false);
    }
    return KakuyomuRemoteReadingState(isAvailable: true, episodeId: episodeId);
  }

  bool _isTrustedKakuyomuWorkUri(Uri uri, String workId) {
    return uri.scheme == 'https' &&
        uri.host == 'kakuyomu.jp' &&
        uri.path == '/works/$workId';
  }
}
