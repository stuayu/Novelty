import 'package:novelty/database/database.dart' as db;
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_info.dart';

/// [db.Novel] (DB Entity) から [NovelInfo] (Domain Model) への変換を行う拡張
extension NovelInfoFromDb on db.Novel {
  /// [db.Novel] を [NovelInfo] に変換する
  NovelInfo toModel({List<Episode>? episodes}) {
    return NovelInfo(
      ncode: ncode,
      title: title,
      writer: writer,
      story: story,
      novelType: novelType,
      end: end,
      genre: genre,
      generalAllNo: generalAllNo,
      keyword: keyword,
      // DBではソート可能な14桁整数、モデルではAPIと同じ日時文字列で扱う。
      generalFirstup: sortableIntToNarouDateTime(generalFirstup),
      generalLastup: sortableIntToNarouDateTime(generalLastup),

      globalPoint: globalPoint,

      reviewCnt: reviewCount,
      allHyokaCnt: rateCount,
      allPoint: allPoint,
      impressionCnt: pointCount,

      dailyPoint: dailyPoint,
      weeklyPoint: weeklyPoint,
      monthlyPoint: monthlyPoint,
      quarterPoint: quarterPoint,
      yearlyPoint: yearlyPoint,

      // DBはText, NovelInfoはInt
      novelupdatedAt: novelUpdatedAt != null
          ? int.tryParse(novelUpdatedAt!)
          : null,

      episodes: episodes, // そのまま渡す（既にEpisodeモデルのリスト）

      isr15: isr15,
      isbl: isbl,
      isgl: isgl,
      iszankoku: iszankoku,
      istensei: istensei,
      istenni: istenni,
    );
  }
}
