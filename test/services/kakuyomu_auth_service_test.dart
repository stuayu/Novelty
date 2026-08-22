import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';

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
}
