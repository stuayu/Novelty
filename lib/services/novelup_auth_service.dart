import 'package:dio/dio.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

final _configuration = FormPostAuthConfiguration(
  loginUri: Uri.parse('https://novelup.plus/login'),
  postUri: Uri.parse('https://novelup.plus/login'),
  accountField: 'mail',
  passwordField: 'password',
  hiddenFields: const ['_token', 'remember'],
);

/// ノベルアップ＋認証サービスのプロバイダー。
final novelupAuthServiceProvider = Provider<NovelupAuthService>((ref) {
  return NovelupAuthService(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.novelup),
    ),
    rateLimiter: ref.watch(siteRateLimiterProvider(NovelSource.novelup)),
  );
});

/// ノベルアップ＋のフォームPOSTログインとセッション管理。
class NovelupAuthService {
  /// コンストラクタ。
  NovelupAuthService({
    required FormAuthSessionRepository sessionRepository,
    Dio? dio,
    RequestRateLimiter? rateLimiter,
  }) : _delegate = FormPostAuthService(
         sessionRepository: sessionRepository,
         dio: dio ?? createNoveltyDio(rateLimiter: rateLimiter),
         configuration: _configuration,
       );

  final FormPostAuthService _delegate;

  /// メールアドレスとパスワードでログインする。
  Future<FormAuthLoginResult> login({
    required String mail,
    required String password,
  }) => _delegate.login(accountId: mail, password: password);

  /// 保存済みセッションが有効か確認する。
  Future<bool> isSessionValid() => _delegate.isSessionValid();

  /// 保存済み認証情報を削除する。
  Future<void> logout() => _delegate.logout();
}
