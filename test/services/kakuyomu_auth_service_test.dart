import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';

class _FakeSessionRepository extends KakuyomuSessionRepository {
  _FakeSessionRepository(this.cookieHeader);

  final String? cookieHeader;

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('kakuyomuDashboardIndicatesLoggedIn', () {
    test('未ログインの/auth/loginリンクがある場合はfalse', () {
      const html = '''
<html>
  <body>
    <a href="/auth/login">ログイン</a>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isFalse);
    });

    test('旧/loginリンクがある場合もfalse', () {
      const html = '''
<html>
  <body>
    <a href="/login">ログイン</a>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isFalse);
    });

    test('data-is-guest=0のログイン済みページはtrue', () {
      const html = '''
<html data-is-guest="0">
  <body id="page-my">
    <header class="test-header isSignedInUser"></header>
    <main><h1>ダッシュボード</h1></main>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isTrue);
    });

    test('isSignedInUserマーカーだけでもログイン済みと判定する', () {
      const html = '''
<html>
  <body id="page-my">
    <header class="test-header isSignedInUser"></header>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isTrue);
    });

    test('ログイン導線が無いだけの汎用200ページはfalse', () {
      const html = '''
<html>
  <body>
    <main><h1>一時的なエラーページ</h1></main>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isFalse);
    });

    test('空HTMLはfalse', () {
      expect(kakuyomuDashboardIndicatesLoggedIn(''), isFalse);
    });
  });

  group('KakuyomuAuthService.isSessionValid', () {
    test('同一originのredirect後にログイン済みマーカーを確認する', () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/my') {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['/my/dashboard'],
            },
          );
        }
        return ResponseBody.fromString(
          '<html data-is-guest="0"><body></body></html>',
          200,
        );
      });
      final service = KakuyomuAuthService(
        sessionRepository: _FakeSessionRepository('session=test'),
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(await service.isSessionValid(), isTrue);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.uri.path, '/my/dashboard');
    });

    test('外部originへredirectしてもCookie付きで追跡しない', () async {
      final adapter = _RecordingAdapter((options) {
        return ResponseBody.fromString(
          '',
          302,
          headers: <String, List<String>>{
            'location': ['https://attacker.example/collect'],
          },
        );
      });
      final service = KakuyomuAuthService(
        sessionRepository: _FakeSessionRepository('session=test'),
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(await service.isSessionValid(), isFalse);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.host, 'kakuyomu.jp');
      expect(adapter.requests.single.headers['Cookie'], 'session=test');
    });
  });
}
