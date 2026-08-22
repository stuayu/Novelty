import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:riverpod/riverpod.dart';

const _kakuyomuBaseUrl = 'https://kakuyomu.jp';
const _kakuyomuSessionCheckUrl = '$_kakuyomuBaseUrl/my';

/// `/my` の HTML がログイン済み状態を示しているか判定する。
///
/// 未ログイン時はログイン導線 (`/auth/login` または `/login`) が表示されるため、
/// それらが存在しない場合だけログイン済みとみなす。
bool kakuyomuDashboardIndicatesLoggedIn(String html) {
  if (html.isEmpty) return false;

  final document = html_parser.parse(html);
  final hasLoginLink = document.querySelectorAll('a').any((anchor) {
    final href = anchor.attributes['href'];
    if (href == null) return false;
    return href == '/auth/login' || href == '/login';
  });

  return !hasLoginLink;
}

/// カクヨム認証サービスのプロバイダー。
final kakuyomuAuthServiceProvider = Provider<KakuyomuAuthService>((ref) {
  return KakuyomuAuthService(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
  );
});

/// 保存済みカクヨムセッションの有効性確認と破棄を担当するサービス。
class KakuyomuAuthService {
  /// コンストラクタ。
  KakuyomuAuthService({
    required KakuyomuSessionRepository sessionRepository,
    Dio? dio,
  }) : _sessionRepository = sessionRepository,
       _dio = dio ?? Dio();

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;

  /// 保存済み Cookie がログイン済みセッションとして有効か確認する。
  ///
  /// カクヨムの `/my` は未ログインでも表示できるため、HTTP ステータスだけでなく
  /// ログイン導線が残っていないことも確認する。
  Future<bool> isSessionValid() async {
    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) return false;

    try {
      final response = await _dio.get<String>(
        _kakuyomuSessionCheckUrl,
        options: Options(
          headers: <String, Object>{
            'Cookie': cookieHeader,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/143.0.0.0 Safari/537.36',
          },
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == null || response.statusCode! >= 400) {
        return false;
      }

      final finalUri = response.realUri;
      if (finalUri.path.startsWith('/auth/login') ||
          finalUri.path.startsWith('/login')) {
        return false;
      }

      final body = response.data;
      if (body == null) return false;
      return kakuyomuDashboardIndicatesLoggedIn(body);
    } on DioException {
      return false;
    }
  }

  /// Novelty に保存されたカクヨム認証情報を破棄する。
  Future<void> logout() => _sessionRepository.clearAll();
}

/// カクヨムの保存済みセッション状態を監視するプロバイダー。
final kakuyomuSessionValidProvider = FutureProvider<bool>((ref) async {
  return ref.watch(kakuyomuAuthServiceProvider).isSessionValid();
});
