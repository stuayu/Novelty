import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:novelty/models/kakuyomu_session_cookie.dart';
import 'package:riverpod/riverpod.dart';

const _kakuyomuSessionCookiesKey = 'kakuyomu_session_cookies';
const _kakuyomuUsernameKey = 'kakuyomu_username';

/// カクヨムセッション保存リポジトリのプロバイダー。
final kakuyomuSessionRepositoryProvider = Provider<KakuyomuSessionRepository>(
  (ref) => KakuyomuSessionRepository(),
);

/// カクヨムのログインセッションを Secure Storage に保存するリポジトリ。
class KakuyomuSessionRepository {
  /// コンストラクタ。
  KakuyomuSessionRepository({FlutterSecureStorage? storage})
    : _storage = storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  /// カクヨムへ送信可能な Cookie だけを保存する。
  Future<void> saveCookies(List<KakuyomuSessionCookie> cookies) async {
    final filtered = cookies
        .where((cookie) => cookie.belongsToKakuyomu && !cookie.isExpired)
        .map((cookie) => cookie.toJson())
        .toList(growable: false);

    await _storage.write(
      key: _kakuyomuSessionCookiesKey,
      value: jsonEncode(filtered),
    );
  }

  /// 保存済み Cookie を取得する。
  ///
  /// 壊れた保存データがあった場合は安全のため空リストとして扱う。
  Future<List<KakuyomuSessionCookie>> getCookies() async {
    final encoded = await _storage.read(key: _kakuyomuSessionCookiesKey);
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<dynamic>) return const [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(
            (json) => KakuyomuSessionCookie.fromJson(
              Map<String, Object?>.from(json),
            ),
          )
          .where((cookie) => cookie.belongsToKakuyomu && !cookie.isExpired)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  /// 有効期限内の Cookie が保存されているか確認する。
  Future<bool> hasCookies() async => (await getCookies()).isNotEmpty;

  /// カクヨム用 Cookie ヘッダーを生成する。
  Future<String?> buildCookieHeader() async {
    final cookies = await getCookies();
    if (cookies.isEmpty) return null;

    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  /// 表示用ユーザー名を保存する。
  Future<void> saveUsername(String username) =>
      _storage.write(key: _kakuyomuUsernameKey, value: username);

  /// 表示用ユーザー名を取得する。
  Future<String?> getUsername() => _storage.read(key: _kakuyomuUsernameKey);

  /// Novelty が保持するカクヨム認証情報をすべて削除する。
  Future<void> clearAll() async {
    // Windows の Secure Storage 実装で書き込み競合を起こさないよう直列に削除する。
    await _storage.delete(key: _kakuyomuSessionCookiesKey);
    await _storage.delete(key: _kakuyomuUsernameKey);
  }
}
