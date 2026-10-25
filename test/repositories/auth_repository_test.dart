import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/auth_repository.dart';

class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  group('AuthRepository', () {
    late _MemorySecureStorage storage;
    late AuthRepository repository;

    setUp(() {
      storage = _MemorySecureStorage();
      repository = AuthRepository(storage: storage);
    });

    test('ログイン状態を維持しない場合、稼働中だけ使えて永続領域を空にする', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );

      await repository.saveSession(
        narouid: 'temporary-reader',
        username: '一時利用者',
        ks2: 'temporary-ks2',
        ses: 'temporary-ses',
        userl: 'temporary-userl',
        rememberSession: false,
      );

      expect(storage.values, isEmpty);
      expect(await repository.getNarouid(), 'temporary-reader');
      expect(await repository.getUsername(), '一時利用者');
      expect(await repository.getSessionCookies(), {
        'ks2': 'temporary-ks2',
        'ses': 'temporary-ses',
        'userl': 'temporary-userl',
      });

      final restartedRepository = AuthRepository(storage: storage);
      expect(await restartedRepository.hasSessionCookies(), isFalse);
      expect(await restartedRepository.getNarouid(), isNull);
    });

    test('一時セッション中のCookie更新を永続領域へ書き込まない', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: false,
      );

      await repository.saveSessionCookies(
        ks2: 'rotated-ks2',
        ses: 'rotated-ses',
        userl: 'rotated-userl',
      );

      expect(storage.values, isEmpty);
      expect(await repository.getSessionCookies(), {
        'ks2': 'rotated-ks2',
        'ses': 'rotated-ses',
        'userl': 'rotated-userl',
      });
    });

    test('なろうの認証応答で更新されたCookieだけ保存する', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );

      await repository.updateSessionCookieHeaders([
        'ks2=new-ks2; Path=/; Secure',
        'tracking=ignored; Path=/',
      ]);

      expect(await repository.getSessionCookies(), {
        'ks2': 'new-ks2',
        'ses': 'old-ses',
        'userl': 'old-userl',
      });
    });

    test('期限切れの認証Cookieを受け取ったらセッションを消去する', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );

      await repository.updateSessionCookieHeaders([
        'ses=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ]);

      expect(await repository.hasSessionCookies(), isFalse);
      expect(await repository.getNarouid(), isNull);
      expect(storage.values, isEmpty);
    });

    test('一時セッションの後にログイン状態を維持すると永続保存へ戻る', () async {
      await repository.saveSession(
        narouid: 'temporary-reader',
        username: '一時利用者',
        ks2: 'temporary-ks2',
        ses: 'temporary-ses',
        userl: 'temporary-userl',
        rememberSession: false,
      );

      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );

      expect(await repository.getNarouid(), 'reader-id');
      expect(await repository.getUsername(), '読者');
      expect(await repository.hasSessionCookies(), isTrue);
      expect(storage.values, isNotEmpty);
      expect(await AuthRepository(storage: storage).getNarouid(), 'reader-id');
    });

    test('ログアウトすると一時セッションを破棄する', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: false,
      );

      await repository.clearAll();

      expect(await repository.getNarouid(), isNull);
      expect(await repository.getUsername(), isNull);
      expect(await repository.getSessionCookies(), isNull);
      expect(storage.values, isEmpty);
    });
  });
}
