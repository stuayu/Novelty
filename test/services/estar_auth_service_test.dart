import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/estar_session_cookie.dart';
import 'package:novelty/repositories/estar_session_repository.dart';
import 'package:novelty/services/estar_auth_service.dart';
import 'package:novelty/services/estar_web_cookie_service.dart';

class _FakeSessionRepository extends EstarSessionRepository {
  bool hasSession = true;
  bool cleared = false;

  @override
  Future<bool> hasCookies() async => hasSession;

  @override
  Future<void> clearAll() async => cleared = true;
}

class _FakeWebCookieService extends EstarWebCookieService {
  _FakeWebCookieService(EstarSessionRepository repository)
    : super(sessionRepository: repository, cookieReader: (_) async => []);

  bool cleared = false;
  bool failToClear = false;
  int captureCount = 0;

  @override
  Future<void> clearWebViewCookies() async {
    cleared = true;
    if (failToClear) throw StateError('WebView Cookie削除失敗');
  }

  @override
  Future<List<EstarSessionCookie>> captureFromWebView() async {
    captureCount++;
    return const [
      EstarSessionCookie(
        name: 'unknown_cookie',
        value: 'secret',
        domain: 'estar.jp',
        path: '/',
      ),
    ];
  }
}

void main() {
  group('isEstarLoginCompleteUrl', () {
    test('/app/login_completeへの遷移をログイン完了と判定する', () {
      expect(
        isEstarLoginCompleteUrl(
          Uri.parse('https://estar.jp/app/login_complete'),
        ),
        isTrue,
      );
    });

    test('外部ホストの同名パスや別パスはログイン完了と判定しない', () {
      expect(
        isEstarLoginCompleteUrl(
          Uri.parse('https://example.com/app/login_complete'),
        ),
        isFalse,
      );
      expect(
        isEstarLoginCompleteUrl(Uri.parse('https://estar.jp/login')),
        isFalse,
      );
    });
  });

  group('EstarAuthService', () {
    test('保存済みCookieの有無をログイン状態として返す', () async {
      final repository = _FakeSessionRepository();
      final service = EstarAuthService(sessionRepository: repository);

      expect(await service.isSessionValid(), isTrue);
      repository.hasSession = false;
      expect(await service.isSessionValid(), isFalse);
    });

    test('logoutでWebViewと保存済みセッションを消す', () async {
      final repository = _FakeSessionRepository();
      final webCookieService = _FakeWebCookieService(repository);
      final service = EstarAuthService(
        sessionRepository: repository,
        webCookieService: webCookieService,
      );

      await service.logout();

      expect(webCookieService.cleared, isTrue);
      expect(repository.cleared, isTrue);
    });

    test('WebView Cookie削除失敗時も保存済みセッションを消す', () async {
      final repository = _FakeSessionRepository();
      final webCookieService = _FakeWebCookieService(repository)
        ..failToClear = true;
      final service = EstarAuthService(
        sessionRepository: repository,
        webCookieService: webCookieService,
      );

      await expectLater(service.logout(), throwsStateError);

      expect(repository.cleared, isTrue);
    });
  });

  test('/app/login_completeの時だけWebView Cookieを取得する', () async {
    final repository = _FakeSessionRepository();
    final webCookieService = _FakeWebCookieService(repository);

    expect(
      await captureEstarLoginIfCompleted(
        Uri.parse('https://estar.jp/login'),
        webCookieService,
      ),
      isFalse,
    );
    expect(webCookieService.captureCount, 0);

    expect(
      await captureEstarLoginIfCompleted(
        Uri.parse('https://estar.jp/app/login_complete'),
        webCookieService,
      ),
      isTrue,
    );
    expect(webCookieService.captureCount, 1);
  });
}
