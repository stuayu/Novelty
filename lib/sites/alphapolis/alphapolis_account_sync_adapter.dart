import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/sites/form_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

/// アルファポリスの認証状態を共通表現へ接続するAdapter。
class AlphapolisAccountSyncAdapter extends FormAccountSyncAdapter {
  /// コンストラクタ。
  AlphapolisAccountSyncAdapter({
    required super.sessionRepository,
    required AlphapolisAuthService authService,
  }) : super(
         source: NovelSource.alphapolis,
         validateSession: authService.isSessionValid,
         clearSession: authService.logout,
       );
}
