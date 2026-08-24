import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
