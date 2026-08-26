import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/models/estar_session_cookie.dart';
import 'package:novelty/repositories/estar_session_repository.dart';
import 'package:riverpod/riverpod.dart';

final _estarWebUris = <WebUri>[
  WebUri('https://estar.jp/'),
  WebUri('https://auth.estar.jp/'),
];

/// テスト時にWebViewのCookie取得を差し替えるためのコールバック。
typedef EstarWebCookieReader = Future<List<Cookie>> Function(WebUri url);

/// エブリスタWebView Cookieサービスのプロバイダー。
final estarWebCookieServiceProvider = Provider<EstarWebCookieService>(
  (ref) => EstarWebCookieService(
    sessionRepository: ref.watch(estarSessionRepositoryProvider),
  ),
);

/// WebViewとSecure Storageの間でエブリスタCookieを移送するサービス。
class EstarWebCookieService {
  /// コンストラクタ。
  EstarWebCookieService({
    required EstarSessionRepository sessionRepository,
    CookieManager? cookieManager,
    EstarWebCookieReader? cookieReader,
  }) : _sessionRepository = sessionRepository,
       _cookieManager = cookieManager,
       _cookieReader = cookieReader;

  final EstarSessionRepository _sessionRepository;
  CookieManager? _cookieManager;
  final EstarWebCookieReader? _cookieReader;

  CookieManager get _manager => _cookieManager ??= CookieManager.instance();

  /// 保存済みCookieを対応する公式ホストのWebViewへ復元する。
  Future<void> restoreToWebView() async {
    final cookies = await _sessionRepository.getCookies();
    for (final cookie in cookies) {
      final host = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
      await _manager.setCookie(
        url: WebUri('https://$host/'),
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

  /// 両公式ホストのWebView Cookieを、名前を限定せず保存する。
  Future<List<EstarSessionCookie>> captureFromWebView() async {
    final byIdentity = <String, EstarSessionCookie>{};
    for (final url in _estarWebUris) {
      final cookies = await _readCookies(url);
      for (final cookie in cookies) {
        final sessionCookie = EstarSessionCookie(
          name: cookie.name,
          value: cookie.value.toString(),
          domain: cookie.domain ?? url.host,
          path: cookie.path ?? '/',
          expiresDate: cookie.expiresDate,
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
        );
        if (!sessionCookie.belongsToEstar || sessionCookie.isExpired) continue;
        final key =
            '${sessionCookie.domain}\u0000'
            '${sessionCookie.path}\u0000${sessionCookie.name}';
        byIdentity[key] = sessionCookie;
      }
    }

    final cookies = byIdentity.values.toList(growable: false);
    await _sessionRepository.saveCookies(cookies);
    return cookies;
  }

  /// WebViewに残るエブリスタ配下のCookieを削除する。
  Future<void> clearWebViewCookies() async {
    final deleted = <String>{};
    for (final url in _estarWebUris) {
      final cookies = await _readCookies(url);
      for (final cookie in cookies) {
        final domain = cookie.domain ?? url.host;
        final candidate = EstarSessionCookie(
          name: cookie.name,
          value: cookie.value.toString(),
          domain: domain,
          path: cookie.path ?? '/',
        );
        if (!candidate.belongsToEstar) continue;
        final key = '$domain\u0000${candidate.path}\u0000${candidate.name}';
        if (!deleted.add(key)) continue;
        await _manager.deleteCookie(
          url: url,
          name: candidate.name,
          domain: domain,
          path: candidate.path,
        );
      }
    }
  }

  Future<List<Cookie>> _readCookies(WebUri url) {
    final reader = _cookieReader;
    return reader == null ? _manager.getCookies(url: url) : reader(url);
  }
}
