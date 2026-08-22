import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/models/kakuyomu_session_cookie.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:riverpod/riverpod.dart';

final _kakuyomuWebUri = WebUri('https://kakuyomu.jp/');

/// WebView Cookie と Secure Storage の同期サービス。
final kakuyomuWebCookieServiceProvider = Provider<KakuyomuWebCookieService>(
  (ref) => KakuyomuWebCookieService(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
  ),
);

/// カクヨム配下の Cookie だけを WebView と永続ストレージ間で同期する。
class KakuyomuWebCookieService {
  /// コンストラクタ。
  KakuyomuWebCookieService({
    required KakuyomuSessionRepository sessionRepository,
    CookieManager? cookieManager,
  }) : _sessionRepository = sessionRepository,
       _cookieManager = cookieManager ?? CookieManager.instance();

  final KakuyomuSessionRepository _sessionRepository;
  final CookieManager _cookieManager;

  /// Secure Storage に保存済みの Cookie を WebView へ復元する。
  Future<void> restoreToWebView() async {
    final cookies = await _sessionRepository.getCookies();
    for (final cookie in cookies) {
      await _cookieManager.setCookie(
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

  /// WebView に存在するカクヨム Cookie を Secure Storage へ保存する。
  Future<List<KakuyomuSessionCookie>> captureFromWebView() async {
    final cookies = await _cookieManager.getAllCookies();
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

    await _sessionRepository.saveCookies(sessionCookies);
    return sessionCookies;
  }

  /// WebView 内のカクヨム Cookie だけを削除する。
  Future<void> clearWebViewCookies() async {
    final cookies = await _cookieManager.getAllCookies();
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

      await _cookieManager.deleteCookie(
        url: _kakuyomuWebUri,
        name: cookie.name,
        domain: domain,
        path: cookie.path ?? '/',
      );
    }
  }
}
