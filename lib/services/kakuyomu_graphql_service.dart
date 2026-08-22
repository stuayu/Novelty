import 'package:dio/dio.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:riverpod/riverpod.dart';

const _kakuyomuGraphqlEndpoint = 'https://kakuyomu.jp/graphql';

/// カクヨムGraphQLへのHTTPリクエスト。
class KakuyomuGraphqlRequest {
  /// コンストラクタ。
  const KakuyomuGraphqlRequest({
    required this.operationName,
    required this.query,
    required this.variables,
    this.cookieHeader,
  });

  /// GraphQL operation名。
  final String operationName;

  /// GraphQL query / mutation本文。
  final String query;

  /// GraphQL variables。
  final Map<String, Object?> variables;

  /// 保存済みログインセッションを利用する場合のCookieヘッダー。
  final String? cookieHeader;
}

/// カクヨムGraphQLからのHTTPレスポンス。
class KakuyomuGraphqlResponse {
  /// コンストラクタ。
  const KakuyomuGraphqlResponse({
    required this.statusCode,
    required this.body,
  });

  /// HTTPステータスコード。
  final int statusCode;

  /// JSONレスポンス。
  final Map<String, Object?> body;

  /// GraphQL errorsが含まれているか。
  bool get hasErrors => errors.isNotEmpty;

  /// GraphQL errorsを文字列キーのMapとして取得する。
  List<Map<String, Object?>> get errors {
    final value = body['errors'];
    if (value is! List<Object?>) return const [];

    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (error) => error.map(
            (key, entry) => MapEntry(key.toString(), entry),
          ),
        )
        .toList(growable: false);
  }

  /// GraphQL errorの`extensions.code`に[code]が含まれるか確認する。
  bool hasErrorCode(String code) {
    return errors.any((error) {
      final extensions = error['extensions'];
      if (extensions is! Map<Object?, Object?>) return false;
      return extensions['code'] == code;
    });
  }

  /// dataオブジェクト。
  Map<String, Object?>? get data {
    final value = body['data'];
    if (value is! Map<Object?, Object?>) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

/// テスト時にGraphQL HTTP通信を差し替えるためのコールバック。
typedef KakuyomuGraphqlTransport =
    Future<KakuyomuGraphqlResponse> Function(KakuyomuGraphqlRequest request);

/// カクヨムGraphQLネイティブ通信サービスのProvider。
final kakuyomuGraphqlServiceProvider = Provider<KakuyomuGraphqlService>((ref) {
  return KakuyomuGraphqlService(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
  );
});

/// カクヨムのGraphQL APIをDioで呼び出す低レベルサービス。
///
/// ブラウザやWebViewを利用せず、確認済みのGraphQL通信形式だけを扱う。
/// 個別operationのquery/mutation本文は、実通信または公式クライアント解析で
/// 内容を確認できたものだけ上位サービスから渡す。
class KakuyomuGraphqlService {
  /// コンストラクタ。
  KakuyomuGraphqlService({
    required KakuyomuSessionRepository sessionRepository,
    Dio? dio,
    KakuyomuGraphqlTransport? transport,
  }) : _sessionRepository = sessionRepository,
       _dio = dio ?? Dio(),
       _transport = transport;

  final KakuyomuSessionRepository _sessionRepository;
  final Dio _dio;
  final KakuyomuGraphqlTransport? _transport;

  /// GraphQL operationを実行する。
  ///
  /// [authenticated] がtrueの場合はSecure Storageに保存済みのカクヨムCookieを
  /// 付与する。Cookieが無い場合はHTTPリクエストを行わずnullを返す。
  Future<KakuyomuGraphqlResponse?> execute({
    required String operationName,
    required String query,
    Map<String, Object?> variables = const <String, Object?>{},
    bool authenticated = false,
  }) async {
    final cookieHeader = authenticated
        ? await _sessionRepository.buildCookieHeader()
        : null;
    if (authenticated && (cookieHeader == null || cookieHeader.isEmpty)) {
      return null;
    }

    final request = KakuyomuGraphqlRequest(
      operationName: operationName,
      query: query,
      variables: variables,
      cookieHeader: cookieHeader,
    );

    final override = _transport;
    if (override != null) return override(request);

    final response = await _dio.post<Object?>(
      _kakuyomuGraphqlEndpoint,
      queryParameters: <String, Object?>{'opname': operationName},
      data: <String, Object?>{
        'operationName': operationName,
        'variables': variables,
        'query': query,
      },
      options: Options(
        headers: <String, Object>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': 'https://kakuyomu.jp',
          'Referer': 'https://kakuyomu.jp/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36',
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.json,
      ),
    );

    final body = _normalizeJsonMap(response.data);
    return KakuyomuGraphqlResponse(
      statusCode: response.statusCode ?? 0,
      body: body,
    );
  }

  Map<String, Object?> _normalizeJsonMap(Object? value) {
    if (value is! Map<Object?, Object?>) return const <String, Object?>{};
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
}
