import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/trusted_uri.dart';

void main() {
  group('isTrustedHttpsOrigin', () {
    test('指定したHTTPS originを許可する', () {
      expect(
        isTrustedHttpsOrigin(
          Uri.parse('https://example.com/path'),
          host: 'example.com',
        ),
        isTrue,
      );
    });

    test('HTTP、別ホスト、標準外ポート、userinfoを拒否する', () {
      final untrustedUris = <Uri>[
        Uri.parse('http://example.com/path'),
        Uri.parse('https://other.example/path'),
        Uri.parse('https://example.com:8443/path'),
        Uri.parse('https://user@example.com/path'),
      ];

      for (final uri in untrustedUris) {
        expect(
          isTrustedHttpsOrigin(uri, host: 'example.com'),
          isFalse,
          reason: uri.toString(),
        );
      }
    });
  });
}
