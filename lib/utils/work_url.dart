import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/alphapolis_uri.dart';
import 'package:novelty/utils/estar_uri.dart';
import 'package:novelty/utils/hameln_uri.dart';
import 'package:novelty/utils/ncode_utils.dart';
import 'package:novelty/utils/novelup_uri.dart';

/// 作品ページのURLを組み立てる。
///
/// - なろう: `https://ncode.syosetu.com/{ncode}/`
/// - カクヨム: `https://kakuyomu.jp/works/{workId}`
/// - アルファポリス: `https://www.alphapolis.co.jp/novel/{authorId}/{workId}`
String buildWorkUrl(
  NovelSource source, {
  String? ncode,
  String? workId,
}) {
  switch (source) {
    case NovelSource.narou:
      return '${source.baseUrl}/${ncode?.toNormalizedNcode() ?? ''}/';
    case NovelSource.kakuyomu:
      return '${source.baseUrl}/works/${workId ?? ''}';
    case NovelSource.alphapolis:
      return buildAlphapolisWorkUrl(workId ?? '');
    case NovelSource.hameln:
      return buildHamelnWorkUrl(workId ?? '');
    case NovelSource.estar:
      return buildEstarWorkUrl(workId ?? '');
    case NovelSource.novelup:
      return buildNovelupWorkUrl(workId ?? '');
  }
}
