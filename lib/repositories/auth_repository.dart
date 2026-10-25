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

  /// セッション情報を選択された保存期間で記録する。
  Future<void> saveSession({
    required String narouid,
    required String username,
    required String ks2,
    required String ses,
    required String userl,
    required bool rememberSession,
  }) async {
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
    await saveNarouid(narouid);
    await saveUsername(username);
    await saveSessionCookies(ks2: ks2, ses: ses, userl: userl);
  }

  /// ログインIDを保存する。
  Future<void> saveNarouid(String narouid) {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      _volatileSession = volatileSession.copyWith(narouid: narouid);
      return Future<void>.value();
    }
    return _storage.write(key: _narouidKey, value: narouid);
  }

  /// ログインIDを取得する。
  Future<String?> getNarouid() => _volatileSession != null
      ? Future<String?>.value(_volatileSession!.narouid)
      : _storage.read(key: _narouidKey);

  /// ユーザー名を保存する。
  Future<void> saveUsername(String username) {
    final volatileSession = _volatileSession;
    if (volatileSession != null) {
      _volatileSession = volatileSession.copyWith(username: username);
      return Future<void>.value();
    }
    return _storage.write(key: _usernameKey, value: username);
  }

  /// ユーザー名を取得する。
  Future<String?> getUsername() => _volatileSession != null
      ? Future<String?>.value(_volatileSession!.username)
      : _storage.read(key: _usernameKey);

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
  Future<Map<String, String>?> getSessionCookies() async {
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

  /// セッションCookieが保存されているか確認する。
  Future<bool> hasSessionCookies() async {
    final cookies = await getSessionCookies();
    return cookies != null;
  }

  /// なろうから返った認証Cookieの更新を保存する。
  Future<void> updateSessionCookieHeaders(List<String>? headers) async {
    if (headers == null || headers.isEmpty) return;
    final sessionHeaders = headers.where((header) {
      final separator = header.indexOf('=');
      return separator > 0 &&
          _narouSessionCookieNames.contains(
            header.substring(0, separator).trim(),
          );
    }).toList();
    if (sessionHeaders.isEmpty) return;

    final previous = await getSessionCookies();
    if (previous == null) return;
    final updated = Map<String, String>.of(previous);
    mergeSetCookieHeaders(
      updated,
      sessionHeaders,
      allowedNames: _narouSessionCookieNames,
    );
    if (_narouSessionCookieNames.any(
      (name) => updated[name]?.isNotEmpty != true,
    )) {
      await clearAll();
      return;
    }
    if (_narouSessionCookieNames.any(
      (name) => updated[name] != previous[name],
    )) {
      await saveSessionCookies(
        ks2: updated['ks2']!,
        ses: updated['ses']!,
        userl: updated['userl']!,
      );
    }
  }

  /// 認証情報をすべて削除する（ログアウト時に使用）。
  Future<void> clearAll() async {
    _volatileSession = null;
    await _clearPersistedValues();
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
    final ks2 = cookies['ks2'];
    final ses = cookies['ses'];
    final userl = cookies['userl'];
    return 'ks2=$ks2; ses=$ses; userl=$userl';
  }
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
