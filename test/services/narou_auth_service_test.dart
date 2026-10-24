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
  });

  final String challengeLocation;
  final bool failVerification;
  final requests = <RequestOptions>[];

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
        return ResponseBody.fromString(
          '',
          302,
          headers: <String, List<String>>{
            'location': ['/favnovelmain/list/'],
            'set-cookie': <String>[
              'ks2=ks2-value; Path=/; Secure',
              'ses=ses-value; Path=/; HttpOnly; Secure',
              'userl=userl-value; Path=/; HttpOnly; Secure',
            ],
          },
        );
      }
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': [challengeLocation],
          'set-cookie': ['challenge=temporary; Path=/; HttpOnly'],
        },
      );
    }
    if (options.uri.path == '/login/input/') {
      return ResponseBody.fromString(
        '<form action="/login/login/" method="post"> '
        '<input name="narouid"><input name="pass"></form>',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
          'set-cookie': ['form_session=form-value; Path=/; Secure'],
        },
      );
    }
    if (options.uri.path == '/favnovelmain/list/') {
      return ResponseBody.fromString(
        '<span class="p-up-header-pc__username">認証済みユーザー</span>',
        200,
      );
    }
    return ResponseBody.fromString(
      '<h2>二段階認証 認証コードを入力</h2> '
      '<form action="/login/auth_code/verify/" method="post"> '
      '<input type="hidden" name="csrf" value="csrf-value"> '
      '<input type="text" name="auth_code" autocomplete="one-time-code"> '
      '</form>',
      200,
      headers: <String, List<String>>{
        'content-type': ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _OrderedAuthRepository extends AuthRepository {
  final events = <String>[];
  final narouidStarted = Completer<void>();
  final usernameStarted = Completer<void>();
  final cookiesStarted = Completer<void>();
  final allowNarouid = Completer<void>();
  final allowUsername = Completer<void>();
  final allowCookies = Completer<void>();

  @override
  Future<void> saveNarouid(String narouid) async {
    events.add('narouid');
    narouidStarted.complete();
    await allowNarouid.future;
  }

  @override
  Future<void> saveUsername(String username) async {
    events.add('username');
    usernameStarted.complete();
    await allowUsername.future;
  }

  @override
  Future<void> saveSessionCookies({
    required String ks2,
    required String ses,
    required String userl,
  }) async {
    events.add('cookies');
    cookiesStarted.complete();
    await allowCookies.future;
  }

  void releaseAll() {
    if (!allowNarouid.isCompleted) allowNarouid.complete();
    if (!allowUsername.isCompleted) allowUsername.complete();
    if (!allowCookies.isCompleted) allowCookies.complete();
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

    test('認証情報は前の保存完了後に次の保存を開始する', () async {
      final repository = _OrderedAuthRepository();
      final dio = Dio()..httpClientAdapter = _LoginAdapter();
      final service = NarouAuthService(
        authRepository: repository,
        dio: dio,
      );

      final loginFuture = service.login(narouid: 'test-id', password: 'pass');

      try {
        await repository.narouidStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(repository.events, <String>['narouid']);

        repository.allowNarouid.complete();
        await repository.usernameStarted.future;
        expect(repository.events, <String>['narouid', 'username']);

        repository.allowUsername.complete();
        await repository.cookiesStarted.future;
        expect(repository.events, <String>['narouid', 'username', 'cookies']);

        repository.allowCookies.complete();
        expect((await loginFuture).isSuccess, isTrue);
      } finally {
        repository.releaseAll();
        await loginFuture;
      }
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
      verify(mockAuthRepository.saveNarouid('reader-id')).called(1);
      verify(
        mockAuthRepository.saveSessionCookies(
          ks2: 'ks2-value',
          ses: 'ses-value',
          userl: 'userl-value',
        ),
      ).called(1);
    });

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
