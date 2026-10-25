import 'package:flutter/services.dart';

/// Cookie保存時のエラーを、ログイン画面向けの説明へ変換する。
String? kakuyomuLoginErrorMessage(Object error) {
  if (error is PlatformException &&
      error.code == 'Unexpected security result code' &&
      error.message?.contains('-34018') == true) {
    return 'このMacアプリではKeychainにCookieを保存できません。署名とKeychain権限を確認してください。';
  }
  return null;
}
