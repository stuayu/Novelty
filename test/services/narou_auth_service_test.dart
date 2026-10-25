import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/narou_auth_service.dart';

import 'narou_auth_service_test.mocks.dart';

const _defaultMfaChallengeHtml =
    '<h2>二段階認証 認証コードを入力</h2> '
    '<form action="/login/auth_code/verify/" method="post"> '
    '<input type="hidden" name="csrf" value="csrf-value"> '
    '<input type="text" name="auth_code" autocomplete="one-time-code"> '
    '</form>';

class _LoginAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'set-cookie': <String>[
            'ks2=ks2-value; Path=/',
            'ses=ses-value; Path=/',
            'userl=userl-value; Path=/',
          ],
        },
      );
    }
    if (options.uri.path == '/login/input/') {
      return ResponseBody.fromString(
        '<form action="/login/login/"> '
        '<input name="narouid"><input name="pass"></form>',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
        },
      );
    }
    return ResponseBody.fromString(
      '<span class="p-up-header-pc__username">テストユーザー</span>',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MfaLoginAdapter implements HttpClientAdapter {
  _MfaLoginAdapter({
    this.challengeLocation = '/login/auth_code/',
    this.failVerification = false,
    this.failVerificationWithGenericPage = false,
    this.sessionCookiesOnChallenge = false,
    this.returnRefreshedChallengeOnce = false,
    this.failVerificationWithRedirect = false,
    this.challengeHtml = _defaultMfaChallengeHtml,
    this.credentialErrorHtml,
    this.loginFormAction = '/login/login/',
    this.expireSesWithExpires = false,
    this.redirectAfterVerificationToGenericPage = false,
    this.bookmarkPageWithoutUsername = false,
    this.bookmarkPageIsLogin = false,
    this.challengeStarted,
    this.releaseChallenge,
    this.verificationStarted,
    this.releaseVerification,
  });

  final String challengeLocation;
  final bool failVerification;
  final bool failVerificationWithGenericPage;
  final bool sessionCookiesOnChallenge;
  final bool returnRefreshedChallengeOnce;
  final bool failVerificationWithRedirect;
  final String challengeHtml;
  final String? credentialErrorHtml;
  final String loginFormAction;
  final bool expireSesWithExpires;
  final bool redirectAfterVerificationToGenericPage;
  final bool bookmarkPageWithoutUsername;
  final bool bookmarkPageIsLogin;
  final Completer<void>? challengeStarted;
  final Completer<void>? releaseChallenge;
  final Completer<void>? verificationStarted;
  final Completer<void>? releaseVerification;
  final List<RequestOptions> requests = <RequestOptions>[];
  int verificationAttempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'POST') {
      if (options.uri.path == '/login/auth_code/verify/') {
        if (failVerification) {
          throw DioException(
            requestOptions: options,
            message: 'password=do-not-log-this-password code=123456',
          );
        }
        if (failVerificationWithGenericPage) {
          return ResponseBody.fromString(
            '<html><body>認証を確認できませんでした</body></html>',
            200,
          );
        }
        if (failVerificationWithRedirect) {
          return ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': ['/error/'],
            },
          );
        }
        if (returnRefreshedChallengeOnce && verificationAttempts++ == 0) {
          return ResponseBody.fromString(
            '<h2>二段階認証 認証コードを確認</h2> '
            '<form action="/login/auth_code/verify/" method="post"> '
            '<input type="hidden" name="csrf" value="csrf-refreshed"> '
            '<input type="text" name="auth_code" '
            'autocomplete="one-time-code"> '
            '</form>',
            200,
            headers: <String, List<String>>{
              'content-type': ['text/html; charset=utf-8'],
            },
          );
        }
        final started = verificationStarted;
        if (started != null && !started.isCompleted) started.complete();
        await releaseVerification?.future;
        return ResponseBody.fromString(
          '',
          302,
          headers: <String, List<String>>{
            'location': [
              if (redirectAfterVerificationToGenericPage)
                '/mypage/'
              else
                '/favnovelmain/list/',
            ],
            'set-cookie': <String>[
              'ks2=ks2-value; Path=/; Secure',
              'ses=ses-value; Path=/; HttpOnly; Secure',
              'userl=userl-value; Path=/; HttpOnly; Secure',
            ],
          },
        );
      }
      final credentialErrorHtml = this.credentialErrorHtml;
      if (credentialErrorHtml != null) {
        return ResponseBody.fromString(
          credentialErrorHtml,
          200,
          headers: <String, List<String>>{
            'content-type': ['text/html; charset=utf-8'],
          },
        );
      }
      final cookies = <String>['challenge=temporary; Path=/; HttpOnly'];
      if (sessionCookiesOnChallenge) {
        cookies.addAll(<String>[
          'ks2=stale-ks2; Path=/; Secure',
          'ses=stale-ses; Path=/; HttpOnly; Secure',
          'userl=stale-userl; Path=/; HttpOnly; Secure',
        ]);
      }
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': [challengeLocation],
          'set-cookie': cookies,
        },
      );
    }
    if (options.uri.path == '/login/input/') {
      return ResponseBody.fromString(
        '<form action="$loginFormAction" method="post"> '
        '<input name="narouid"><input name="pass"></form>',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
          'set-cookie': ['form_session=form-value; Path=/; Secure'],
        },
      );
    }
    if (options.uri.path == '/favnovelmain/list/') {
      if (bookmarkPageIsLogin) {
        return ResponseBody.fromString(
          '<form action="/login/login/"><input name="narouid"></form>',
          200,
        );
      }
      if (bookmarkPageWithoutUsername) {
        return ResponseBody.fromString(
          '<li class="p-up-bookmark-item">ブックマーク</li>',
          200,
        );
      }
      return ResponseBody.fromString(
        '<span class="p-up-header-pc__username">認証済みユーザー</span>'
        ' <div>ブックマーク一覧</div>',
        200,
      );
    }
    if (options.uri.path == '/mypage/') {
      return ResponseBody.fromString(
        '<html><body>ログイン完了 <a>ブックマーク</a></body></html>',
        200,
      );
    }
    if (options.uri.path == '/error/') {
      return ResponseBody.fromString(
        '<html><body>認証コードを確認できませんでした</body></html>',
        200,
      );
    }
    final started = challengeStarted;
    if (started != null && !started.isCompleted) started.complete();
    await releaseChallenge?.future;
    final challengeHeaders = <String, List<String>>{
      'content-type': ['text/html; charset=utf-8'],
    };
    if (expireSesWithExpires) {
      challengeHeaders['set-cookie'] = <String>[
        'ses=deleted; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ];
    }
    return ResponseBody.fromString(
      challengeHtml,
      200,
      headers: challengeHeaders,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TwoStepMfaAdapter implements HttpClientAdapter {
  _TwoStepMfaAdapter({this.emailOnly = false});

  final bool emailOnly;
  final List<RequestOptions> requests = <RequestOptions>[];

  static const _challengeId = 'test-challenge';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    if (options.method == 'POST' && path == '/login/login/') {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': ['/user2stepauth/input/authtoken/$_challengeId/'],
          'set-cookie': ['challenge=fake; Path=/; Secure'],
        },
      );
    }
    if (options.method == 'POST' &&
        (path.startsWith('/user2stepauth/totpauth/') ||
            path.startsWith('/user2stepauth/emailauth/'))) {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': ['/login/user2stepauthend/'],
          'set-cookie': <String>[
            'ks2=ks2-value; Path=/; Secure',
            'ses=ses-value; Path=/; HttpOnly; Secure',
            'userl=userl-value; Path=/; HttpOnly; Secure',
          ],
        },
      );
    }
    if (options.method == 'POST' &&
        path.startsWith('/user2stepauth/sendemail/')) {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': [
            '/user2stepauth/emailinput/authtoken/$_challengeId/',
          ],
        },
      );
    }
    if (options.method == 'GET' && path == '/login/input/') {
      return ResponseBody.fromString(
        '<form action="/login/login/"> '
        '<input name="narouid"><input name="pass"> '
        '<label><input type="checkbox" name="auto_login" value="1"> '
        '次回から自動的にログイン</label></form>',
        200,
      );
    }
    if (options.method == 'GET' &&
        path == '/user2stepauth/input/authtoken/$_challengeId/') {
      final totpLink = emailOnly
          ? ''
          : '<a href="/user2stepauth/totpinput/authtoken/$_challengeId/"> '
                '認証アプリ</a>';
      return ResponseBody.fromString(
        '<form method="post" '
        'action="/user2stepauth/sendemail/authtoken/$_challengeId/"> '
        '<input type="radio" name="email_type" value="primary"> '
        '</form>$totpLink',
        200,
      );
    }
    if (options.method == 'GET' &&
        path == '/user2stepauth/totpinput/authtoken/$_challengeId/') {
      return ResponseBody.fromString(
        '<h2>二段階認証</h2><p>メール認証に切り替えることもできます。'
        '認証コードを登録メールに送信できます</p><form '
        'action="/user2stepauth/totpauth/authtoken/$_challengeId/"> '
        '<input type="text" name="totp_code" '
        'autocomplete="one-time-code"></form>',
        200,
      );
    }
    if (options.method == 'GET' &&
        path == '/user2stepauth/emailinput/authtoken/$_challengeId/') {
      return ResponseBody.fromString(
        '<h2>メール認証コード</h2><form '
        'action="/user2stepauth/emailauth/authtoken/$_challengeId/"> '
        '<input type="text" name="email_code" '
        'autocomplete="one-time-code"></form>',
        200,
      );
    }
    if (options.method == 'GET' && path == '/login/user2stepauthend/') {
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': ['/user/top/'],
        },
      );
    }
    if (options.method == 'GET' && path == '/user/top/') {
      return ResponseBody.fromString(
        '<span class="p-up-header-pc__username">テスト利用者</span>',
        200,
      );
    }
    if (options.method == 'GET' && path == '/favnovelmain/list/') {
      return ResponseBody.fromString(
        '<span class="p-up-header-pc__username">テスト利用者</span>',
        200,
      );
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _RotatingSessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '<span class="p-up-header-pc__username">テスト利用者</span> '
    '<div>ブックマーク一覧</div>',
    200,
    headers: <String, List<String>>{
      'set-cookie': <String>[
        'ks2=ks2-rotated; Path=/; Secure',
        'ses=ses-rotated; Path=/; HttpOnly; Secure',
        'userl=userl-rotated; Path=/; HttpOnly; Secure',
      ],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _UnauthenticatedSessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '<form action="/login/login/"><input name="narouid"></form>',
    200,
    headers: <String, List<String>>{
      'set-cookie': <String>['ses=anonymous; Path=/; Secure'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _LoginRedirectSessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '',
    302,
    headers: <String, List<String>>{
      'location': <String>['/login/input/'],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _TemporaryFailureSessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', 503);

  @override
  void close({bool force = false}) {}
}

class _StatusSessionAdapter implements HttpClientAdapter {
  _StatusSessionAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', statusCode);

  @override
  void close({bool force = false}) {}
}

class _UnknownBookmarkPageAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('<h1>メンテナンス中</h1>', 200);

  @override
  void close({bool force = false}) {}
}

class _OrderedAuthRepository extends AuthRepository {
  final events = <String>[];
  final sessionStarted = Completer<void>();
  final allowSession = Completer<void>();
  int clearCount = 0;

  @override
  Future<void> saveSession({
    required String narouid,
    required String username,
    required String ks2,
    required String ses,
    required String userl,
    required bool rememberSession,
  }) async {
    events.add('session');
    sessionStarted.complete();
    await allowSession.future;
  }

  @override
  Future<void> clearAll() async {
    clearCount++;
    events.add('clear');
  }

  void releaseAll() {
    if (!allowSession.isCompleted) allowSession.complete();
  }
}

@GenerateMocks([AuthRepository])
void main() {
  group('NarouAuthService', () {
    late MockAuthRepository mockAuthRepository;
    late NarouAuthService authService;

    setUp(() {
      mockAuthRepository = MockAuthRepository();
      authService = NarouAuthService(authRepository: mockAuthRepository);
    });

    group('ログイン失敗ケース', () {
      test('セッションCookieが保存されていない場合isSessionValidはfalseを返す', () async {
        when(
          mockAuthRepository.buildCookieHeader(),
        ).thenAnswer((_) async => null);

        final result = await authService.isSessionValid();
        expect(result, isFalse);
      });
    });

    test('有効確認中に更新されたセッションCookieをKeyChainへ保存する', () async {
      when(
        mockAuthRepository.buildCookieHeader(),
      ).thenAnswer((_) async => 'ks2=old; ses=old; userl=old');
      when(mockAuthRepository.getSessionCookies()).thenAnswer(
        (_) async => <String, String>{
          'ks2': 'ks2-old',
          'ses': 'ses-old',
          'userl': 'userl-old',
        },
      );
      when(
        mockAuthRepository.updateSessionCookieHeaders(any),
      ).thenAnswer((_) async {});
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _RotatingSessionAdapter(),
      );

      expect(await service.isSessionValid(), isTrue);

      verify(
        mockAuthRepository.updateSessionCookieHeaders([
          'ks2=ks2-rotated; Path=/; Secure',
          'ses=ses-rotated; Path=/; HttpOnly; Secure',
          'userl=userl-rotated; Path=/; HttpOnly; Secure',
        ], expectedCookieHeader: 'ks2=old; ses=old; userl=old'),
      ).called(1);
    });

    test('未認証ページのSet-Cookieでは保存済みセッションを更新しない', () async {
      when(
        mockAuthRepository.buildCookieHeader(),
      ).thenAnswer((_) async => 'ks2=old; ses=old; userl=old');
      when(
        mockAuthRepository.updateSessionCookieHeaders(any),
      ).thenAnswer((_) async {});
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _UnauthenticatedSessionAdapter(),
      );

      expect(
        await service.validateSession('ks2=old; ses=old; userl=old'),
        NarouSessionValidity.invalid,
      );
      expect(await service.isSessionValid(), isFalse);

      verifyNever(mockAuthRepository.updateSessionCookieHeaders(any));
    });

    test('ログイン画面へのリダイレクトを明示的なセッション失効として扱う', () async {
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _LoginRedirectSessionAdapter(),
      );

      expect(
        await service.validateSession(
          'ks2=old; ses=old; userl=old',
        ),
        NarouSessionValidity.invalid,
      );
    });

    test('なろうの一時エラーはセッション失効と判定しない', () async {
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _TemporaryFailureSessionAdapter(),
      );

      expect(
        await service.validateSession(
          'ks2=old; ses=old; userl=old',
        ),
        NarouSessionValidity.unavailable,
      );
    });

    test('401は未認証として扱うが403だけではセッションを失効させない', () async {
      final unauthorizedService = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _StatusSessionAdapter(401),
      );
      final forbiddenService = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _StatusSessionAdapter(403),
      );

      expect(
        await unauthorizedService.validateSession(
          'ks2=old; ses=old; userl=old',
        ),
        NarouSessionValidity.invalid,
      );
      expect(
        await forbiddenService.validateSession(
          'ks2=old; ses=old; userl=old',
        ),
        NarouSessionValidity.unavailable,
      );
    });

    test('認証状態を判断できない200ページはセッション失効と判定しない', () async {
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = _UnknownBookmarkPageAdapter(),
      );

      expect(
        await service.validateSession(
          'ks2=old; ses=old; userl=old',
        ),
        NarouSessionValidity.unavailable,
      );
    });

    test('認証情報をひとつのセッション保存として記録する', () async {
      final repository = _OrderedAuthRepository();
      final dio = Dio()..httpClientAdapter = _MfaLoginAdapter();
      final service = NarouAuthService(
        authRepository: repository,
        dio: dio,
      );

      final firstStep = await service.login(
        narouid: 'test-id',
        password: 'pass',
      );
      expect(firstStep.requiresMfa, isTrue);
      final loginFuture = service.verifyMfaCode('123456');

      try {
        await repository.sessionStarted.future;
        expect(repository.events, <String>['session']);
        repository.allowSession.complete();
        expect((await loginFuture).isSuccess, isTrue);
      } finally {
        repository.releaseAll();
        await loginFuture;
      }
    });

    test('パスワードだけでセッションCookieが返っても必須MFA完了前は保存しない', () async {
      final repository = MockAuthRepository();
      final service = NarouAuthService(
        authRepository: repository,
        dio: Dio()..httpClientAdapter = _LoginAdapter(),
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'secret-password',
      );

      expect(result.isSuccess, isFalse);
      expect(result.requiresMfa, isFalse);
      verifyNever(repository.saveNarouid(any));
      verifyNever(
        repository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('パスワード確認後は二段階認証を待ちセッション情報を保存しない', () async {
      final adapter = _MfaLoginAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: dio,
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.requiresMfa,
        isTrue,
        reason:
            '${result.error} requests=${adapter.requests.map((r) => r.uri)}',
      );
      expect(result.error, isNull);
      expect(adapter.requests, hasLength(3));
      expect(
        adapter.requests[2].headers['Cookie'],
        'form_session=form-value; challenge=temporary',
      );
      verifyNever(mockAuthRepository.saveNarouid(any));
      verifyNever(
        mockAuthRepository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('TOTPページにメール認証への切替案内があっても設定案内を重複表示しない', () async {
      final adapter = _TwoStepMfaAdapter();
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'secret-password',
      );

      expect(firstStep.requiresMfa, isTrue);
      expect(
        adapter.requests.map((request) => request.uri.path),
        contains('/user2stepauth/totpinput/authtoken/test-challenge/'),
      );
      final loginPost = adapter.requests.firstWhere(
        (request) => request.method == 'POST',
      );
      expect(loginPost.data, containsPair('auto_login', '1'));

      final result = await service.verifyMfaCode('654321');

      expect(result.isSuccess, isTrue);
      expect(result.shouldSuggestAuthenticatorApp, isFalse);
      final totpPost = adapter.requests.firstWhere(
        (request) => request.uri.path.startsWith('/user2stepauth/totpauth/'),
      );
      expect(totpPost.data, containsPair('totp_code', '654321'));
      expect(totpPost.uri.host, 'syosetu.com');
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: 'テスト利用者',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: true,
        ),
      ).called(1);
    });

    test('TOTP未設定の選択画面ではメールを要求しメールコードを送信できる', () async {
      final adapter = _TwoStepMfaAdapter(emailOnly: true);
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'secret-password',
        rememberSession: false,
      );

      expect(firstStep.requiresMfa, isTrue);
      final loginPost = adapter.requests.firstWhere(
        (request) => request.method == 'POST',
      );
      expect(loginPost.data, isNot(contains('auto_login')));
      expect(
        adapter.requests.map((request) => request.uri.path),
        contains('/user2stepauth/emailinput/authtoken/test-challenge/'),
      );
      expect(
        adapter.requests.map((request) => request.uri.path),
        isNot(contains('/user2stepauth/totpinput/authtoken/test-challenge/')),
      );

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      expect(result.shouldSuggestAuthenticatorApp, isTrue);
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: 'テスト利用者',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: false,
        ),
      ).called(1);
      final emailPost = adapter.requests.firstWhere(
        (request) => request.uri.path.startsWith('/user2stepauth/emailauth/'),
      );
      expect(emailPost.data, containsPair('email_code', '123456'));
    });

    test('確認コードを同一originのchallenge formへ送り成功後だけsessionを保存する', () async {
      final adapter = _MfaLoginAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: dio,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      expect(result.username, '認証済みユーザー');
      expect(adapter.requests, hasLength(5));
      final challengeRequest = adapter.requests[3];
      expect(
        challengeRequest.uri.toString(),
        'https://syosetu.com/login/auth_code/verify/',
      );
      expect(challengeRequest.data, {
        'csrf': 'csrf-value',
        'auth_code': '123456',
      });
      expect(
        challengeRequest.headers['Cookie'],
        'form_session=form-value; challenge=temporary',
      );
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: '認証済みユーザー',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: true,
        ),
      ).called(1);
    });

    test('メール認証コードの直接入力で成功したらTOTP設定を案内する', () async {
      final adapter = _MfaLoginAdapter(
        challengeHtml: '''
<h2>二段階認証</h2>
<p>メール認証コードを入力してください</p>
<form action="/login/auth_code/verify/" method="post">
<input type="text" name="auth_code" autocomplete="one-time-code"></form>
''',
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'secret-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      expect(result.shouldSuggestAuthenticatorApp, isTrue);
    });

    test('ログイン状態を維持しない選択ではセッション情報を永続保存しない', () async {
      final adapter = _MfaLoginAdapter();
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
        rememberSession: false,
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: '認証済みユーザー',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: false,
        ),
      ).called(1);
      verifyNever(mockAuthRepository.saveNarouid(any));
      verifyNever(mockAuthRepository.saveUsername(any));
      verifyNever(
        mockAuthRepository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('MFA後の最終ページにユーザー名がなくてもブックマークページで確認してログインする', () async {
      final adapter = _MfaLoginAdapter(
        redirectAfterVerificationToGenericPage: true,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      expect(result.username, '認証済みユーザー');
      expect(adapter.requests, hasLength(6));
      expect(adapter.requests.last.uri.path, '/favnovelmain/list/');
      expect(
        adapter.requests.last.headers['Cookie'],
        contains('ks2=ks2-value'),
      );
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: '認証済みユーザー',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: true,
        ),
      ).called(1);
    });

    test('MFA後のユーザー名がなくても有効なブックマークページがあればログインIDを表示名に使う', () async {
      final adapter = _MfaLoginAdapter(
        redirectAfterVerificationToGenericPage: true,
        bookmarkPageWithoutUsername: true,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isTrue);
      expect(result.username, 'reader-id');
      verify(
        mockAuthRepository.saveSession(
          narouid: 'reader-id',
          username: 'reader-id',
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
          rememberSession: true,
        ),
      ).called(1);
    });

    test('MFA後に認証済みブックマークページを確認できなければログインしない', () async {
      final repository = MockAuthRepository();
      final adapter = _MfaLoginAdapter(
        redirectAfterVerificationToGenericPage: true,
        bookmarkPageIsLogin: true,
      );
      final service = NarouAuthService(
        authRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isFalse);
      verifyNever(repository.saveNarouid(any));
      verifyNever(
        repository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('MFAコードの失敗後はチャレンジ前のセッションCookieだけでログインしない', () async {
      final repository = MockAuthRepository();
      final adapter = _MfaLoginAdapter(
        sessionCookiesOnChallenge: true,
        failVerificationWithGenericPage: true,
      );
      final service = NarouAuthService(
        authRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isFalse);
      verifyNever(repository.saveNarouid(any));
      verifyNever(
        repository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('MFAコードの失敗後に汎用ページへ転送されてもログインしない', () async {
      final repository = MockAuthRepository();
      final adapter = _MfaLoginAdapter(
        sessionCookiesOnChallenge: true,
        failVerificationWithRedirect: true,
      );
      final service = NarouAuthService(
        authRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final result = await service.verifyMfaCode('123456');

      expect(result.isSuccess, isFalse);
      verifyNever(repository.saveNarouid(any));
      verifyNever(
        repository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('MFA検証中にチャレンジをキャンセルすると遅れて届いた成功応答を破棄する', () async {
      final verificationStarted = Completer<void>();
      final releaseVerification = Completer<void>();
      final adapter = _MfaLoginAdapter(
        verificationStarted: verificationStarted,
        releaseVerification: releaseVerification,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final verification = service.verifyMfaCode('123456');
      await verificationStarted.future;
      service.cancelMfaChallenge();
      releaseVerification.complete();

      final result = await verification;

      expect(result.isSuccess, isFalse);
      verifyNever(mockAuthRepository.saveNarouid(any));
      verifyNever(
        mockAuthRepository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('ログイン中にチャレンジをキャンセルすると遅延応答でMFA状態を再生成しない', () async {
      final challengeStarted = Completer<void>();
      final releaseChallenge = Completer<void>();
      final adapter = _MfaLoginAdapter(
        challengeStarted: challengeStarted,
        releaseChallenge: releaseChallenge,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final login = service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      await challengeStarted.future;
      service.cancelMfaChallenge();
      releaseChallenge.complete();

      final result = await login;

      expect(result.requiresMfa, isFalse);
      final retry = await service.verifyMfaCode('123456');
      expect(retry.isSuccess, isFalse);
      expect(
        adapter.requests.where(
          (request) => request.uri.path == '/login/auth_code/verify/',
        ),
        isEmpty,
      );
    });

    test('ログアウトが進行中のMFA後セッション保存より後に完了する', () async {
      final repository = _OrderedAuthRepository();
      final adapter = _MfaLoginAdapter();
      final service = NarouAuthService(
        authRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final verification = service.verifyMfaCode('123456');
      await repository.sessionStarted.future;
      final logout = service.logout();
      repository.releaseAll();

      final result = await verification;
      await logout;

      expect(result.isSuccess, isFalse);
      expect(repository.events, isNot(contains('username')));
      expect(repository.events, isNot(contains('cookies')));
      expect(repository.clearCount, greaterThanOrEqualTo(1));
    });

    test('古いsession Cookieがあっても失敗コードでは保存せず更新されたCSRFで再試行する', () async {
      final adapter = _MfaLoginAdapter(
        sessionCookiesOnChallenge: true,
        returnRefreshedChallengeOnce: true,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      final rejectedCode = await service.verifyMfaCode('123456');

      expect(rejectedCode.isSuccess, isFalse);
      verifyNever(mockAuthRepository.saveNarouid(any));
      verifyNever(
        mockAuthRepository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );

      final acceptedCode = await service.verifyMfaCode('654321');

      expect(acceptedCode.isSuccess, isTrue);
      final verificationRequests = adapter.requests
          .where((request) => request.uri.path == '/login/auth_code/verify/')
          .toList();
      expect(verificationRequests, hasLength(2));
      final firstRequestData = Map<String, String>.from(
        verificationRequests[0].data as Map,
      );
      final secondRequestData = Map<String, String>.from(
        verificationRequests[1].data as Map,
      );
      expect(firstRequestData['csrf'], 'csrf-value');
      expect(secondRequestData['csrf'], 'csrf-refreshed');
    });

    test('二段階認証の説明と電話番号欄だけではMFA入力画面と判定しない', () async {
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()
          ..httpClientAdapter = _MfaLoginAdapter(
            challengeHtml:
                '<h2>二段階認証について</h2> '
                '<form><input type="tel" name="phone_number"></form>',
          ),
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );

      expect(result.requiresMfa, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('ログインに失敗しました'));
      verifyNever(mockAuthRepository.saveNarouid(any));
    });

    test('IDやパスワードのエラーをMFA画面の解析失敗と表示しない', () async {
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()
          ..httpClientAdapter = _MfaLoginAdapter(
            credentialErrorHtml: '<p>ログインIDまたはパスワードが正しくありません。</p>',
          ),
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'wrong-password',
      );

      expect(result.requiresMfa, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('ID・パスワード'));
      expect(result.error, isNot(contains('二段階認証画面を確認できませんでした')));
    });

    test('同一originでも既定のログインパス以外へ資格情報を送らない', () async {
      final adapter = _MfaLoginAdapter(loginFormAction: '/account/collect/');
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'GET');
    });

    test('Expiresで削除されたCookieをMFA検証リクエストへ含めない', () async {
      final adapter = _MfaLoginAdapter(
        sessionCookiesOnChallenge: true,
        returnRefreshedChallengeOnce: true,
        expireSesWithExpires: true,
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final firstStep = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );
      expect(firstStep.requiresMfa, isTrue);

      await service.verifyMfaCode('123456');

      final verificationRequest = adapter.requests.firstWhere(
        (request) => request.uri.path == '/login/auth_code/verify/',
      );
      expect(verificationRequest.headers['Cookie'], isNot(contains('ses=')));
    });

    test(
      'logout clears the in-memory MFA challenge before deleting credentials',
      () async {
        when(mockAuthRepository.clearAll()).thenAnswer((_) async {});
        final adapter = _MfaLoginAdapter();
        final service = NarouAuthService(
          authRepository: mockAuthRepository,
          dio: Dio()..httpClientAdapter = adapter,
        );

        final firstStep = await service.login(
          narouid: 'reader-id',
          password: 'do-not-log-this-password',
        );
        expect(firstStep.requiresMfa, isTrue);

        await service.logout();
        final result = await service.verifyMfaCode('123456');

        expect(result.isSuccess, isFalse);
        expect(
          adapter.requests.where(
            (request) => request.uri.path == '/login/auth_code/verify/',
          ),
          isEmpty,
        );
      },
    );

    test('外部originへのログインredirectを追跡せずCookieも送らない', () async {
      final adapter = _MfaLoginAdapter(
        challengeLocation: 'https://attacker.example/login/auth_code/',
      );
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        narouid: 'reader-id',
        password: 'do-not-log-this-password',
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.requests, hasLength(2));
      verifyNever(mockAuthRepository.saveNarouid(any));
      verifyNever(
        mockAuthRepository.saveSessionCookies(
          ks2: anyNamed('ks2'),
          ses: anyNamed('ses'),
          userl: anyNamed('userl'),
        ),
      );
    });

    test('HTTP例外に資格情報とコードが含まれても結果やログへ出さない', () async {
      final adapter = _MfaLoginAdapter(failVerification: true);
      final service = NarouAuthService(
        authRepository: mockAuthRepository,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

      try {
        final firstStep = await service.login(
          narouid: 'reader-id',
          password: 'do-not-log-this-password',
        );
        expect(firstStep.requiresMfa, isTrue);
        final result = await service.verifyMfaCode('123456');

        expect(result.error, isNot(contains('do-not-log-this-password')));
        expect(result.error, isNot(contains('123456')));
        expect(logs.join('\n'), isNot(contains('do-not-log-this-password')));
        expect(logs.join('\n'), isNot(contains('123456')));
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    group('_parseCookies（間接テスト）', () {
      test('NarouAuthServiceが正しくインスタンス化される', () {
        expect(authService, isA<NarouAuthService>());
      });
    });

    group('NarouLoginResult', () {
      test('成功結果が正しく生成される', () {
        const result = NarouLoginResult.success(username: 'テストユーザー');
        expect(result.isSuccess, isTrue);
        expect(result.username, equals('テストユーザー'));
        expect(result.error, isNull);
      });

      test('失敗結果が正しく生成される', () {
        const result = NarouLoginResult.failure('エラーメッセージ');
        expect(result.isSuccess, isFalse);
        expect(result.username, isNull);
        expect(result.error, equals('エラーメッセージ'));
      });
    });
  });
}
