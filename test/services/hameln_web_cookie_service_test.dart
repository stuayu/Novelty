import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/hameln_web_cookie_service.dart';
import 'package:novelty/sites/novel_source.dart';

class _MemoryRepository extends FormAuthSessionRepository {
  _MemoryRepository() : super(source: NovelSource.hameln);

  Map<String, String> cookies = {
    'session': 'saved-session',
  };

  @override
  Future<Map<String, String>> getCookies() async => cookies;

  @override
  Future<String?> getAccountId() async => null;

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    this.cookies = Map.of(cookies);
  }

  @override
  Future<void> clearAll() async => cookies = {};
}

void main() {
  test('WebViewのハーメルン配下Cookieを名前で限定せず保存する', () async {
    final repository = _MemoryRepository();
    final service = HamelnWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async => [
        Cookie(
          name: 'cf_clearance',
          value: 'cloudflare-token',
          domain: '.syosetu.org',
          path: '/',
        ),
        Cookie(
          name: 'opaque_session',
          value: 'session-token',
          domain: 'syosetu.org',
          path: '/',
        ),
      ],
    );

    final cookies = await service.captureFromWebView();

    expect(cookies, {
      'cf_clearance': 'cloudflare-token',
      'opaque_session': 'session-token',
    });
    expect(repository.cookies, cookies);
  });

  test('保存済みCookieをWebViewへ復元する', () async {
    final repository = _MemoryRepository();
    final restored = <Cookie>[];
    final service = HamelnWebCookieService(
      sessionRepository: repository,
      cookieSetter: (cookie) async {
        restored.add(cookie);
      },
    );

    await service.restoreToWebView();

    expect(restored.single.name, 'session');
    expect(restored.single.value, 'saved-session');
  });

  test('WebViewからハーメルン配下の全Cookieを削除する', () async {
    final repository = _MemoryRepository();
    final deleted = <String>[];
    final service = HamelnWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async => [
        Cookie(
          name: 'cf_clearance',
          value: 'cloudflare-token',
          domain: '.syosetu.org',
          path: '/',
        ),
        Cookie(
          name: 'opaque_session',
          value: 'session-token',
          domain: 'syosetu.org',
          path: '/',
        ),
      ],
      cookieDeleter: (cookie) async {
        deleted.add(cookie.name);
      },
    );

    await service.clearWebViewCookies();

    expect(deleted, ['cf_clearance', 'opaque_session']);
  });
}
