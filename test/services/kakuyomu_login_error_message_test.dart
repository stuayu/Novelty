import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/kakuyomu_login_error_message.dart';

void main() {
  test('Keychain entitlement不足をログイン画面向けに説明する', () {
    final error = PlatformException(
      code: 'Unexpected security result code',
      message: 'A required entitlement is not present, -34018',
    );

    expect(kakuyomuLoginErrorMessage(error), contains('Keychain'));
  });

  test('Keychain以外のエラーは既定メッセージへ委ねる', () {
    expect(kakuyomuLoginErrorMessage(StateError('unavailable')), isNull);
  });
}
