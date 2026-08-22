import 'package:novelty/services/kakuyomu_graphql_service.dart';
import 'package:riverpod/riverpod.dart';

const _recordReadingHistoryMutation = r'''
mutation RecordReadingHistory($input: RecordReadingHistoryInput!) {
  recordReadingHistory(input: $input) {
    clientMutationId
    __typename
  }
}
''';

final _numericIdPattern = RegExp(r'^\d+$');

/// カクヨム読書履歴同期サービスのProvider。
final kakuyomuReadingProgressServiceProvider =
    Provider<KakuyomuReadingProgressService>((ref) {
      return KakuyomuReadingProgressService(
        graphqlService: ref.watch(kakuyomuGraphqlServiceProvider),
      );
    });

/// カクヨムの「続きから読む」位置をネイティブGraphQLで記録するサービス。
///
/// `RecordReadingHistoryInput` の必須フィールドは現行Web bundleと
/// 未認証GraphQL validationで確認済みの `episodeId` / `position` のみ扱う。
/// [position] の意味や形式は呼び出し側で確認済みの値を渡し、この層では
/// 正規化・推測を行わない。
class KakuyomuReadingProgressService {
  /// コンストラクタ。
  const KakuyomuReadingProgressService({
    required KakuyomuGraphqlService graphqlService,
  }) : _graphqlService = graphqlService;

  final KakuyomuGraphqlService _graphqlService;

  /// 指定したremote episodeの読書位置を記録する。
  ///
  /// 保存済みCookieが無い場合、認証切れ、GraphQL error、通信失敗はすべて
  /// `false` を返す。外部同期失敗を読書UIへ伝播させないため例外は投げない。
  Future<bool> record({
    required String episodeId,
    required String position,
  }) async {
    if (!_numericIdPattern.hasMatch(episodeId) || position.isEmpty) {
      return false;
    }

    try {
      final response = await _graphqlService.execute(
        operationName: 'RecordReadingHistory',
        query: _recordReadingHistoryMutation,
        variables: <String, Object?>{
          'input': <String, Object?>{
            'episodeId': episodeId,
            'position': position,
          },
        },
        authenticated: true,
      );
      if (response == null) return false;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      if (response.hasErrors || response.hasErrorCode('UNAUTHORIZED')) {
        return false;
      }

      return response.data?['recordReadingHistory'] is Map<Object?, Object?>;
    } on Exception {
      return false;
    }
  }
}
