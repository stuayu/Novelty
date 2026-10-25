import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/sites/novel_source.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({
    Map<String, String>? values,
    this.onWrite,
    this.onDelete,
  }) : values = values ?? {};

  final Map<String, String> values;
  final Future<void> Function(String key, String? value)? onWrite;
  final Future<void> Function(String key)? onDelete;

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await onWrite?.call(key, value);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await onDelete?.call(key);
    values.remove(key);
  }
}

void main() {
  group('FormAuthSessionRepository', () {
    late _FakeSecureStorage storage;
    late FormAuthSessionRepository repository;

    setUp(() {
      storage = _FakeSecureStorage();
      repository = FormAuthSessionRepository(
        source: NovelSource.alphapolis,
        storage: storage,
      );
    });

    test('Cookie名を限定せず保存しCookieヘッダーを復元する', () async {
      await repository.saveSession(
        accountId: 'reader@example.com',
        cookies: const {'AWSALB': 'alb', 'unknown': 'session'},
      );

      expect(
        await repository.getCookies(),
        const {'AWSALB': 'alb', 'unknown': 'session'},
      );
      expect(
        await repository.buildCookieHeader(),
        'AWSALB=alb; unknown=session',
      );
      expect(await repository.getAccountId(), 'reader@example.com');
    });

    test('Secure Storageへの保存は前の書き込み完了後に次を開始する', () async {
      final events = <String>[];
      final cookiesStarted = Completer<void>();
      final allowCookies = Completer<void>();
      final accountStarted = Completer<void>();

      storage = _FakeSecureStorage(
        onWrite: (key, value) async {
          if (key == 'alphapolis_session_cookies') {
            events.add('cookies');
            cookiesStarted.complete();
            await allowCookies.future;
          } else if (key == 'alphapolis_account_id') {
            events.add('account');
            accountStarted.complete();
          }
        },
      );
      repository = FormAuthSessionRepository(
        source: NovelSource.alphapolis,
        storage: storage,
      );

      final future = repository.saveSession(
        accountId: 'reader@example.com',
        cookies: const {'session': 'value'},
      );
      await cookiesStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(events, ['cookies']);

      allowCookies.complete();
      await accountStarted.future;
      await future;
      expect(events, ['cookies', 'account']);
    });

    test('セッションスナップショットはアカウント・Cookie・世代をまとめて返す', () async {
      await repository.saveSession(
        accountId: 'reader@example.com',
        cookies: const {'session': 'old'},
      );

      final snapshot = await repository.getSessionSnapshot();

      expect(snapshot?.accountId, 'reader@example.com');
      expect(snapshot?.cookieHeader, 'session=old');
      expect(snapshot?.generation, 1);
    });

    test('一致したセッションの処理中は新しいログインを待たせる', () async {
      await repository.saveSession(
        accountId: 'old-reader',
        cookies: const {'session': 'old'},
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
            accountId: 'new-reader',
            cookies: const {'session': 'new'},
          )
          .then((_) => reloginCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(reloginCompleted, isFalse);
      releaseOperation.complete();
      expect(await guardedOperation, isTrue);
      await relogin;
      expect((await repository.getSessionSnapshot())?.accountId, 'new-reader');
    });

    test('一致したセッションの処理中も認証状態の読み取りを待たせない', () async {
      await repository.saveSession(
        accountId: 'reader-id',
        cookies: const {'session': 'current'},
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

    test('同期中に再ログインした場合は古い応答で新しいセッションを消せない', () async {
      await repository.saveSession(
        accountId: 'old-reader',
        cookies: const {'session': 'old'},
      );
      final oldSnapshot = (await repository.getSessionSnapshot())!;
      await repository.saveSession(
        accountId: 'new-reader',
        cookies: const {'session': 'new'},
      );

      final cleared = await repository
          .clearAllIfSessionCookieHeaderAndGenerationMatches(
            oldSnapshot.generation,
            oldSnapshot.cookieHeader,
          );

      expect(cleared, isFalse);
      expect((await repository.getSessionSnapshot())?.accountId, 'new-reader');
      expect(await repository.buildCookieHeader(), 'session=new');
    });

    test('ログアウトは保存済みセッションを直列に削除する', () async {
      final events = <String>[];
      final cookiesDeleted = Completer<void>();
      final allowCookiesDelete = Completer<void>();
      final accountDeleted = Completer<void>();

      storage = _FakeSecureStorage(
        values: {
          'alphapolis_session_cookies': '{"session":"value"}',
          'alphapolis_account_id': 'reader@example.com',
        },
        onDelete: (key) async {
          if (key == 'alphapolis_session_cookies') {
            events.add('cookies');
            cookiesDeleted.complete();
            await allowCookiesDelete.future;
          } else if (key == 'alphapolis_account_id') {
            events.add('account');
            accountDeleted.complete();
          }
        },
      );
      repository = FormAuthSessionRepository(
        source: NovelSource.alphapolis,
        storage: storage,
      );

      final future = repository.clearAll();
      await cookiesDeleted.future;
      await Future<void>.delayed(Duration.zero);
      expect(events, ['cookies']);

      allowCookiesDelete.complete();
      await accountDeleted.future;
      await future;
      expect(events, ['cookies', 'account']);
    });

    test('壊れたCookieデータは空として扱う', () async {
      storage.values['alphapolis_session_cookies'] = 'not-json';

      expect(await repository.getCookies(), isEmpty);
      expect(await repository.hasCookies(), isFalse);
      expect(await repository.buildCookieHeader(), isNull);
    });
  });
}
