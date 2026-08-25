import 'package:novelty/services/novelup_auth_service.dart';
import 'package:novelty/sites/form_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// ノベルアップ＋の認証状態を共通表現へ接続するAdapter。
class NovelupAccountSyncAdapter extends FormAccountSyncAdapter {
  /// コンストラクタ。
  NovelupAccountSyncAdapter({
    required super.sessionRepository,
    required NovelupAuthService authService,
  }) : super(
         source: NovelSource.novelup,
         validateSession: authService.isSessionValid,
         clearSession: authService.logout,
       );
}
