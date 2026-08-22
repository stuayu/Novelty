import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/services/kakuyomu_graphql_service.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:riverpod/riverpod.dart';

const _followWorkMutation = r'''
mutation FollowWork($input: FollowWorkInput!) {
  followWork(input: $input) {
    __typename
  }
}
''';

const _unfollowWorksMutation = r'''
mutation UnfollowWorks($input: UnfollowWorksInput!) {
  unfollowWorks(input: $input) {
    __typename
  }
}
''';

/// セッション有効性確認をテスト時に差し替えるためのコールバック。
typedef KakuyomuSessionValidator = Future<bool> Function();

/// カクヨム作品のフォロー操作をネイティブHTTPで行うサービス。
final kakuyomuFollowServiceProvider = Provider<KakuyomuFollowService>((ref) {
  final authService = ref.watch(kakuyomuAuthServiceProvider);
  return KakuyomuFollowService(
    graphqlService: ref.watch(kakuyomuGraphqlServiceProvider),
    sessionValidator: authService.isSessionValid,
  );
});

/// カクヨムWeb版が使用しているGraphQL mutationで作品フォローを同期する。
///
/// 2026-08-22時点の現行Next.jsバンドルとApollo Serverの入力検証から、
/// 以下を確認済み。
/// - `FollowWork(input: FollowWorkInput!)` の必須フィールドは `workId: ID!`
/// - `UnfollowWorks(input: UnfollowWorksInput!)` の必須フィールドは
///   `workIds: [ID!]!`
/// - 未認証時のGraphQL error codeは `UNAUTHORIZED`
///
/// ブラウザ/WebViewは使用せず、保存済みCookieをDio経由でGraphQLへ送信する。
class KakuyomuFollowService {
  /// コンストラクタ。
  const KakuyomuFollowService({
    required KakuyomuGraphqlService graphqlService,
    required KakuyomuSessionValidator sessionValidator,
  }) : _graphqlService = graphqlService,
       _sessionValidator = sessionValidator;

  final KakuyomuGraphqlService _graphqlService;
  final KakuyomuSessionValidator _sessionValidator;

  /// 作品をカクヨムでフォローする。
  Future<AccountSyncOutcome> followWork(String workId) {
    return _executeMutation(
      workId: workId,
      operationName: 'FollowWork',
      query: _followWorkMutation,
      rootField: 'followWork',
      input: <String, Object?>{'workId': workId},
    );
  }

  /// 作品のカクヨムフォローを解除する。
  ///
  /// 現行Webクライアントには単数の `UnfollowWork` ではなく
  /// `UnfollowWorks` が存在するため、1件だけの配列として送信する。
  Future<AccountSyncOutcome> unfollowWork(String workId) {
    return _executeMutation(
      workId: workId,
      operationName: 'UnfollowWorks',
      query: _unfollowWorksMutation,
      rootField: 'unfollowWorks',
      input: <String, Object?>{
        'workIds': <String>[workId],
      },
    );
  }

  Future<AccountSyncOutcome> _executeMutation({
    required String workId,
    required String operationName,
    required String query,
    required String rootField,
    required Map<String, Object?> input,
  }) async {
    if (!_isValidWorkId(workId)) return AccountSyncOutcome.failed;

    // Cookieの存在だけでは期限切れを判定できないため、既存のネイティブHTTP
    // セッション検証を先に行う。期限切れは同期失敗ではなく未ログイン扱い。
    if (!await _sessionValidator()) return AccountSyncOutcome.notLoggedIn;

    final response = await _graphqlService.execute(
      operationName: operationName,
      query: query,
      variables: <String, Object?>{'input': input},
      authenticated: true,
    );
    if (response == null) return AccountSyncOutcome.notLoggedIn;

    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.hasErrorCode('UNAUTHORIZED')) {
      return AccountSyncOutcome.notLoggedIn;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AccountSyncOutcome.failed;
    }
    if (response.hasErrors) return AccountSyncOutcome.failed;

    final root = response.data?[rootField];
    return root == null
        ? AccountSyncOutcome.failed
        : AccountSyncOutcome.success;
  }

  bool _isValidWorkId(String workId) => RegExp(r'^\d+$').hasMatch(workId);
}
