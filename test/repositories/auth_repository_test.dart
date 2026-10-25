import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/auth_repository.dart';

class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  late Completer<void> _readStarted;
  late Completer<void> _allowRead;
  bool _pauseNextRead = false;

  void pauseNextRead() {
    _readStarted = Completer<void>();
    _allowRead = Completer<void>();
    _pauseNextRead = true;
  }

  Future<void> get readPaused => _readStarted.future;

  void releaseRead() => _allowRead.complete();

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
  }) async {
    final value = values[key];
    if (_pauseNextRead) {
      _pauseNextRead = false;
      _readStarted.complete();
      await _allowRead.future;
    }
    return value;
  }

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

    test('検証中に別アカウントへ切り替わった場合は新しいセッションを消さない', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      await repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );

      final cleared = await repository.clearAllIfSessionCookieHeaderMatches(
        'ks2=old-ks2; ses=old-ses; userl=old-userl',
      );

      expect(cleared, isFalse);
      expect(await repository.getNarouid(), 'new-reader');
      expect(
        await repository.buildCookieHeader(),
        'ks2=new-ks2; ses=new-ses; userl=new-userl',
      );
    });

    test('検証したセッションCookieと一致する場合だけ認証情報を消去する', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );

      final cleared = await repository.clearAllIfSessionCookieHeaderMatches(
        'ks2=ks2-token; ses=ses-token; userl=userl-token',
      );

      expect(cleared, isTrue);
      expect(await repository.hasSessionCookies(), isFalse);
      expect(await repository.getNarouid(), isNull);
      expect(storage.values, isEmpty);
    });

    test('同じログイン中でも古いCookieへの失効応答で更新Cookieを消さない', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );
      final generation = (await repository.getSessionSnapshot())!.generation;

      await repository.updateSessionCookieHeaders([
        'ses=rotated-ses; Path=/; Secure',
      ]);

      final cleared = await repository
          .clearAllIfSessionCookieHeaderAndGenerationMatches(
            generation,
            'ks2=ks2-token; ses=ses-token; userl=userl-token',
          );

      expect(cleared, isFalse);
      expect(await repository.hasSessionCookies(), isTrue);
      expect(
        await repository.buildCookieHeader(),
        'ks2=ks2-token; ses=rotated-ses; userl=userl-token',
      );
    });

    test('現在のCookieとログイン世代が一致すると失効応答で削除できる', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );
      final generation = (await repository.getSessionSnapshot())!.generation;

      final cleared = await repository
          .clearAllIfSessionCookieHeaderAndGenerationMatches(
            generation,
            'ks2=ks2-token; ses=ses-token; userl=userl-token',
          );

      expect(cleared, isTrue);
      expect(await repository.hasSessionCookies(), isFalse);
    });

    test('再ログイン後は古い世代の失効応答で新しいセッションを消さない', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      final oldGeneration = (await repository.getSessionSnapshot())!.generation;
      await repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );

      final cleared = await repository
          .clearAllIfSessionCookieHeaderAndGenerationMatches(
            oldGeneration,
            'ks2=old-ks2; ses=old-ses; userl=old-userl',
          );

      expect(cleared, isFalse);
      expect(await repository.getNarouid(), 'new-reader');
      expect(
        await repository.buildCookieHeader(),
        'ks2=new-ks2; ses=new-ses; userl=new-userl',
      );
    });

    test('同じCookieで再ログインした後も古い世代の失効応答で消さない', () async {
      const cookieHeader = 'ks2=same-ks2; ses=same-ses; userl=same-userl';
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'same-ks2',
        ses: 'same-ses',
        userl: 'same-userl',
        rememberSession: true,
      );
      final oldGeneration = (await repository.getSessionSnapshot())!.generation;
      await repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'same-ks2',
        ses: 'same-ses',
        userl: 'same-userl',
        rememberSession: true,
      );

      final cleared = await repository
          .clearAllIfSessionCookieHeaderAndGenerationMatches(
            oldGeneration,
            cookieHeader,
          );

      expect(cleared, isFalse);
      expect((await repository.getSessionSnapshot())?.narouid, 'new-reader');
    });

    test('Cookie更新中に別アカウントでログインしても新しいセッションを保つ', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      storage.pauseNextRead();

      final delayedCookieUpdate = repository.updateSessionCookieHeaders([
        'ses=old-rotated-ses; Path=/; Secure',
      ]);
      await storage.readPaused;
      final newLogin = repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );
      await Future<void>.delayed(Duration.zero);
      storage.releaseRead();
      await Future.wait([delayedCookieUpdate, newLogin]);

      expect(await repository.getNarouid(), 'new-reader');
      expect(await repository.getSessionCookies(), {
        'ks2': 'new-ks2',
        'ses': 'new-ses',
        'userl': 'new-userl',
      });
    });

    test('別アカウントのログイン中にCookieヘッダーへ複数セッションを混ぜない', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      storage.pauseNextRead();

      final oldHeader = repository.buildCookieHeader();
      await storage.readPaused;
      final newLogin = repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );
      await Future<void>.delayed(Duration.zero);
      storage.releaseRead();

      expect(await oldHeader, 'ks2=old-ks2; ses=old-ses; userl=old-userl');
      await newLogin;
    });

    test('アカウント情報とCookieを同一セッションのsnapshotとして読む', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      storage.pauseNextRead();

      final oldSnapshotFuture = repository.getSessionSnapshot();
      await storage.readPaused;
      final newLogin = repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );
      storage.releaseRead();

      final oldSnapshot = await oldSnapshotFuture;
      await newLogin;

      expect(oldSnapshot?.narouid, 'old-reader');
      expect(oldSnapshot?.username, '旧利用者');
      expect(
        oldSnapshot?.cookieHeader,
        'ks2=old-ks2; ses=old-ses; userl=old-userl',
      );
      expect(oldSnapshot?.generation, 1);

      final newSnapshot = await repository.getSessionSnapshot();
      expect(newSnapshot?.narouid, 'new-reader');
      expect(newSnapshot?.username, '新利用者');
      expect(
        newSnapshot?.cookieHeader,
        'ks2=new-ks2; ses=new-ses; userl=new-userl',
      );
      expect(newSnapshot?.generation, 2);
    });

    test('一致したセッションの処理中は再ログインを待たせる', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );
      final snapshot = (await repository.getSessionSnapshot())!;
      final operationStarted = Completer<void>();
      final releaseOperation = Completer<void>();
      var reloginCompleted = false;

      final guardedOperation = repository.runIfSessionSnapshotMatches(
        snapshot,
        () async {
          operationStarted.complete();
          await releaseOperation.future;
        },
      );
      await operationStarted.future;
      final relogin = repository
          .saveSession(
            narouid: 'new-reader',
            username: '新利用者',
            ks2: 'new-ks2',
            ses: 'new-ses',
            userl: 'new-userl',
            rememberSession: true,
          )
          .then((_) => reloginCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(reloginCompleted, isFalse);
      releaseOperation.complete();
      expect(await guardedOperation, isTrue);
      await relogin;
      expect(await repository.getNarouid(), 'new-reader');
    });

    test('一致したセッションの処理中も認証状態の読み取りを待たせない', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );
      final snapshot = (await repository.getSessionSnapshot())!;
      final operationStarted = Completer<void>();
      final releaseOperation = Completer<void>();
      final guardedOperation = repository.runIfSessionSnapshotMatches(
        snapshot,
        () async {
          operationStarted.complete();
          await releaseOperation.future;
        },
      );
      await operationStarted.future;

      var readCompleted = false;
      final read = repository.getSessionSnapshot().then((value) {
        readCompleted = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      final wasReadAvailable = readCompleted;
      releaseOperation.complete();
      expect(await guardedOperation, isTrue);

      expect(wasReadAvailable, isTrue);
      expect((await read)?.cookieHeader, snapshot.cookieHeader);
    });

    test('処理開始前に世代が変わった場合はコールバックを実行しない', () async {
      await repository.saveSession(
        narouid: 'old-reader',
        username: '旧利用者',
        ks2: 'old-ks2',
        ses: 'old-ses',
        userl: 'old-userl',
        rememberSession: true,
      );
      final snapshot = (await repository.getSessionSnapshot())!;
      await repository.saveSession(
        narouid: 'new-reader',
        username: '新利用者',
        ks2: 'new-ks2',
        ses: 'new-ses',
        userl: 'new-userl',
        rememberSession: true,
      );
      var operationRan = false;

      final ran = await repository.runIfSessionSnapshotMatches(
        snapshot,
        () async {
          operationRan = true;
        },
      );

      expect(ran, isFalse);
      expect(operationRan, isFalse);
      expect(await repository.getNarouid(), 'new-reader');
    });

    test('個別の認証情報更新でもsnapshotの世代番号を進める', () async {
      await repository.saveSession(
        narouid: 'reader-id',
        username: '読者',
        ks2: 'ks2-token',
        ses: 'ses-token',
        userl: 'userl-token',
        rememberSession: true,
      );
      final initialGeneration =
          (await repository.getSessionSnapshot())!.generation;

      await repository.saveNarouid('updated-reader-id');
      final idUpdateGeneration =
          (await repository.getSessionSnapshot())!.generation;
      await repository.saveUsername('更新済み読者');
      final usernameUpdateGeneration =
          (await repository.getSessionSnapshot())!.generation;
      await repository.saveSessionCookies(
        ks2: 'updated-ks2',
        ses: 'updated-ses',
        userl: 'updated-userl',
      );
      final cookieUpdateGeneration =
          (await repository.getSessionSnapshot())!.generation;

      expect(idUpdateGeneration, initialGeneration + 1);
      expect(usernameUpdateGeneration, idUpdateGeneration + 1);
      expect(cookieUpdateGeneration, usernameUpdateGeneration + 1);
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
