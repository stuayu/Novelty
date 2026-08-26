import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/estar_session_cookie.dart';
import 'package:novelty/repositories/estar_session_repository.dart';
import 'package:novelty/services/estar_web_cookie_service.dart';

class _FakeSessionRepository extends EstarSessionRepository {
  List<EstarSessionCookie> saved = const [];

  @override
  Future<void> saveCookies(List<EstarSessionCookie> cookies) async {
    saved = List.unmodifiable(cookies);
  }
}

void main() {
  test('WebViewの両公式ホストからCookie名を限定せず保存する', () async {
    final repository = _FakeSessionRepository();
    final requestedHosts = <String>[];
    final service = EstarWebCookieService(
      sessionRepository: repository,
      cookieReader: (url) async {
        requestedHosts.add(url.host);
        if (url.host == 'auth.estar.jp') {
          return [
            Cookie(
              name: 'unknown_auth_cookie',
              value: 'auth-secret',
              domain: 'auth.estar.jp',
              path: '/',
            ),
          ];
        }
        return [
          Cookie(
            name: 'future_session_cookie',
            value: 'main-secret',
            domain: '.estar.jp',
            path: '/',
          ),
        ];
      },
    );

    final cookies = await service.captureFromWebView();

    expect(requestedHosts, ['estar.jp', 'auth.estar.jp']);
    expect(cookies.map((cookie) => cookie.name), [
      'future_session_cookie',
      'unknown_auth_cookie',
    ]);
    expect(repository.saved.map((cookie) => cookie.name), [
      'future_session_cookie',
      'unknown_auth_cookie',
    ]);
  });
}
