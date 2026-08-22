import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';

void main() {
  group('isTrustedKakuyomuUri', () {
    test('HTTPSのkakuyomu.jpだけを許可する', () {
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp/my')),
        isTrue,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp/auth/login')),
        isTrue,
      );
    });

    test('紛らわしい外部ホストとHTTPを拒否する', () {
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://evilkakuyomu.jp/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://kakuyomu.jp.example.com/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('https://sub.kakuyomu.jp/my')),
        isFalse,
      );
      expect(
        isTrustedKakuyomuUri(Uri.parse('http://kakuyomu.jp/my')),
        isFalse,
      );
    });
  });
}
