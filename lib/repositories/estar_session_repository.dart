import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:novelty/models/estar_session_cookie.dart';
import 'package:riverpod/riverpod.dart';

const _estarSessionCookiesKey = 'estar_session_cookies';

/// エブリスタセッション保存リポジトリのプロバイダー。
final estarSessionRepositoryProvider = Provider<EstarSessionRepository>(
  (ref) => EstarSessionRepository(),
);

/// エブリスタのログインCookieをSecure Storageへ保存するリポジトリ。
class EstarSessionRepository {
  /// コンストラクタ。
  EstarSessionRepository({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  /// エブリスタ配下の有効なCookieを、名前を限定せず保存する。
  Future<void> saveCookies(List<EstarSessionCookie> cookies) async {
    final filtered = cookies
        .where((cookie) => cookie.belongsToEstar && !cookie.isExpired)
        .map((cookie) => cookie.toJson())
        .toList(growable: false);
    await _storage.write(
      key: _estarSessionCookiesKey,
      value: jsonEncode(filtered),
    );
  }

  /// 保存済みCookieを取得する。壊れた値は空として扱う。
  Future<List<EstarSessionCookie>> getCookies() async {
    final encoded = await _storage.read(key: _estarSessionCookiesKey);
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<dynamic>) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .where(_isValidCookieJson)
          .map(
            (json) => EstarSessionCookie.fromJson(
              Map<String, Object?>.from(json),
            ),
          )
          .where((cookie) => cookie.belongsToEstar && !cookie.isExpired)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  /// 有効なCookieが1件以上保存されているか確認する。
  Future<bool> hasCookies() async => (await getCookies()).isNotEmpty;

  /// 保存済み認証情報を削除する。
  Future<void> clearAll() => _storage.delete(key: _estarSessionCookiesKey);

  bool _isValidCookieJson(Map<String, dynamic> json) {
    if (json['name'] is! String ||
        json['value'] is! String ||
        json['domain'] is! String ||
        json['path'] is! String) {
      return false;
    }
    final expiresDate = json['expiresDate'];
    final isSecure = json['isSecure'];
    final isHttpOnly = json['isHttpOnly'];
    return (expiresDate == null || expiresDate is int) &&
        (isSecure == null || isSecure is bool) &&
        (isHttpOnly == null || isHttpOnly is bool);
  }
}
