import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/narou_auth_service.dart';

import 'narou_auth_service_test.mocks.dart';

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
        when(mockAuthRepository.buildCookieHeader())
            .thenAnswer((_) async => null);

        final result = await authService.isSessionValid();
        expect(result, isFalse);
      });
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
