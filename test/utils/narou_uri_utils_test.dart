import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/narou_uri_utils.dart';

void main() {
  group('Narou URI utilities', () {
    test('ログイン経路とその配下だけをログインページとして判定する', () {
      for (final path in ['/login', '/login/', '/login/auth_code/verify/']) {
        expect(
          isNarouLoginUri(Uri.parse('https://syosetu.com$path')),
          isTrue,
          reason: path,
        );
      }

      for (final path in ['/login_input/', '/login-invalid', '/mypage/']) {
        expect(
          isNarouLoginUri(Uri.parse('https://syosetu.com$path')),
          isFalse,
          reason: path,
        );
      }
    });

    test('安全ななろうのHTTPS originだけを許可する', () {
      expect(
        isTrustedNarouUri(Uri.parse('https://syosetu.com/login/')),
        isTrue,
      );
      for (final uri in [
        Uri.parse('http://syosetu.com/login/'),
        Uri.parse('https://syosetu.com.evil.example/login/'),
        Uri.parse('https://syosetu.com:444/login/'),
        Uri.parse('https://user@syosetu.com/login/'),
      ]) {
        expect(isTrustedNarouUri(uri), isFalse, reason: '$uri');
      }
    });
  });
}
