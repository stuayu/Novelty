import 'package:dio/dio.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
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

/// テスト時にviewer履歴HTTP通信を差し替えるためのコールバック。
typedef KakuyomuReadingProgressTransport =
    Future<KakuyomuReadingProgressResponse> Function(
      KakuyomuReadingProgressRequest request,
    );

/// カクヨム読書履歴同期サービスのProvider。
final kakuyomuReadingProgressServiceProvider =
    Provider<KakuyomuReadingProgressService>((ref) {
      return KakuyomuReadingProgressService(
        sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
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
  }) : _sessionRepository = sessionRepository,
       _dio = dio ?? Dio(),
       _transport = transport;

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;
  final KakuyomuReadingProgressTransport? _transport;

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
}
