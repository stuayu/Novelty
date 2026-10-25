import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';
import 'package:novelty/utils/kakuyomu_webview_support.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

const _kakuyomuBaseUrl = 'https://kakuyomu.jp';
const _kakuyomuSessionCheckUrl = '$_kakuyomuBaseUrl/my';

/// 保存済みカクヨムセッションの検証結果。
enum KakuyomuSessionValidity {
  /// ログイン済みページを確認した。
  valid,

  /// ログイン画面または未ログイン状態を確認した。
  invalid,

  /// 通信障害などで状態を確認できなかった。
  unavailable,
}

class _KakuyomuSessionCheckResult {
  const _KakuyomuSessionCheckResult({
    this.response,
    this.isLoginRedirect = false,
  });

  final Response<String>? response;
  final bool isLoginRedirect;
}

/// `/my` の HTML がログイン済み状態を示しているか判定する。
///
/// ログイン導線が無いだけの汎用200ページを成功扱いせず、カクヨムが実際に
/// ログイン済みページへ出している `data-is-guest="0"` または
/// `isSignedInUser` マーカーを確認する。
bool kakuyomuDashboardIndicatesLoggedIn(String html) {
  if (html.isEmpty) return false;

  final document = html_parser.parse(html);
  final hasLoginLink = document.querySelectorAll('a').any((anchor) {
    final href = anchor.attributes['href'];
    if (href == null) return false;
    return href == '/auth/login' || href == '/login';
  });
  if (hasLoginLink) return false;

  final htmlElement = document.querySelector('html');
  final explicitlyNotGuest = htmlElement?.attributes['data-is-guest'] == '0';
  final hasSignedInMarker = document.querySelector('.isSignedInUser') != null;

  return explicitlyNotGuest || hasSignedInMarker;
}

/// カクヨム認証サービスのプロバイダー。
final kakuyomuAuthServiceProvider = Provider<KakuyomuAuthService>((ref) {
  return KakuyomuAuthService(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
    rateLimiter: ref.watch(
      siteRateLimiterProvider(NovelSource.kakuyomu),
    ),
  );
});

/// 保存済みカクヨムセッションの有効性確認と破棄を担当するサービス。
class KakuyomuAuthService {
  /// コンストラクタ。
  KakuyomuAuthService({
    required KakuyomuSessionRepository sessionRepository,
    Dio? dio,
    RequestRateLimiter? rateLimiter,
  }) : _sessionRepository = sessionRepository,
       _dio =
           dio ??
           createNoveltyDio(
             rateLimiter: rateLimiter,
           );

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;

  /// 保存済み Cookie がログイン済みセッションとして有効か確認する。
  ///
  /// カクヨムの `/my` は未ログインでも表示できるため、HTTP ステータスだけでなく
  /// ログイン済み固有マーカーも確認する。
  Future<bool> isSessionValid() async {
    return await validateSessionStatus() == KakuyomuSessionValidity.valid;
  }

  /// 認証切れと一時的な確認不能を分けて保存済みセッションを検証する。
  Future<KakuyomuSessionValidity> validateSessionStatus({
    String? cookieHeader,
  }) async {
    final requestCookieHeader =
        cookieHeader ?? await _sessionRepository.buildCookieHeader();
    if (requestCookieHeader == null || requestCookieHeader.isEmpty) {
      return KakuyomuSessionValidity.invalid;
    }

    try {
      final result = await _fetchSessionCheckPage(requestCookieHeader);
      if (result == null) return KakuyomuSessionValidity.unavailable;
      if (result.isLoginRedirect) return KakuyomuSessionValidity.invalid;
      final response = result.response;
      if (response == null) return KakuyomuSessionValidity.unavailable;
      if (response.statusCode == 401 || _isLoginPage(response.realUri)) {
        return KakuyomuSessionValidity.invalid;
      }
      if (response.statusCode != 200) {
        return KakuyomuSessionValidity.unavailable;
      }

      final body = response.data;
      if (body == null || body.isEmpty) {
        return KakuyomuSessionValidity.unavailable;
      }
      if (_kakuyomuDashboardExplicitlyIndicatesLoggedOut(body)) {
        return KakuyomuSessionValidity.invalid;
      }
      return kakuyomuDashboardIndicatesLoggedIn(body)
          ? KakuyomuSessionValidity.valid
          : KakuyomuSessionValidity.unavailable;
    } on DioException catch (error) {
      return error.response?.statusCode == 401
          ? KakuyomuSessionValidity.invalid
          : KakuyomuSessionValidity.unavailable;
    } on Exception {
      return KakuyomuSessionValidity.unavailable;
    }
  }

  Future<_KakuyomuSessionCheckResult?> _fetchSessionCheckPage(
    String cookieHeader,
  ) async {
    var current = Uri.parse(_kakuyomuSessionCheckUrl);
    final visited = <Uri>{};
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!isTrustedKakuyomuUri(current) || !visited.add(current)) return null;

      final response = await _dio.get<String>(
        current.toString(),
        options: Options(
          headers: <String, Object>{
            'Cookie': cookieHeader,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/143.0.0.0 Safari/537.36',
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );

      if (!isTrustedKakuyomuUri(response.realUri)) return null;
      if (_isLoginPage(response.realUri)) {
        return const _KakuyomuSessionCheckResult(isLoginRedirect: true);
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 300 || statusCode >= 400) {
        return _KakuyomuSessionCheckResult(response: response);
      }

      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
      final target = response.realUri.resolve(location);
      if (_isLoginPage(target)) {
        return const _KakuyomuSessionCheckResult(isLoginRedirect: true);
      }
      if (!isTrustedKakuyomuUri(target)) return null;
      if (redirects == 5) return null;
      current = target;
    }
    return null;
  }

  bool _kakuyomuDashboardExplicitlyIndicatesLoggedOut(String html) {
    final document = html_parser.parse(html);
    final hasLoginLink = document.querySelectorAll('a').any((anchor) {
      final href = anchor.attributes['href'];
      return href == '/auth/login' || href == '/login';
    });
    final isGuest =
        document.querySelector('html')?.attributes['data-is-guest'] == '1';
    return hasLoginLink || isGuest;
  }

  bool _isLoginPage(Uri uri) =>
      isTrustedKakuyomuUri(uri) &&
      (uri.path.startsWith('/auth/login') || uri.path.startsWith('/login'));

  /// Novelty と WebView に保存されたカクヨム認証情報を破棄する。
  Future<void> logout() async {
    if (isKakuyomuWebViewSupported) {
      final webCookieService = KakuyomuWebCookieService(
        sessionRepository: _sessionRepository,
      );
      await webCookieService.clearWebViewCookies();
    }
    await _sessionRepository.clearAll();
  }
}
