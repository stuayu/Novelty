import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/database/database.dart';
import 'package:novelty/models/novel_info.dart';
import 'package:novelty/repositories/kakuyomu_session_repository.dart';
import 'package:novelty/sites/account_sync_adapter.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_followed_works_parser.dart';
import 'package:novelty/sites/novel_source.dart';

const _initialFollowedWorksUrl =
    'https://kakuyomu.jp/my/antenna/works/all?order=last_read_at';

/// Phase 3 のカクヨム読み取り同期に使用する専用Provider。
///
/// リモート書き込みが完成するPhase 4までは共通AccountSyncRegistryへ登録しない。
final kakuyomuAccountSyncAdapterProvider = Provider<KakuyomuAccountSyncAdapter>(
  (ref) => KakuyomuAccountSyncAdapter(
    sessionRepository: ref.watch(kakuyomuSessionRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
  ),
);

/// カクヨムのアカウント同期アダプター。
///
/// Phase 3 ではカクヨム → Novelty のフォロー作品取り込みだけを提供する。
/// リモートへの追加・削除、読書位置送信は後続Phaseで実装する。
class KakuyomuAccountSyncAdapter implements AccountSyncAdapter {
  /// コンストラクタ。
  KakuyomuAccountSyncAdapter({
    required KakuyomuSessionRepository sessionRepository,
    required AppDatabase db,
    Dio? dio,
    KakuyomuFollowedWorksParser? parser,
  }) : _sessionRepository = sessionRepository,
       _db = db,
       _dio = dio ?? Dio(),
       _parser = parser ?? KakuyomuFollowedWorksParser();

  final KakuyomuSessionRepository _sessionRepository;
  final AppDatabase _db;
  final Dio _dio;
  final KakuyomuFollowedWorksParser _parser;

  @override
  NovelSource get source => NovelSource.kakuyomu;

  @override
  Future<int> pullLibrary() async {
    final cookieHeader = await _sessionRepository.buildCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) return 0;

    final seenPageUrls = <Uri>{};
    final seenWorkIds = <String>{};
    var currentUrl = Uri.parse(_initialFollowedWorksUrl);
    var importedCount = 0;

    // フォロー上限が大きいためページ数を無制限にはしない。
    // 通常のページサイズを大幅に超える500ページを安全弁とする。
    for (var page = 0; page < 500; page++) {
      if (!seenPageUrls.add(currentUrl)) break;

      final response = await _dio.get<String>(
        currentUrl.toString(),
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
        break;
      }

      final finalUri = response.realUri;
      if (finalUri.path.startsWith('/auth/login') ||
          finalUri.path == '/login') {
        break;
      }

      final body = response.data;
      if (body == null || body.isEmpty) break;

      final parsed = _parser.parse(body, baseUri: finalUri);
      for (final entry in parsed.entries) {
        if (!seenWorkIds.add(entry.workId)) continue;

        final wasInLibrary = await _db.isInLibrary(source, entry.workId);
        final existingNovel = await _db.getNovel(source, entry.workId);

        if (existingNovel == null) {
          await _db.insertNovel(
            NovelInfo(
              source: source,
              workId: entry.workId,
              title: entry.title,
              writer: entry.writer,
            ).toDbCompanion(),
          );
        }

        await _db.addToLibrary(source, entry.workId);
        if (!wasInLibrary) importedCount++;
      }

      final next = parsed.nextPageUrl;
      if (next == null) break;
      currentUrl = next;
    }

    return importedCount;
  }

  @override
  Future<AccountSyncOutcome> addToRemoteLibrary(String workId) async {
    return AccountSyncOutcome.failed;
  }

  @override
  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId) async {
    return AccountSyncOutcome.failed;
  }

  @override
  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
  }) async {
    return false;
  }
}
