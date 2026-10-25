import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:novelty/utils/http_cookie.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

const _narouidKey = 'narou_narouid';
const _cookieKs2Key = 'narou_cookie_ks2';
const _cookieSesKey = 'narou_cookie_ses';
const _cookieUserlKey = 'narou_cookie_userl';
const _usernameKey = 'narou_username';
const _narouSessionCookieNames = <String>{'ks2', 'ses', 'userl'};

@Riverpod(keepAlive: true)
/// 認証リポジトリのプロバイダー。
AuthRepository authRepository(Ref ref) => AuthRepository();

/// なろうの認証情報をSecure Storageまたはメモリで保持するリポジトリ。
///
/// 保存するデータ：
/// - ログインID (narouid)
/// - セッションCookie (ks2, ses, userl)
/// - ユーザー名
class AuthRepository {
  /// Secure Storageを指定できる認証情報リポジトリを作成する。
  AuthRepository({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  _VolatileSession? _volatileSession;
  int _sessionGeneration = 0;
  Future<void> _sessionOperationQueue = Future<void>.value();
  Future<void> _sessionCommitQueue = Future<void>.value();

  /// セッション情報を選択された保存期間で記録する。
  Future<void> saveSession({
    required String narouid,
    required String username,
    required String ks2,
    required String ses,
    required String userl,
    required bool rememberSession,
  }) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      _sessionGeneration++;
      if (!rememberSession) {
        await _saveVolatileSession(
          narouid: narouid,
          username: username,
          ks2: ks2,
          ses: ses,
          userl: userl,
        );
        return;
      }

      _volatileSession = null;
      await _saveNarouid(narouid);
      await _saveUsername(username);
      await _saveSessionCookies(ks2: ks2, ses: ses, userl: userl);
    }),
  );

  /// ログインIDを保存する。
  Future<void> saveNarouid(String narouid) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      _sessionGeneration++;
      await _saveNarouid(narouid);
    }),
  );

  Future<void> _saveNarouid(String narouid) async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      _volatileSession = volatileSession.copyWith(narouid: narouid);
      return;
    }
    await _storage.write(key: _narouidKey, value: narouid);
  }

  /// ログインIDを取得する。
  Future<String?> getNarouid() => _serializeSessionOperation(() async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) return volatileSession.narouid;
    return _storage.read(key: _narouidKey);
  });

  /// ユーザー名を保存する。
  Future<void> saveUsername(String username) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      _sessionGeneration++;
      await _saveUsername(username);
    }),
  );

  Future<void> _saveUsername(String username) async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      _volatileSession = volatileSession.copyWith(username: username);
      return;
    }
    await _storage.write(key: _usernameKey, value: username);
  }

  /// ユーザー名を取得する。
  Future<String?> getUsername() => _serializeSessionOperation(() async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) return volatileSession.username;
    return _storage.read(key: _usernameKey);
  });

  /// ログイン状態をアプリ終了までメモリ上だけで保持する。
  Future<void> _saveVolatileSession({
    required String narouid,
    required String username,
    required String ks2,
    required String ses,
    required String userl,
  }) async {
    await _clearPersistedValues();
    _volatileSession = _VolatileSession(
      narouid: narouid,
      username: username,
      sessionCookies: {'ks2': ks2, 'ses': ses, 'userl': userl},
    );
  }

  /// セッションCookieをまとめて保存する。
  ///
  /// なろうの認証に必要な3つのCookieを保存する：
  /// - `ks2`: 永続セッションCookie (1年間有効)
  /// - `ses`: セッションCookie (HttpOnly)
  /// - `userl`: ユーザー識別Cookie (HttpOnly)
  Future<void> saveSessionCookies({
    required String ks2,
    required String ses,
    required String userl,
  }) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      _sessionGeneration++;
      await _saveSessionCookies(ks2: ks2, ses: ses, userl: userl);
    }),
  );

  Future<void> _saveSessionCookies({
    required String ks2,
    required String ses,
    required String userl,
  }) async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      _volatileSession = volatileSession.copyWith(
        sessionCookies: {'ks2': ks2, 'ses': ses, 'userl': userl},
      );
      return;
    }
    // flutter_secure_storageのWindows実装は全キーを単一ファイルへ
    // 読み込み→更新→保存で書き込むため、並列に書き込むと後勝ちで
    // 他のキーが消える。必ず直列に書き込むこと。
    await _storage.write(key: _cookieKs2Key, value: ks2);
    await _storage.write(key: _cookieSesKey, value: ses);
    await _storage.write(key: _cookieUserlKey, value: userl);
  }

  /// 保存済みのセッションCookieをすべて取得する。
  ///
  /// いずれかのCookieが未保存の場合は`null`を返す。
  Future<Map<String, String>?> getSessionCookies() =>
      _serializeSessionOperation(_getSessionCookies);

  Future<Map<String, String>?> _getSessionCookies() async {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      return Map<String, String>.of(volatileSession.sessionCookies);
    }
    final ks2 = await _storage.read(key: _cookieKs2Key);
    final ses = await _storage.read(key: _cookieSesKey);
    final userl = await _storage.read(key: _cookieUserlKey);
    if (ks2 == null || ses == null || userl == null) return null;
    return {'ks2': ks2, 'ses': ses, 'userl': userl};
  }

  /// 認証状態の表示に使うアカウント情報とCookieを一貫して取得する。
  Future<AuthSessionSnapshot?> getSessionSnapshot() =>
      _serializeSessionOperation(_getSessionSnapshot);

  Future<AuthSessionSnapshot?> _getSessionSnapshot() async {
    final cookies = await _getSessionCookies();
    if (cookies == null) return null;

    final volatileSession = _volatileSession;
    final narouid =
        volatileSession?.narouid ?? await _storage.read(key: _narouidKey);
    final username =
        volatileSession?.username ?? await _storage.read(key: _usernameKey);
    if (narouid == null || username == null) return null;

    return AuthSessionSnapshot(
      narouid: narouid,
      username: username,
      cookieHeader: _buildCookieHeader(cookies),
      generation: _sessionGeneration,
    );
  }

  /// [snapshot]と同じログイン中にだけ[operation]を直列に実行する。
  ///
  /// セッションの保存・削除を待たせて処理途中のアカウント切替を防ぐ。
  /// 通常の読み取りは処理中も続けられる。コールバック内ではこのリポジトリを
  /// 呼び出さないこと。
  Future<bool> runIfSessionSnapshotMatches(
    AuthSessionSnapshot snapshot,
    Future<void> Function() operation,
  ) => _serializeSessionCommit(() async {
    final current = await _serializeSessionOperation(_getSessionSnapshot);
    if (current == null ||
        current.generation != snapshot.generation ||
        current.narouid != snapshot.narouid) {
      return false;
    }
    await operation();
    return true;
  });

  /// セッションCookieが保存されているか確認する。
  Future<bool> hasSessionCookies() async {
    final cookies = await getSessionCookies();
    return cookies != null;
  }

  /// なろうから返った認証Cookieの更新を保存する。
  Future<void> updateSessionCookieHeaders(
    List<String>? headers, {
    String? expectedCookieHeader,
  }) => _serializeSessionCommit(
    () => _serializeSessionOperation(
      () => _updateSessionCookieHeaders(
        headers,
        expectedCookieHeader: expectedCookieHeader,
      ),
    ),
  );

  Future<void> _updateSessionCookieHeaders(
    List<String>? headers, {
    String? expectedCookieHeader,
  }) async {
    if (headers == null || headers.isEmpty) return;
    final sessionHeaders = headers.where((header) {
      final separator = header.indexOf('=');
      return separator > 0 &&
          _narouSessionCookieNames.contains(
            header.substring(0, separator).trim(),
          );
    }).toList();
    if (sessionHeaders.isEmpty) return;

    final previous = await _getSessionCookies();
    if (previous == null) return;
    if (expectedCookieHeader != null &&
        _buildCookieHeader(previous) != expectedCookieHeader) {
      return;
    }
    final updated = Map<String, String>.of(previous);
    mergeSetCookieHeaders(
      updated,
      sessionHeaders,
      allowedNames: _narouSessionCookieNames,
    );
    if (_narouSessionCookieNames.any(
      (name) => updated[name]?.isNotEmpty != true,
    )) {
      await _clearAll();
      return;
    }
    if (_narouSessionCookieNames.any(
      (name) => updated[name] != previous[name],
    )) {
      await _saveSessionCookies(
        ks2: updated['ks2']!,
        ses: updated['ses']!,
        userl: updated['userl']!,
      );
    }
  }

  /// 認証情報をすべて削除する（ログアウト時に使用）。
  Future<void> clearAll() =>
      _serializeSessionCommit(() => _serializeSessionOperation(_clearAll));

  /// 検証時と同じセッションCookieが保存されている場合だけ認証情報を削除する。
  Future<bool> clearAllIfSessionCookieHeaderMatches(
    String expectedCookieHeader,
  ) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      final current = await _getSessionCookies();
      if (current == null ||
          _buildCookieHeader(current) != expectedCookieHeader) {
        return false;
      }
      await _clearAll();
      return true;
    }),
  );

  /// 失効応答を受けたリクエストと同じCookie・ログイン世代の場合だけ削除する。
  ///
  /// 並行リクエストによるCookie更新や別アカウントへの切替から保護する。
  Future<bool> clearAllIfSessionCookieHeaderAndGenerationMatches(
    int expectedGeneration,
    String expectedCookieHeader,
  ) => _serializeSessionCommit(
    () => _serializeSessionOperation(() async {
      if (_sessionGeneration != expectedGeneration) return false;
      final current = await _getSessionCookies();
      if (current == null ||
          _sessionGeneration != expectedGeneration ||
          _buildCookieHeader(current) != expectedCookieHeader) {
        return false;
      }
      await _clearAll();
      return true;
    }),
  );

  Future<void> _clearAll() async {
    _sessionGeneration++;
    _volatileSession = null;
    await _clearPersistedValues();
  }

  Future<T> _serializeSessionOperation<T>(Future<T> Function() operation) {
    final result = _sessionOperationQueue.then((_) => operation());
    _sessionOperationQueue = result
        .then<void>((_) {})
        .catchError(
          (Object _) {},
        );
    return result;
  }

  Future<T> _serializeSessionCommit<T>(Future<T> Function() operation) {
    final result = _sessionCommitQueue.then((_) => operation());
    _sessionCommitQueue = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  Future<void> _clearPersistedValues() async {
    // 保存時と同じ理由（Windows実装の単一ファイル競合）で直列に削除する。
    await _storage.delete(key: _narouidKey);
    await _storage.delete(key: _cookieKs2Key);
    await _storage.delete(key: _cookieSesKey);
    await _storage.delete(key: _cookieUserlKey);
    await _storage.delete(key: _usernameKey);
  }

  /// Cookieヘッダー文字列を組み立てる。
  ///
  /// なろうのHTTPリクエストに付与するCookieヘッダー値を返す。
  /// セッションがない場合は`null`を返す。
  Future<String?> buildCookieHeader() async {
    final cookies = await getSessionCookies();
    if (cookies == null) return null;
    return _buildCookieHeader(cookies);
  }

  String _buildCookieHeader(Map<String, String> cookies) {
    final ks2 = cookies['ks2'];
    final ses = cookies['ses'];
    final userl = cookies['userl'];
    return 'ks2=$ks2; ses=$ses; userl=$userl';
  }
}

/// 認証済みアカウントの一貫した読み取り結果。
class AuthSessionSnapshot {
  /// スナップショットを作成する。
  const AuthSessionSnapshot({
    required this.narouid,
    required this.username,
    required this.cookieHeader,
    required this.generation,
  });

  /// なろうのログインID。
  final String narouid;

  /// なろうに登録された表示名。
  final String username;

  /// 現在保存されているセッションCookie。
  final String cookieHeader;

  /// 完全なログイン／ログアウト時に進む、プロセス内の世代番号。
  final int generation;
}

class _VolatileSession {
  _VolatileSession({
    required this.narouid,
    required this.username,
    required Map<String, String> sessionCookies,
  }) : sessionCookies = Map<String, String>.unmodifiable(sessionCookies);

  final String narouid;
  final String username;
  final Map<String, String> sessionCookies;

  _VolatileSession copyWith({
    String? narouid,
    String? username,
    Map<String, String>? sessionCookies,
  }) => _VolatileSession(
    narouid: narouid ?? this.narouid,
    username: username ?? this.username,
    sessionCookies: sessionCookies ?? this.sessionCookies,
  );
}
