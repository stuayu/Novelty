import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/kakuyomu_session_cookie.dart';

void main() {
  group('KakuyomuSessionCookie', () {
    test('kakuyomu.jp配下のCookieだけを対象にする', () {
      const root = KakuyomuSessionCookie(
        name: 'a',
        value: '1',
        domain: 'kakuyomu.jp',
        path: '/',
      );
      const subdomain = KakuyomuSessionCookie(
        name: 'b',
        value: '2',
        domain: '.kakuyomu.jp',
        path: '/',
      );
      const external = KakuyomuSessionCookie(
        name: 'c',
        value: '3',
        domain: 'accounts.google.com',
        path: '/',
      );

      expect(root.belongsToKakuyomu, isTrue);
      expect(subdomain.belongsToKakuyomu, isTrue);
      expect(external.belongsToKakuyomu, isFalse);
    });

    test('期限切れCookieを判定できる', () {
      final expired = KakuyomuSessionCookie(
        name: 'a',
        value: '1',
        domain: 'kakuyomu.jp',
        path: '/',
        expiresDate: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      final valid = KakuyomuSessionCookie(
        name: 'b',
        value: '2',
        domain: 'kakuyomu.jp',
        path: '/',
        expiresDate: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      );

      expect(expired.isExpired, isTrue);
      expect(valid.isExpired, isFalse);
    });

    test('JSON往復でCookie属性を維持する', () {
      const original = KakuyomuSessionCookie(
        name: 'session',
        value: 'secret',
        domain: '.kakuyomu.jp',
        path: '/',
        expiresDate: 123456789,
        isSecure: true,
        isHttpOnly: true,
      );

      final restored = KakuyomuSessionCookie.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.value, original.value);
      expect(restored.domain, original.domain);
      expect(restored.path, original.path);
      expect(restored.expiresDate, original.expiresDate);
      expect(restored.isSecure, original.isSecure);
      expect(restored.isHttpOnly, original.isHttpOnly);
    });
  });
}
