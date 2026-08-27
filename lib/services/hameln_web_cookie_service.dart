import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:riverpod/riverpod.dart';

final _hamelnWebUri = WebUri('https://syosetu.org/');

/// WebViewからCookieを読み込む関数。
typedef HamelnWebCookieReader = Future<List<Cookie>> Function(WebUri url);

/// WebViewへCookieを設定する関数。
typedef HamelnWebCookieSetter = Future<void> Function(Cookie cookie);

/// WebViewからCookieを削除する関数。
typedef HamelnWebCookieDeleter = Future<void> Function(Cookie cookie);

/// ハーメルンWebView Cookieサービスのプロバイダー。
final hamelnWebCookieServiceProvider = Provider<HamelnWebCookieService>(
  (ref) => HamelnWebCookieService(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.hameln),
    ),
  ),
);

/// WebViewとSecure Storageの間でハーメルンCookieを移送するサービス。
class HamelnWebCookieService {
  /// コンストラクタ。
  HamelnWebCookieService({
    required FormAuthSessionRepository sessionRepository,
    CookieManager? cookieManager,
    HamelnWebCookieReader? cookieReader,
    HamelnWebCookieSetter? cookieSetter,
    HamelnWebCookieDeleter? cookieDeleter,
  }) : _sessionRepository = sessionRepository,
       _cookieManager = cookieManager,
       _cookieReader = cookieReader,
       _cookieSetter = cookieSetter,
       _cookieDeleter = cookieDeleter;

  final FormAuthSessionRepository _sessionRepository;
  CookieManager? _cookieManager;
  final HamelnWebCookieReader? _cookieReader;
  final HamelnWebCookieSetter? _cookieSetter;
  final HamelnWebCookieDeleter? _cookieDeleter;

  CookieManager get _manager => _cookieManager ??= CookieManager.instance();

  /// 保存済みCookieをハーメルンWebViewへ復元する。
  Future<void> restoreToWebView() async {
    final cookies = await _sessionRepository.getCookies();
    for (final entry in cookies.entries) {
      await _setCookie(
        Cookie(
          name: entry.key,
          value: entry.value,
          domain: _hamelnWebUri.host,
          path: '/',
        ),
      );
    }
  }

  /// WebViewのハーメルン配下にある全Cookieを保存する。
  Future<Map<String, String>> captureFromWebView() async {
    final cookies = await _readCookies();
    final values = <String, String>{};
    for (final cookie in cookies) {
      if (!_belongsToHameln(cookie.domain)) continue;
      values[cookie.name] = cookie.value.toString();
    }

    await _sessionRepository.saveSession(
      accountId: await _sessionRepository.getAccountId() ?? '',
      cookies: values,
    );
    return values;
  }

  /// WebViewに残るハーメルン配下の全Cookieを削除する。
  Future<void> clearWebViewCookies() async {
    for (final cookie in await _readCookies()) {
      if (_belongsToHameln(cookie.domain)) {
        await _deleteCookie(cookie);
      }
    }
  }

  Future<List<Cookie>> _readCookies() {
    final reader = _cookieReader;
    return reader == null
        ? _manager.getCookies(url: _hamelnWebUri)
        : reader(_hamelnWebUri);
  }

  Future<void> _setCookie(Cookie cookie) async {
    final setter = _cookieSetter;
    if (setter != null) {
      await setter(cookie);
      return;
    }
    await _manager.setCookie(
      url: _hamelnWebUri,
      name: cookie.name,
      value: cookie.value.toString(),
      domain: cookie.domain,
      path: cookie.path ?? '/',
      expiresDate: cookie.expiresDate,
      isSecure: cookie.isSecure,
      isHttpOnly: cookie.isHttpOnly,
    );
  }

  Future<void> _deleteCookie(Cookie cookie) async {
    final deleter = _cookieDeleter;
    if (deleter != null) {
      await deleter(cookie);
      return;
    }
    await _manager.deleteCookie(
      url: _hamelnWebUri,
      name: cookie.name,
      domain: cookie.domain ?? _hamelnWebUri.host,
      path: cookie.path ?? '/',
    );
  }

  bool _belongsToHameln(String? domain) {
    final normalized = (domain ?? _hamelnWebUri.host)
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '');
    return normalized == _hamelnWebUri.host ||
        normalized.endsWith('.${_hamelnWebUri.host}');
  }
}
