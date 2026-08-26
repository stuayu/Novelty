import 'package:novelty/repositories/estar_session_repository.dart';
import 'package:novelty/services/estar_web_cookie_service.dart';
import 'package:novelty/utils/estar_webview_support.dart';
import 'package:riverpod/riverpod.dart';

/// エブリスタ公式ログイン画面がログイン完了URLへ遷移したか判定する。
bool isEstarLoginCompleteUrl(Uri? url) {
  if (url == null || url.scheme != 'https') return false;

  final host = url.host.toLowerCase();
  final isEstarHost = host == 'estar.jp' || host.endsWith('.estar.jp');
  return isEstarHost && url.path == '/app/login_complete';
}

/// ログイン完了URLの場合だけWebView Cookieを取得・保存する。
Future<bool> captureEstarLoginIfCompleted(
  Uri? url,
  EstarWebCookieService webCookieService,
) async {
  if (!isEstarLoginCompleteUrl(url)) return false;
  return (await webCookieService.captureFromWebView()).isNotEmpty;
}

/// エブリスタ認証サービスのプロバイダー。
final estarAuthServiceProvider = Provider<EstarAuthService>(
  (ref) => EstarAuthService(
    sessionRepository: ref.watch(estarSessionRepositoryProvider),
    webCookieService: ref.watch(estarWebCookieServiceProvider),
  ),
);

/// 保存済みエブリスタセッションの判定と破棄を担当するサービス。
class EstarAuthService {
  /// コンストラクタ。
  EstarAuthService({
    required EstarSessionRepository sessionRepository,
    EstarWebCookieService? webCookieService,
  }) : _sessionRepository = sessionRepository,
       _webCookieService = webCookieService;

  final EstarSessionRepository _sessionRepository;
  final EstarWebCookieService? _webCookieService;

  /// 完了URLで保存した有効なCookieが残っているか確認する。
  ///
  /// ログイン済み専用HTTPエンドポイントは未確認のため、通信による推測判定はしない。
  Future<bool> isSessionValid() => _sessionRepository.hasCookies();

  /// NoveltyとWebViewに保存されたエブリスタ認証情報を破棄する。
  Future<void> logout() async {
    try {
      if (isEstarWebViewSupported) {
        final webCookieService =
            _webCookieService ??
            EstarWebCookieService(sessionRepository: _sessionRepository);
        await webCookieService.clearWebViewCookies();
      }
    } finally {
      await _sessionRepository.clearAll();
    }
  }
}
