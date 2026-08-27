import 'package:dio/dio.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/services/hameln_web_cookie_service.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

final _configuration = FormPostAuthConfiguration(
  loginUri: Uri.parse('https://syosetu.org/?mode=login'),
  postUri: Uri.parse('https://syosetu.org/?mode=login').resolve('./'),
  accountField: 'id',
  passwordField: 'pass',
  hiddenFields: const ['redirect_mode'],
  staticFields: const {'mode': 'login_entry_end'},
);

/// ハーメルン認証サービスのプロバイダー。
final hamelnAuthServiceProvider = Provider<HamelnAuthService>((ref) {
  return HamelnAuthService(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.hameln),
    ),
    webCookieService: ref.watch(hamelnWebCookieServiceProvider),
    rateLimiter: ref.watch(siteRateLimiterProvider(NovelSource.hameln)),
  );
});

/// ログイン済みのときだけ発行されるCookie名。
///
/// 実機のログイン済みブラウザで確認した値。`uaid` や `cf_clearance` は
/// 未ログインでも付くため、ログインの判定には使わない。
const _loginCookieNames = <String>{'autologin', 'sson'};

/// ハーメルンのフォームPOSTログインとセッション管理。
class HamelnAuthService {
  /// コンストラクタ。
  HamelnAuthService({
    required FormAuthSessionRepository sessionRepository,
    HamelnWebCookieService? webCookieService,
    Dio? dio,
    RequestRateLimiter? rateLimiter,
  }) : _delegate = FormPostAuthService(
         sessionRepository: sessionRepository,
         dio: dio ?? createNoveltyDio(rateLimiter: rateLimiter),
         configuration: _configuration,
       ),
       _sessionRepository = sessionRepository,
       _webCookieService = webCookieService;

  final FormPostAuthService _delegate;
  final FormAuthSessionRepository _sessionRepository;
  final HamelnWebCookieService? _webCookieService;

  /// ユーザーIDとパスワードでログインする。
  Future<FormAuthLoginResult> login({
    required String id,
    required String password,
  }) => _delegate.login(accountId: id, password: password);

  /// 保存済みセッションが有効か確認する。
  ///
  /// ハーメルンはCloudflareのBot対策下にあり、素のHTTPでページを取得すると
  /// ログイン状態にかかわらず403とチャレンジページが返る。そのため
  /// [FormPostAuthService.isSessionValid] のようなHTTPでの確認はできない。
  /// 代わりに、WebViewでのログイン時に保存したCookieへ
  /// ログインセッション用のCookieが含まれるかで判定する。
  Future<bool> isSessionValid() async {
    final cookies = await _sessionRepository.getCookies();
    return cookies.keys.any(_loginCookieNames.contains);
  }

  /// 保存済み認証情報を削除する。
  Future<void> logout() async {
    try {
      final webCookieService = _webCookieService;
      if (webCookieService != null) {
        await webCookieService.clearWebViewCookies();
      }
    } finally {
      await _delegate.logout();
    }
  }
}
