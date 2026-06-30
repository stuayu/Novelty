import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

const _narouidKey = 'narou_narouid';
const _cookieKs2Key = 'narou_cookie_ks2';
const _cookieSesKey = 'narou_cookie_ses';
const _cookieUserlKey = 'narou_cookie_userl';
const _usernameKey = 'narou_username';

@Riverpod(keepAlive: true)
/// 認証リポジトリのプロバイダー。
AuthRepository authRepository(Ref ref) => AuthRepository();

/// なろうの認証情報をKeyChain/Android Keystoreに安全に保存・取得するリポジトリ。
///
/// 保存するデータ：
/// - ログインID (narouid)
/// - セッションCookie (ks2, ses, userl)
/// - ユーザー名
class AuthRepository {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// ログインIDを保存する。
  Future<void> saveNarouid(String narouid) =>
      _storage.write(key: _narouidKey, value: narouid);

  /// ログインIDを取得する。
  Future<String?> getNarouid() => _storage.read(key: _narouidKey);

  /// ユーザー名を保存する。
  Future<void> saveUsername(String username) =>
      _storage.write(key: _usernameKey, value: username);

  /// ユーザー名を取得する。
  Future<String?> getUsername() => _storage.read(key: _usernameKey);

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
    await Future.wait([
      _storage.write(key: _cookieKs2Key, value: ks2),
      _storage.write(key: _cookieSesKey, value: ses),
      _storage.write(key: _cookieUserlKey, value: userl),
    ]);
  }

  /// 保存済みのセッションCookieをすべて取得する。
  ///
  /// いずれかのCookieが未保存の場合は`null`を返す。
  Future<Map<String, String>?> getSessionCookies() async {
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

  /// 認証情報をすべて削除する（ログアウト時に使用）。
  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _narouidKey),
      _storage.delete(key: _cookieKs2Key),
      _storage.delete(key: _cookieSesKey),
      _storage.delete(key: _cookieUserlKey),
      _storage.delete(key: _usernameKey),
    ]);
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
