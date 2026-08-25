import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:riverpod/misc.dart' show ProviderFamily;
import 'package:riverpod/riverpod.dart';

/// サイト別フォーム認証セッションのリポジトリプロバイダー。
final ProviderFamily<FormAuthSessionRepository, NovelSource>
formAuthSessionRepositoryProvider =
    Provider.family<FormAuthSessionRepository, NovelSource>(
      (ref, source) => FormAuthSessionRepository(source: source),
    );

/// フォームPOST認証サイトのセッションをSecure Storageへ保存するリポジトリ。
class FormAuthSessionRepository {
  /// コンストラクタ。
  FormAuthSessionRepository({
    required NovelSource source,
    FlutterSecureStorage? storage,
  }) : _cookiesKey = '${source.dbId}_session_cookies',
       _accountIdKey = '${source.dbId}_account_id',
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           );

  final String _cookiesKey;
  final String _accountIdKey;
  final FlutterSecureStorage _storage;

  /// アカウント識別子と、サイトが発行した全Cookieを保存する。
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    // Windows実装は全キーを単一ファイルへ書くため、必ず直列に保存する。
    await _storage.write(key: _cookiesKey, value: jsonEncode(cookies));
    await _storage.write(key: _accountIdKey, value: accountId);
  }

  /// 保存済みCookieを取得する。壊れた値は空として扱う。
  Future<Map<String, String>> getCookies() async {
    final encoded = await _storage.read(key: _cookiesKey);
    if (encoded == null || encoded.isEmpty) return const {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return const {};
      final cookies = <String, String>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (entry.key.isNotEmpty && value is String && value.isNotEmpty) {
          cookies[entry.key] = value;
        }
      }
      return cookies;
    } on FormatException {
      return const {};
    }
  }

  /// 保存済みアカウント識別子を取得する。
  Future<String?> getAccountId() => _storage.read(key: _accountIdKey);

  /// Cookieが1件以上保存されているか確認する。
  Future<bool> hasCookies() async => (await getCookies()).isNotEmpty;

  /// HTTP Cookieヘッダーを生成する。
  Future<String?> buildCookieHeader() async {
    final cookies = await getCookies();
    if (cookies.isEmpty) return null;
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  /// 保存済み認証情報をすべて削除する。
  Future<void> clearAll() async {
    // 保存時と同じWindows実装の競合を避けるため、削除も直列に行う。
    await _storage.delete(key: _cookiesKey);
    await _storage.delete(key: _accountIdKey);
  }
}
