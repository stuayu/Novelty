import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:novelty/repositories/auth_repository.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:novelty/services/narou_sync_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/narou/narou_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

import '../../repositories/library_status_toggle_test.mocks.dart';

class _FakeAuthRepository extends AuthRepository {
  bool cleared = false;
  String? cookieHeader = 'ks2=old-ks2; ses=old-ses; userl=old-userl';
  String narouId = 'test-id';
  String username = 'テストユーザー';
  int generation = 1;

  void replaceSession({
    required String cookieHeader,
    required String narouId,
    required String username,
  }) {
    this.cookieHeader = cookieHeader;
    this.narouId = narouId;
    this.username = username;
    generation++;
  }

  @override
  Future<String?> buildCookieHeader() async => cookieHeader;

  @override
  Future<AuthSessionSnapshot?> getSessionSnapshot() async {
    final currentCookieHeader = cookieHeader;
    if (currentCookieHeader == null) return null;
    return AuthSessionSnapshot(
      narouid: narouId,
      username: username,
      cookieHeader: currentCookieHeader,
      generation: generation,
    );
  }

  @override
  Future<bool> hasSessionCookies() async => cookieHeader != null;

  @override
  Future<bool> clearAllIfSessionCookieHeaderMatches(String expected) async {
    if (cookieHeader != expected) return false;
    cleared = true;
    cookieHeader = null;
    generation++;
    return true;
  }

  @override
  Future<bool> clearAllIfSessionCookieHeaderAndGenerationMatches(
    int expectedGeneration,
    String expectedCookieHeader,
  ) async {
    if (generation != expectedGeneration ||
        cookieHeader != expectedCookieHeader) {
      return false;
    }
    cleared = true;
    cookieHeader = null;
    generation++;
    return true;
  }

  @override
  Future<String?> getNarouid() async => cookieHeader == null ? null : narouId;

  @override
  Future<String?> getUsername() async => cookieHeader == null ? null : username;

  @override
  Future<void> clearAll() async => cleared = true;
}

class _FakeNarouAuthService extends NarouAuthService {
  _FakeNarouAuthService(AuthRepository authRepository)
    : super(authRepository: authRepository);

  NarouSessionValidity sessionValidity = NarouSessionValidity.valid;
  bool loggedOut = false;
  void Function(int validationNumber)? onValidate;
  Completer<void>? validationStarted;
  Completer<void>? allowValidation;
  final validatedCookieHeaders = <String>[];
  final validityByCookieHeader = <String, NarouSessionValidity>{};

  @override
  Future<NarouSessionValidity> validateSession(String cookieHeader) async {
    validatedCookieHeaders.add(cookieHeader);
    final started = validationStarted;
    if (started != null && !started.isCompleted) started.complete();
    await allowValidation?.future;
    final validity = validityByCookieHeader[cookieHeader] ?? sessionValidity;
    onValidate?.call(validatedCookieHeaders.length);
    return validity;
  }

  @override
  Future<void> logout() async => loggedOut = true;
}

void main() {
  group('NarouAccountSyncAdapter', () {
    late MockNarouSyncService syncService;
    late MockAppDatabase db;
    late NarouAccountSyncAdapter adapter;

    const workId = 'n1234ab';

    setUp(() {
      syncService = MockNarouSyncService();
      db = MockAppDatabase();
      adapter = NarouAccountSyncAdapter(syncService: syncService, db: db);
    });

    test('sourceはnarouを返す', () {
      expect(adapter.source, NovelSource.narou);
    });

    test('ログイン中のアカウント識別子と表示名を共通状態で返す', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository);
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(state.source, NovelSource.narou);
      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, 'test-id');
      expect(state.displayName, 'テストユーザー');
      expect(await authAdapter.isLoggedIn(), isTrue);
    });

    test('セッションCookieが無い場合は未ログインを返す', () async {
      final repository = _FakeAuthRepository()..cookieHeader = null;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );

      final state = await authAdapter.getAuthState();

      expect(state.isLoggedIn, isFalse);
      expect(await authAdapter.isLoggedIn(), isFalse);
    });

    test('検証中に別アカウントへ切り替わった応答で新しいセッションを消さない', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.invalid
        ..validityByCookieHeader['ks2=old-ks2; ses=old-ses; userl=old-userl'] =
            NarouSessionValidity.invalid
        ..validityByCookieHeader['ks2=new-ks2; ses=new-ses; userl=new-userl'] =
            NarouSessionValidity.valid
        ..validationStarted = Completer<void>()
        ..allowValidation = Completer<void>();
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final stateFuture = authAdapter.getAuthState();
      await authService.validationStarted!.future;
      repository.replaceSession(
        cookieHeader: 'ks2=new-ks2; ses=new-ses; userl=new-userl',
        narouId: 'new-reader',
        username: '新利用者',
      );
      authService.allowValidation!.complete();

      final state = await stateFuture;

      expect(authService.validatedCookieHeaders, [
        'ks2=old-ks2; ses=old-ses; userl=old-userl',
        'ks2=new-ks2; ses=new-ses; userl=new-userl',
      ]);
      expect(repository.cleared, isFalse);
      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, 'new-reader');
      expect(state.displayName, '新利用者');
    });

    test('通信障害でセッションを消去せず保存済みアカウントを返す', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.unavailable;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(repository.cleared, isFalse);
      expect(state.isLoggedIn, isFalse);
      expect(state.hasSession, isTrue);
      expect(state.isVerified, isFalse);
      expect(state.accountId, 'test-id');
    });

    test('再試行上限に達したら保存済みセッションを未確認として返す', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.unavailable
        ..onValidate = (validationNumber) {
          repository.replaceSession(
            cookieHeader:
                'ks2=ks$validationNumber; ses=s$validationNumber; '
                'userl=u$validationNumber',
            narouId: 'test-id',
            username: 'テストユーザー',
          );
        };
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(authService.validatedCookieHeaders, hasLength(5));
      expect(state.isLoggedIn, isFalse);
      expect(state.hasSession, isTrue);
      expect(state.isVerified, isFalse);
      expect(state.accountId, 'test-id');
      expect(repository.cleared, isFalse);
    });

    test('明示的に失効した現行セッションは消去して未ログインを返す', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.invalid;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(repository.cleared, isTrue);
      expect(state.isLoggedIn, isFalse);
    });

    test('再試行上限後に確認した最新セッションが失効していれば消去する', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.invalid
        ..onValidate = (validationNumber) {
          if (validationNumber > 3) return;
          repository.replaceSession(
            cookieHeader:
                'ks2=ks$validationNumber; ses=s$validationNumber; '
                'userl=u$validationNumber',
            narouId: 'test-id',
            username: 'テストユーザー',
          );
        };
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(authService.validatedCookieHeaders, hasLength(4));
      expect(state.isLoggedIn, isFalse);
      expect(repository.cleared, isTrue);
      expect(repository.cookieHeader, isNull);
    });

    test('最終検証中にCookieが更新されたら同一アカウントをログアウト扱いしない', () async {
      final repository = _FakeAuthRepository();
      const rotatedCookieHeader =
          'ks2=rotated-ks2; ses=rotated-ses; userl=rotated-userl';
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.invalid
        ..validityByCookieHeader[rotatedCookieHeader] =
            NarouSessionValidity.valid
        ..onValidate = (validationNumber) {
          if (validationNumber <= 3) {
            repository.replaceSession(
              cookieHeader:
                  'ks2=ks$validationNumber; ses=s$validationNumber; '
                  'userl=u$validationNumber',
              narouId: 'test-id',
              username: 'テストユーザー',
            );
          } else {
            repository.cookieHeader = rotatedCookieHeader;
          }
        };
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(authService.validatedCookieHeaders, hasLength(5));
      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, 'test-id');
      expect(repository.cleared, isFalse);
      expect(repository.cookieHeader, rotatedCookieHeader);
    });

    test('最終検証中に別アカウントへ変わったら新しいセッションを確認する', () async {
      final repository = _FakeAuthRepository();
      const newCookieHeader = 'ks2=new-ks2; ses=new-ses; userl=new-userl';
      final authService = _FakeNarouAuthService(repository)
        ..sessionValidity = NarouSessionValidity.invalid
        ..validityByCookieHeader[newCookieHeader] = NarouSessionValidity.valid
        ..onValidate = (validationNumber) {
          if (validationNumber <= 3) {
            repository.replaceSession(
              cookieHeader:
                  'ks2=ks$validationNumber; ses=s$validationNumber; '
                  'userl=u$validationNumber',
              narouId: 'test-id',
              username: 'テストユーザー',
            );
          } else if (validationNumber == 4) {
            repository.replaceSession(
              cookieHeader: newCookieHeader,
              narouId: 'new-reader',
              username: '新利用者',
            );
          }
        };
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      final state = await authAdapter.getAuthState();

      expect(authService.validatedCookieHeaders, hasLength(5));
      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, 'new-reader');
      expect(state.displayName, '新利用者');
      expect(repository.cleared, isFalse);
      expect(repository.cookieHeader, newCookieHeader);
    });

    test('logoutはなろう認証サービスへ委譲する', () async {
      final repository = _FakeAuthRepository();
      final authService = _FakeNarouAuthService(repository);
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: authService,
      );

      await authAdapter.logout();

      expect(authService.loggedOut, isTrue);
    });

    test('pullLibraryは同期した作品数を返す', () async {
      when(syncService.syncBookmarksFromNarou()).thenAnswer(
        (_) async => const ['n0001aa', 'n0002bb'],
      );

      expect(await adapter.pullLibrary(), 2);
    });

    test('同期中に再ログインした場合は古いCookieの失効応答で新しいセッションを消さない', () async {
      final repository = _FakeAuthRepository();
      const oldCookieHeader = 'ks2=old-ks2; ses=old-ses; userl=old-userl';
      const newCookieHeader = 'ks2=new-ks2; ses=new-ses; userl=new-userl';
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );
      when(syncService.syncBookmarksFromNarou()).thenAnswer((_) async {
        repository.replaceSession(
          cookieHeader: newCookieHeader,
          narouId: 'new-reader',
          username: '新しい利用者',
        );
        throw const NarouSessionExpiredException(
          cookieHeader: oldCookieHeader,
        );
      });

      await expectLater(
        authAdapter.pullLibrary(),
        throwsA(isA<NarouBookmarkFetchException>()),
      );

      expect(repository.cleared, isFalse);
      expect(repository.cookieHeader, newCookieHeader);
    });

    test('現在のCookieが失効した同期応答なら一致確認後にだけCookieを消す', () async {
      final repository = _FakeAuthRepository();
      const cookieHeader = 'ks2=old-ks2; ses=old-ses; userl=old-userl';
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );
      when(syncService.syncBookmarksFromNarou()).thenAnswer((_) async {
        throw const NarouSessionExpiredException(cookieHeader: cookieHeader);
      });

      await expectLater(
        authAdapter.pullLibrary(),
        throwsA(isA<AccountSessionExpiredException>()),
      );

      expect(repository.cleared, isTrue);
      expect(repository.cookieHeader, isNull);
    });

    test('同じログイン中に古いCookieが失効したら最新Cookieで同期を再試行する', () async {
      final repository = _FakeAuthRepository();
      const rotatedCookieHeader =
          'ks2=old-ks2; ses=rotated-ses; userl=old-userl';
      final generation = repository.generation;
      var attempts = 0;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );
      when(syncService.syncBookmarksFromNarou()).thenAnswer((_) async {
        attempts++;
        if (attempts > 1) return const ['n0001aa'];
        repository.cookieHeader = rotatedCookieHeader;
        throw NarouSessionExpiredException(
          cookieHeader: 'ks2=old-ks2; ses=old-ses; userl=old-userl',
          generation: generation,
        );
      });

      expect(await authAdapter.pullLibrary(), 1);

      expect(attempts, 2);
      expect(repository.cleared, isFalse);
      expect(repository.cookieHeader, rotatedCookieHeader);
    });

    test('最新Cookieでも失効したら一致するセッションだけを消す', () async {
      final repository = _FakeAuthRepository();
      const oldCookieHeader = 'ks2=old-ks2; ses=old-ses; userl=old-userl';
      const rotatedCookieHeader =
          'ks2=old-ks2; ses=rotated-ses; userl=old-userl';
      final generation = repository.generation;
      var attempts = 0;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );
      when(syncService.syncBookmarksFromNarou()).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) {
          repository.cookieHeader = rotatedCookieHeader;
          throw NarouSessionExpiredException(
            cookieHeader: oldCookieHeader,
            generation: generation,
          );
        }
        throw NarouSessionExpiredException(
          cookieHeader: rotatedCookieHeader,
          generation: generation,
        );
      });

      await expectLater(
        authAdapter.pullLibrary(),
        throwsA(isA<AccountSessionExpiredException>()),
      );

      expect(attempts, 2);
      expect(repository.cleared, isTrue);
      expect(repository.cookieHeader, isNull);
    });

    test('失効応答のCookie処理ですでに消去済みなら未ログイン状態を返す', () async {
      final repository = _FakeAuthRepository();
      final generation = repository.generation;
      final authAdapter = NarouAccountSyncAdapter(
        syncService: syncService,
        db: db,
        authRepository: repository,
        authService: _FakeNarouAuthService(repository),
      );
      when(syncService.syncBookmarksFromNarou()).thenAnswer((_) async {
        repository.cookieHeader = null;
        throw NarouSessionExpiredException(generation: generation);
      });

      await expectLater(
        authAdapter.pullLibrary(),
        throwsA(
          isA<AccountSessionExpiredException>().having(
            (error) => error.clearSessionOnCatch,
            'clearSessionOnCatch',
            isFalse,
          ),
        ),
      );
      expect(repository.cleared, isFalse);
    });

    test('ブックマーク同期成功を共通successへ変換し同期情報を保存する', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.success,
          useridFavncode: '123_456',
          token: 'token-value',
        ),
      );
      when(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      ).thenAnswer((_) async {});

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.success);
      verify(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: '123_456',
          favToken: 'token-value',
        ),
      ).called(1);
    });

    test('未ログインを共通notLoggedInへ変換し同期情報を保存しない', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.notLoggedIn,
        ),
      );

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.notLoggedIn);
      verifyNever(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('同期失敗を共通failedへ変換し同期情報を保存しない', () async {
      when(syncService.addBookmarkToNarou(workId)).thenAnswer(
        (_) async => const NarouBookmarkSyncResult(
          outcome: NarouBookmarkSyncOutcome.failed,
        ),
      );

      final result = await adapter.addToRemoteLibrary(workId);

      expect(result, AccountSyncOutcome.failed);
      verifyNever(
        db.markNarouBookmarkSynced(
          NovelSource.narou,
          workId,
          useridFavncode: anyNamed('useridFavncode'),
          favToken: anyNamed('favToken'),
        ),
      );
    });

    test('解除結果を共通結果へ変換する', () async {
      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.success,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.success,
      );

      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.notLoggedIn,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.notLoggedIn,
      );

      when(syncService.removeBookmarkFromNarou(workId)).thenAnswer(
        (_) async => NarouBookmarkSyncOutcome.failed,
      );
      expect(
        await adapter.removeFromRemoteLibrary(workId),
        AccountSyncOutcome.failed,
      );
    });

    test('pushReadingProgressは既存しおり同期へ委譲する', () async {
      when(
        syncService.setShioriIfLoggedIn(ncode: workId, episode: 12),
      ).thenAnswer((_) async => true);

      final result = await adapter.pushReadingProgress(
        workId: workId,
        episode: 12,
      );

      expect(result, isTrue);
      verify(
        syncService.setShioriIfLoggedIn(ncode: workId, episode: 12),
      ).called(1);
    });
  });
}
