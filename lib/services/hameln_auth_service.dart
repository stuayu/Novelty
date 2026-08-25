import 'package:dio/dio.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

final _configuration = FormPostAuthConfiguration(
  loginUri: Uri.parse('https://syosetu.org/?mode=login'),
  postUri: Uri.parse('https://syosetu.org/?mode=login').resolve('./'),
  accountField: 'id',
  passwordField: 'pass',
  hiddenFields: const ['redirect_mode'],
  staticFields: const {'mode': 'login_entry_end'},
);

/// ハーメルン認証サービスのプロバイダー。
final hamelnAuthServiceProvider = Provider<HamelnAuthService>((ref) {
  return HamelnAuthService(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.hameln),
    ),
    rateLimiter: ref.watch(siteRateLimiterProvider(NovelSource.hameln)),
  );
});

/// ハーメルンのフォームPOSTログインとセッション管理。
class HamelnAuthService {
  /// コンストラクタ。
  HamelnAuthService({
    required FormAuthSessionRepository sessionRepository,
    Dio? dio,
    RequestRateLimiter? rateLimiter,
  }) : _delegate = FormPostAuthService(
         sessionRepository: sessionRepository,
         dio: dio ?? createNoveltyDio(rateLimiter: rateLimiter),
         configuration: _configuration,
       );

  final FormPostAuthService _delegate;

  /// ユーザーIDとパスワードでログインする。
  Future<FormAuthLoginResult> login({
    required String id,
    required String password,
  }) => _delegate.login(accountId: id, password: password);

  /// 保存済みセッションが有効か確認する。
  Future<bool> isSessionValid() => _delegate.isSessionValid();

  /// 保存済み認証情報を削除する。
  Future<void> logout() => _delegate.logout();
}
