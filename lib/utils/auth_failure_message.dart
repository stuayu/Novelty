import 'package:flutter/services.dart';

/// 認証処理で発生した例外を、利用者に伝わる文言へ変換する。
///
/// 資格情報そのものは決して含めない。
String describeAuthFailure(Object error) {
  if (error is PlatformException) {
    // 端末の安全な保存領域（Keychain / Keystore）へ書き込めなかった場合。
    // macOS では keychain-access-groups の entitlement が無いと
    // errSecMissingEntitlement (-34018) で必ず失敗する。
    if (error.code.contains('-34018') ||
        error.message?.contains('entitlement') == true) {
      return 'ログイン情報を安全に保存できませんでした。'
          'アプリの署名設定（Keychain へのアクセス許可）を確認してください。';
    }
    return 'ログイン情報を安全に保存できませんでした: ${error.message ?? error.code}';
  }
  return 'ログインに失敗しました: $error';
}
