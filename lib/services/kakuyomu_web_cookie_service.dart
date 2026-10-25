import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/models/kakuyomu_session_cookie.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:riverpod/riverpod.dart';

final _kakuyomuWebUri = WebUri('https://kakuyomu.jp/');

/// WebViewのCookieを取得する処理。
typedef KakuyomuWebCookieReader = Future<List<Cookie>> Function(WebUri url);

/// カクヨムWebView Cookieサービスのプロバイダー。
final kakuyomuWebCookieServiceProvider = Provider<KakuyomuWebCookieService>(
  (ref) => KakuyomuWebCookieService(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
  ),
);

/// WebViewとSecure Storageの間でカクヨムCookieを移送するサービス。
class KakuyomuWebCookieService {
  /// コンストラクタ。
  KakuyomuWebCookieService({
    required KakuyomuSessionRepository sessionRepository,
    CookieManager? cookieManager,
    KakuyomuWebCookieReader? cookieReader,
  }) : _sessionRepository = sessionRepository,
       _cookieManager = cookieManager,
       _cookieReader = cookieReader;

  final KakuyomuSessionRepository _sessionRepository;
  CookieManager? _cookieManager;
  final KakuyomuWebCookieReader? _cookieReader;

  CookieManager get _manager => _cookieManager ??= CookieManager.instance();

  /// Secure StorageのCookieをカクヨムWebViewへ復元する。
  Future<void> restoreToWebView() async {
    final cookies = await _sessionRepository.getCookies();
    for (final cookie in cookies) {
      await _manager.setCookie(
        url: _kakuyomuWebUri,
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        expiresDate: cookie.expiresDate,
        isSecure: cookie.isSecure,
        isHttpOnly: cookie.isHttpOnly,
      );
    }
  }

  /// WebViewから有効なカクヨムCookieを取得して保存する。
  Future<List<KakuyomuSessionCookie>> captureFromWebView() async {
    final cookies = await _readCookies();
    final sessionCookies = cookies
        .map(
          (cookie) => KakuyomuSessionCookie(
            name: cookie.name,
            value: cookie.value.toString(),
            domain: cookie.domain ?? 'kakuyomu.jp',
            path: cookie.path ?? '/',
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure,
            isHttpOnly: cookie.isHttpOnly,
          ),
        )
        .where((cookie) => cookie.belongsToKakuyomu && !cookie.isExpired)
        .toList(growable: false);

    if (sessionCookies.isNotEmpty) {
      await _sessionRepository.saveCookies(sessionCookies);
    }
    return sessionCookies;
  }

  /// WebViewに残るカクヨムCookieを削除する。
  Future<void> clearWebViewCookies() async {
    final cookies = await _readCookies();
    for (final cookie in cookies) {
      final domain = cookie.domain ?? 'kakuyomu.jp';
      final candidate = KakuyomuSessionCookie(
        name: cookie.name,
        value: cookie.value.toString(),
        domain: domain,
        path: cookie.path ?? '/',
        expiresDate: cookie.expiresDate,
      );
      if (!candidate.belongsToKakuyomu) continue;

      await _manager.deleteCookie(
        url: _kakuyomuWebUri,
        name: cookie.name,
        domain: domain,
        path: cookie.path ?? '/',
      );
    }
  }

  Future<List<Cookie>> _readCookies() =>
      _cookieReader?.call(_kakuyomuWebUri) ??
      _manager.getCookies(url: _kakuyomuWebUri);
}
