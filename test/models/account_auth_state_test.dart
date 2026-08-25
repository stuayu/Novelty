import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/account_auth_state.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  group('AccountAuthState', () {
    test('表示名を持つログイン状態を表現できる', () {
      const state = AccountAuthState.loggedIn(
        source: NovelSource.narou,
        accountId: 'test-user',
        displayName: 'テストユーザー',
      );

      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, 'test-user');
      expect(state.displayName, 'テストユーザー');
    });

    test('表示名を取得できないログイン状態を表現できる', () {
      const state = AccountAuthState.loggedIn(
        source: NovelSource.kakuyomu,
      );

      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, isNull);
      expect(state.displayName, isNull);
    });

    test('未ログイン状態を表現できる', () {
      const state = AccountAuthState.loggedOut(source: NovelSource.narou);

      expect(state.isLoggedIn, isFalse);
      expect(state.accountId, isNull);
      expect(state.displayName, isNull);
    });
  });
}
