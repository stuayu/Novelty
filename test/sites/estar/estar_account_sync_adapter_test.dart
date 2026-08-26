import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/estar_session_repository.dart';
import 'package:novelty/services/estar_auth_service.dart';
import 'package:novelty/sites/estar/estar_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

class _FakeEstarAuthService extends EstarAuthService {
  _FakeEstarAuthService() : super(sessionRepository: EstarSessionRepository());

  bool sessionValid = true;
  bool loggedOut = false;

  @override
  Future<bool> isSessionValid() async => sessionValid;

  @override
  Future<void> logout() async => loggedOut = true;
}

void main() {
  group('EstarAccountSyncAdapter', () {
    test('保存済みセッションから共通認証状態を返しlogoutを委譲する', () async {
      final authService = _FakeEstarAuthService();
      final adapter = EstarAccountSyncAdapter(authService: authService);

      final state = await adapter.getAuthState();

      expect(adapter.source, NovelSource.estar);
      expect(state.source, NovelSource.estar);
      expect(state.isLoggedIn, isTrue);
      expect(state.accountId, isNull);
      expect(state.displayName, isNull);
      expect(await adapter.isLoggedIn(), isTrue);

      await adapter.logout();
      expect(authService.loggedOut, isTrue);
    });

    test('無効なセッションは未ログインとして返す', () async {
      final authService = _FakeEstarAuthService()..sessionValid = false;
      final adapter = EstarAccountSyncAdapter(authService: authService);

      expect((await adapter.getAuthState()).isLoggedIn, isFalse);
      expect(await adapter.isLoggedIn(), isFalse);
    });

    test('未確認の同期4操作はUnsupportedErrorを投げる', () {
      final adapter = EstarAccountSyncAdapter(
        authService: _FakeEstarAuthService(),
      );

      expect(adapter.pullLibrary, throwsUnsupportedError);
      expect(
        () => adapter.addToRemoteLibrary('26544596'),
        throwsUnsupportedError,
      );
      expect(
        () => adapter.removeFromRemoteLibrary('26544596'),
        throwsUnsupportedError,
      );
      expect(
        () => adapter.pushReadingProgress(
          workId: '26544596',
          episode: 1,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
