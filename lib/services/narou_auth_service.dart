import 'package:dio/dio.dart';
import 'package:html/parser.dart' as parser;
import 'package:novelty/repositories/auth_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'narou_auth_service.g.dart';

const _loginUrl = 'https://syosetu.com/login/login/';
const _bookmarkListUrl = 'https://syosetu.com/favnovelmain/list/';

/// なろうへのHTTPリクエストで使用するUser-Agent。
const narouUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

@Riverpod(keepAlive: true)
/// なろう認証サービスのプロバイダー。
NarouAuthService narouAuthService(Ref ref) {
  return NarouAuthService(authRepository: ref.watch(authRepositoryProvider));
}

/// なろうへのログイン・セッション管理を行うサービス。
///
/// セキュリティ設計：
/// - 認証Cookie (`ks2`, `ses`, `userl`) は`AuthRepository`経由でKeyChain/Keystoreに保存する。
/// - 認証Cookieはなろう (`syosetu.com`) へのリクエストにのみ付与する。
/// - 小説API (`api.syosetu.com`)、小説本文取得、検索では認証Cookieを使用しない。
class NarouAuthService {
  /// コンストラクタ。
  NarouAuthService({required this.authRepository});

  /// 認証情報リポジトリ。
  final AuthRepository authRepository;

  /// ログインPOSTリクエストを送信し、セッションCookieを取得・保存する。
  ///
  /// 成功した場合は`NarouLoginResult.success`を返す。
  /// 失敗した場合はエラーメッセージを含む`NarouLoginResult.failure`を返す。
  Future<NarouLoginResult> login({
    required String narouid,
    required String password,
  }) async {
    final dio = Dio();
    try {
      final response = await dio.post<String>(
        _loginUrl,
        data: 'narouid=${Uri.encodeQueryComponent(narouid)}'
            '&pass=${Uri.encodeQueryComponent(password)}',
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://syosetu.com/login/input/',
          },
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          responseType: ResponseType.plain,
        ),
      );

      final setCookieHeaders = response.headers.map['set-cookie'];
      if (setCookieHeaders == null || setCookieHeaders.isEmpty) {
        return const NarouLoginResult.failure(
          'ログインに失敗しました。IDまたはパスワードが正しくありません。',
        );
      }

      final cookies = _parseCookies(setCookieHeaders);
      final ses = cookies['ses'];
      final ks2 = cookies['ks2'];
      final userl = cookies['userl'];

      if (ses == null || ks2 == null || userl == null) {
        return const NarouLoginResult.failure(
          'ログインに失敗しました。IDまたはパスワードが正しくありません。',
        );
      }

      // ブックマーク一覧ページからユーザー名を取得する
      final username =
          await _fetchUsername(ks2: ks2, ses: ses, userl: userl) ?? narouid;

      // 認証情報を安全に保存する
      await Future.wait([
        authRepository.saveNarouid(narouid),
        authRepository.saveUsername(username),
        authRepository.saveSessionCookies(ks2: ks2, ses: ses, userl: userl),
      ]);

      return NarouLoginResult.success(username: username);
    } on DioException catch (e) {
      return NarouLoginResult.failure(
        e.message ?? 'ネットワークエラーが発生しました',
      );
    }
  }

  /// 保存済みのセッションが有効か確認する。
  ///
  /// ブックマーク一覧ページへアクセスし、200が返れば有効と判断する。
  /// 302リダイレクト（ログインページへ転送）が返れば無効と判断する。
  Future<bool> isSessionValid() async {
    final cookieHeader = await authRepository.buildCookieHeader();
    if (cookieHeader == null) return false;

    try {
      final dio = Dio();
      final response = await dio.get<String>(
        _bookmarkListUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': cookieHeader,
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  /// ログアウトして保存済み認証情報をすべて削除する。
  Future<void> logout() => authRepository.clearAll();

  /// ブックマーク一覧ページからユーザー名を取得する（ログイン後に呼ぶ）。
  Future<String?> _fetchUsername({
    required String ks2,
    required String ses,
    required String userl,
  }) async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        _bookmarkListUrl,
        options: Options(
          headers: {
            'User-Agent': narouUserAgent,
            'Cookie': 'ks2=$ks2; ses=$ses; userl=$userl',
          },
          responseType: ResponseType.plain,
        ),
      );
      if (response.data == null) return null;
      final responseData = response.data!;
      final doc = parser.parse(responseData);
      // ユーザー名は `.p-up-header-pc__username` から取得
      final nameEl = doc.querySelector('.p-up-header-pc__username');
      return nameEl?.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    } on Exception {
      return null;
    }
  }

  /// Set-Cookieヘッダーリストを解析してCookie名→値のMapに変換する。
  Map<String, String> _parseCookies(List<String> setCookieHeaders) {
    final result = <String, String>{};
    for (final header in setCookieHeaders) {
      // 各Set-Cookieヘッダーの先頭部分 "name=value" を取り出す
      final parts = header.split(';');
      if (parts.isEmpty) continue;
      final firstPart = parts.first.trim();
      final eqIndex = firstPart.indexOf('=');
      if (eqIndex <= 0) continue;
      final name = firstPart.substring(0, eqIndex).trim();
      final value = firstPart.substring(eqIndex + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        result[name] = value;
      }
    }
    return result;
  }
}

/// ログイン処理の結果を表すクラス。
class NarouLoginResult {
  /// ログイン成功。
  const NarouLoginResult.success({required this.username})
      : isSuccess = true,
        error = null;

  /// ログイン失敗。
  const NarouLoginResult.failure(String this.error)
      : isSuccess = false,
        username = null;

  /// 成功したか否か。
  final bool isSuccess;

  /// ログイン成功時のユーザー名。
  final String? username;

  /// ログイン失敗時のエラーメッセージ。
  final String? error;
}
