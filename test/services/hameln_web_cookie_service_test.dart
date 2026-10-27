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

class _SaveCountingRepository extends _MemoryRepository {
  int saveCount = 0;

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    saveCount++;
    await super.saveSession(accountId: accountId, cookies: cookies);
  }
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
      cookieReader: (url) async => [],
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

  test('WebViewにログインCookieがあれば保存済みの古い値で上書きしない', () async {
    final repository = _MemoryRepository()
      ..cookies = {'autologin': 'old', 'sson': 'old'};
    final restored = <Cookie>[];
    final service = HamelnWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async => [
        Cookie(name: 'autologin', value: 'fresh', domain: '.syosetu.org'),
      ],
      cookieSetter: (cookie) async {
        restored.add(cookie);
      },
    );

    await service.restoreToWebView();

    expect(restored, isEmpty);
  });

  test('WebViewが未ログインならCloudflare用Cookie以外を復元する', () async {
    final repository = _MemoryRepository()
      ..cookies = {
        'autologin': 'saved',
        'cf_clearance': 'stale',
        '__cf_bm': 'stale',
        '_cfuvid': 'stale',
      };
    final restored = <Cookie>[];
    final service = HamelnWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async => [
        Cookie(name: 'uaid', value: 'guest', domain: '.syosetu.org'),
      ],
      cookieSetter: (cookie) async {
        restored.add(cookie);
      },
    );

    await service.restoreToWebView();

    expect(restored.map((cookie) => cookie.name), ['autologin']);
  });

  group('refreshSessionFromWebView', () {
    test('WebViewで更新されたログインCookieを保存し直す', () async {
      final repository = _MemoryRepository()
        ..cookies = {'autologin': 'old', 'sson': 'old'};
      final service = HamelnWebCookieService(
        sessionRepository: repository,
        cookieReader: (url) async => [
          Cookie(name: 'autologin', value: 'new', domain: '.syosetu.org'),
          Cookie(name: 'sson', value: 'new', domain: 'syosetu.org'),
          Cookie(name: 'other', value: 'x', domain: 'example.com'),
        ],
      );

      expect(await service.refreshSessionFromWebView(), isTrue);

      expect(repository.cookies, {'autologin': 'new', 'sson': 'new'});
    });

    test('WebViewが未ログイン状態なら保存済みCookieを残す', () async {
      final repository = _MemoryRepository()..cookies = {'autologin': 'saved'};
      final service = HamelnWebCookieService(
        sessionRepository: repository,
        cookieReader: (url) async => [
          Cookie(name: 'uaid', value: 'guest', domain: '.syosetu.org'),
        ],
      );

      expect(await service.refreshSessionFromWebView(), isFalse);

      expect(repository.cookies, {'autologin': 'saved'});
    });

    test('値が変わっていなければ保存しない', () async {
      final repository = _SaveCountingRepository()
        ..cookies = {'autologin': 'same'};
      final service = HamelnWebCookieService(
        sessionRepository: repository,
        cookieReader: (url) async => [
          Cookie(name: 'autologin', value: 'same', domain: '.syosetu.org'),
        ],
      );

      expect(await service.refreshSessionFromWebView(), isFalse);

      expect(repository.saveCount, 0);
    });
  });
}
