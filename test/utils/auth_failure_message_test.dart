import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/auth_failure_message.dart';

void main() {
  group('describeAuthFailure', () {
    test('Keychainのentitlement不足を分かる文言にする', () {
      final error = PlatformException(
        code: 'Unexpected security result code',
        message: "A required entitlement isn't present.",
        details: -34018,
      );

      final message = describeAuthFailure(error);

      expect(message, contains('安全に保存できませんでした'));
      expect(message, contains('署名設定'));
    });

    test('その他のPlatformExceptionは保存失敗として扱う', () {
      final error = PlatformException(
        code: 'write_error',
        message: '書き込みに失敗',
      );

      expect(
        describeAuthFailure(error),
        contains('安全に保存できませんでした'),
      );
    });

    test('通常の例外はそのまま失敗として扱う', () {
      expect(
        describeAuthFailure(StateError('想定外')),
        contains('ログインに失敗しました'),
      );
    });
  });
}
