import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/kakuyomu_session_cookie.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';

class _FakeKakuyomuSessionRepository extends KakuyomuSessionRepository {
  List<KakuyomuSessionCookie> savedCookies = const [];
  int saveCount = 0;

  @override
  Future<void> saveCookies(List<KakuyomuSessionCookie> cookies) async {
    saveCount++;
    savedCookies = List.unmodifiable(cookies);
  }
}

void main() {
  test('WebViewのカクヨムCookieをSecure Storageへ保存する', () async {
    final repository = _FakeKakuyomuSessionRepository();
    WebUri? requestedUrl;
    final service = KakuyomuWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async {
        requestedUrl = url;
        return [
          Cookie(
            name: 'user_session',
            value: 'session-value',
            domain: '.kakuyomu.jp',
            path: '/',
            isSecure: true,
            isHttpOnly: true,
          ),
          Cookie(
            name: 'unrelated',
            value: 'other-value',
            domain: 'example.com',
            path: '/',
          ),
        ];
      },
    );

    final captured = await service.captureFromWebView();

    expect(requestedUrl?.host, 'kakuyomu.jp');
    expect(captured.map((cookie) => cookie.name), ['user_session']);
    expect(repository.savedCookies, captured);
  });

  test('WebViewのCookie取得が空なら保存済みセッションを消さない', () async {
    final repository = _FakeKakuyomuSessionRepository()
      ..savedCookies = const [
        KakuyomuSessionCookie(
          name: 'user_session',
          value: 'saved-value',
          domain: '.kakuyomu.jp',
          path: '/',
        ),
      ];
    final service = KakuyomuWebCookieService(
      sessionRepository: repository,
      cookieReader: (_) async => const [],
    );

    final captured = await service.captureFromWebView();

    expect(captured, isEmpty);
    expect(repository.saveCount, 0);
    expect(repository.savedCookies.single.value, 'saved-value');
  });
}
