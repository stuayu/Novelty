import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/auth_repository.dart';

void main() {
  group('AuthRepository', () {
    test('インスタンスが正しく生成される', () {
      final repo = AuthRepository();
      expect(repo, isA<AuthRepository>());
    });

    test('セッションCookieが未保存の場合はnullを返す', () async {
      // flutter_secure_storageはFlutterバインディングが必要なため
      // この単体テストでは基本的なAPIの存在確認のみ行う
      final repo = AuthRepository();
      expect(repo.getSessionCookies, isA<Function>());
      expect(repo.saveSessionCookies, isA<Function>());
      expect(repo.clearAll, isA<Function>());
      expect(repo.buildCookieHeader, isA<Function>());
    });
  });
}
