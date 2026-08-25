import 'package:dio/dio.dart';
import 'package:novelty/providers/site_rate_limiter_provider.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/request_rate_limiter.dart';
import 'package:riverpod/riverpod.dart';

final _configuration = FormPostAuthConfiguration(
  loginUri: Uri.parse('https://www.alphapolis.co.jp/login'),
  postUri: Uri.parse('https://www.alphapolis.co.jp/login'),
  accountField: 'email',
  passwordField: 'password',
  hiddenFields: const ['_token'],
);

/// アルファポリス認証サービスのプロバイダー。
final alphapolisAuthServiceProvider = Provider<AlphapolisAuthService>((ref) {
  return AlphapolisAuthService(
    sessionRepository: ref.watch(
      formAuthSessionRepositoryProvider(NovelSource.alphapolis),
    ),
    rateLimiter: ref.watch(
      siteRateLimiterProvider(NovelSource.alphapolis),
    ),
  );
});

/// アルファポリスのフォームPOSTログインとセッション管理。
class AlphapolisAuthService {
  /// コンストラクタ。
  AlphapolisAuthService({
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
    required String email,
    required String password,
  }) => _delegate.login(accountId: email, password: password);

  /// 保存済みセッションが有効か確認する。
  Future<bool> isSessionValid() => _delegate.isSessionValid();

  /// 保存済み認証情報を削除する。
  Future<void> logout() => _delegate.logout();
}
