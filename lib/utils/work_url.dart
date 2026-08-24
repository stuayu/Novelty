import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/alphapolis_uri.dart';
import 'package:novelty/utils/ncode_utils.dart';

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
  }
}
