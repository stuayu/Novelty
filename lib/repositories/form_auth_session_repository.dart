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
  int _sessionGeneration = 0;
  Future<void> _sessionOperationQueue = Future<void>.value();
  Future<void> _sessionCommitQueue = Future<void>.value();

  /// アカウント識別子と、サイトが発行した全Cookieを保存する。
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      _sessionGeneration++;
      await _storage.write(key: _cookiesKey, value: jsonEncode(cookies));
      await _storage.write(key: _accountIdKey, value: accountId);
    }),
  );

  /// 保存済みCookieを取得する。壊れた値は空として扱う。
  Future<Map<String, String>> getCookies() =>
      _serializeSessionOperation(_getCookies);

  Future<Map<String, String>> _getCookies() async {
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
  Future<String?> getAccountId() =>
      _serializeSessionOperation(() => _storage.read(key: _accountIdKey));

  /// アカウント、Cookie、ログイン世代を一貫して取得する。
  Future<FormAuthSessionSnapshot?> getSessionSnapshot() =>
      _serializeSessionOperation(_getSessionSnapshot);

  Future<FormAuthSessionSnapshot?> _getSessionSnapshot() async {
    final cookies = await _getCookies();
    if (cookies.isEmpty) return null;
    final accountId = await _storage.read(key: _accountIdKey);
    if (accountId == null) return null;
    return FormAuthSessionSnapshot(
      accountId: accountId,
      cookieHeader: _buildCookieHeader(cookies)!,
      generation: _sessionGeneration,
    );
  }

  /// [snapshot]と同じログイン中にだけ[operation]を直列に実行する。
  ///
  /// セッション保存や削除が処理中に割り込むことを防ぐ。通常の読み取りは
  /// 処理中も続けられる。コールバック内でこのリポジトリを呼び出さないこと。
  Future<bool> runIfSessionSnapshotMatches(
    FormAuthSessionSnapshot snapshot,
    Future<void> Function() operation,
  ) => _serializeSessionCommit(() async {
    final current = await _serializeSessionOperation(_getSessionSnapshot);
    if (current == null ||
        current.generation != snapshot.generation ||
        current.accountId != snapshot.accountId ||
        current.cookieHeader != snapshot.cookieHeader) {
      return false;
    }
    await operation();
    return true;
  });

  /// Cookieが1件以上保存されているか確認する。
  Future<bool> hasCookies() async => (await getCookies()).isNotEmpty;

  /// HTTP Cookieヘッダーを生成する。
  Future<String?> buildCookieHeader() => _serializeSessionOperation(() async {
    return _buildCookieHeader(await _getCookies());
  });

  String? _buildCookieHeader(Map<String, String> cookies) {
    if (cookies.isEmpty) return null;
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  /// 同期を開始した時点のCookie・ログイン世代と一致するときだけ削除する。
  Future<bool> clearAllIfSessionCookieHeaderAndGenerationMatches(
    int expectedGeneration,
    String expectedCookieHeader,
  ) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      if (_sessionGeneration != expectedGeneration) return false;
      final currentCookieHeader = _buildCookieHeader(await _getCookies());
      if (currentCookieHeader != expectedCookieHeader ||
          _sessionGeneration != expectedGeneration) {
        return false;
      }
      await _clearAll();
      return true;
    }),
  );

  /// 保存済み認証情報をすべて削除する。
  Future<void> clearAll() =>
      _serializeSessionCommit(() => _serializeSessionOperation(_clearAll));

  Future<void> _clearAll() async {
    _sessionGeneration++;
    await _storage.delete(key: _cookiesKey);
    await _storage.delete(key: _accountIdKey);
  }

  Future<T> _serializeSessionOperation<T>(Future<T> Function() operation) {
    final result = _sessionOperationQueue.then((_) => operation());
    _sessionOperationQueue = result
        .then<void>((_) {})
        .catchError((Object _) {});
    return result;
  }

  Future<T> _serializeSessionCommit<T>(Future<T> Function() operation) {
    final result = _sessionCommitQueue.then((_) => operation());
    _sessionCommitQueue = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}

/// フォーム認証済みアカウントの一貫した読み取り結果。
class FormAuthSessionSnapshot {
  /// スナップショットを作成する。
  const FormAuthSessionSnapshot({
    required this.accountId,
    required this.cookieHeader,
    required this.generation,
  });

  /// サイトのアカウント識別子。
  final String accountId;

  /// 保存済みセッションCookie。
  final String cookieHeader;

  /// プロセス内のログイン世代。
  final int generation;
}
