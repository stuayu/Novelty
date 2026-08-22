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

    test('ログイン導線が無いダッシュボードはtrue', () {
      const html = '''
<html>
  <body>
    <nav><a href="/my">ダッシュボード</a></nav>
    <main><h1>ダッシュボード</h1></main>
  </body>
</html>
''';

      expect(kakuyomuDashboardIndicatesLoggedIn(html), isTrue);
    });

    test('空HTMLはfalse', () {
      expect(kakuyomuDashboardIndicatesLoggedIn(''), isFalse);
    });
  });
}
