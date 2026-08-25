import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/sites/form_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// ハーメルンの認証状態を共通表現へ接続するAdapter。
class HamelnAccountSyncAdapter extends FormAccountSyncAdapter {
  /// コンストラクタ。
  HamelnAccountSyncAdapter({
    required super.sessionRepository,
    required HamelnAuthService authService,
  }) : super(
         source: NovelSource.hameln,
         validateSession: authService.isSessionValid,
         clearSession: authService.logout,
       );
}
