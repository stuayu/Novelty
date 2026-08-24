import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novel_parser_core/novel_parser_core.dart';
import 'package:novelty/database/migration_helper.dart';
import 'package:novelty/models/episode.dart';
import 'package:novelty/models/novel_download_summary.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_history_parser.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'database_providers.dart';
export 'migration_helper.dart';

part 'database.g.dart';

/// [NovelSource] と DB の TEXT カラムを相互変換するコンバータ。
class NovelSourceConverter extends TypeConverter<NovelSource, String> {
  /// コンストラクタ
  const NovelSourceConverter();

  @override
  NovelSource fromSql(String fromDb) => NovelSource.values.byName(fromDb);

  @override
  String toSql(NovelSource value) => value.dbId;
}

/// v16 形状（ncode 主キー）の novels テーブルを作成する SQL。
///
/// レガシーバージョン（v12 未満）からのマイグレーションで使用する。
/// v17 への再構築は onUpgrade 末尾の _migrateToV17 で行う。
const String _v16CreateNovelsSql = '''
CREATE TABLE IF NOT EXISTS novels (
  ncode TEXT NOT NULL PRIMARY KEY,
  title TEXT,
  writer TEXT,
  user_id INTEGER,
  story TEXT,
  novel_type INTEGER,
  "end" INTEGER,
  genre INTEGER,
  isr15 INTEGER,
  isbl INTEGER,
  isgl INTEGER,
  iszankoku INTEGER,
  istensei INTEGER,
  istenni INTEGER,
  keyword TEXT,
  general_firstup INTEGER,
  general_lastup INTEGER,
  global_point INTEGER,
  fav INTEGER,
  review_count INTEGER,
  rate_count INTEGER,
  all_point INTEGER,
  point_count INTEGER,
  daily_point INTEGER,
  weekly_point INTEGER,
  monthly_point INTEGER,
  quarter_point INTEGER,
  yearly_point INTEGER,
  general_all_no INTEGER,
  novel_updated_at TEXT,
  cached_at INTEGER,
  is_private INTEGER NOT NULL DEFAULT 0
)
''';

/// v16 形状の library_entries テーブルを作成する SQL。
const String _v16CreateLibraryEntriesSql = '''
CREATE TABLE IF NOT EXISTS library_entries (
  ncode TEXT NOT NULL PRIMARY KEY REFERENCES novels(ncode),
  added_at INTEGER NOT NULL
)
''';

/// v16 形状の reading_history テーブルを作成する SQL。
const String _v16CreateReadingHistorySql = '''
CREATE TABLE IF NOT EXISTS reading_history (
  ncode TEXT NOT NULL PRIMARY KEY REFERENCES novels(ncode),
  last_episode_id INTEGER,
  viewed_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT 0
)
''';

/// v16 形状の episode_list_entries テーブルを作成する SQL。
const String _v16CreateEpisodeListEntriesSql = '''
CREATE TABLE IF NOT EXISTS episode_list_entries (
  ncode TEXT NOT NULL REFERENCES novels(ncode),
  episode_id INTEGER NOT NULL,
  subtitle TEXT,
  url TEXT,
  published_at TEXT,
  revised_at TEXT,
  fetched_at INTEGER,
  PRIMARY KEY (ncode, episode_id)
)
''';

/// v16 形状の episode_contents テーブルを作成する SQL。
const String _v16CreateEpisodeContentsSql = '''
CREATE TABLE IF NOT EXISTS episode_contents (
  ncode TEXT NOT NULL REFERENCES novels(ncode),
  episode_id INTEGER NOT NULL,
  content TEXT,
  fetched_at INTEGER,
  revised_at TEXT,
  PRIMARY KEY (ncode, episode_id)
)
''';

/// 小説のコンテンツをデータベースに保存するための変換クラス
///
/// Hybrid JSON `{"txt":..., "rb":[...]}` 形式で保存する。旧verbose形式も読込可能。
class ContentConverter
    extends TypeConverter<List<NovelContentElement>, String> {
  /// コンストラクタ
  const ContentConverter();

  @override
  List<NovelContentElement> fromSql(String fromDb) {
    if (fromDb.isEmpty) {
      return [];
    }
    // HybridConverter が旧verboseと新Hybridの両方を読む
    return HybridConverter.fromHybridJson(fromDb);
  }

  @override
  String toSql(List<NovelContentElement> value) {
    return HybridConverter.toHybridJson(value);
  }
}

/// 履歴データのDTOクラス
/// 旧Historyテーブルのデータクラスと互換性を持たせるために定義
@immutable
class HistoryData {
  /// コンストラクタ
  const HistoryData({
    required this.source,
    required this.workId,
    required this.viewedAt,
    required this.updatedAt,
    this.title,
    this.writer,
    this.lastEpisode,
  });

  /// 提供サイト（プロバイダ）
  final NovelSource source;

  /// サイト共通の作品ID
  final String workId;

  /// タイトル
  final String? title;

  /// 作者名
  final String? writer;

  /// 最後に読んだエピソード番号
  final int? lastEpisode;

  /// 閲覧日時（UNIXタイムスタンプ）
  final int viewedAt;

  /// 更新日時（UNIXタイムスタンプ）
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryData &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          workId == other.workId &&
          title == other.title &&
          writer == other.writer &&
          lastEpisode == other.lastEpisode &&
          viewedAt == other.viewedAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      source.hashCode ^
      workId.hashCode ^
      title.hashCode ^
      writer.hashCode ^
      lastEpisode.hashCode ^
      viewedAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'HistoryData('
        'workId: $workId, title: $title, writer: $writer, '
        'lastEpisode: $lastEpisode, viewedAt: $viewedAt, '
        'updatedAt: $updatedAt)';
  }
}

/// 外部サイト閲覧履歴の同期結果。
class RemoteHistoryMergeResult {
  /// コンストラクタ。
  const RemoteHistoryMergeResult({
    required this.inserted,
    required this.updated,
  });

  /// 新規登録数。
  final int inserted;

  /// 更新数。
  final int updated;
}

// テーブル定義
/// 小説情報を格納するテーブル（マスターテーブル）
class Novels extends Table {
  /// 提供サイト（プロバイダ）
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// サイト共通の作品ID（なろうはNコード）
  TextColumn get workId => text()();

  /// 小説のタイトル
  TextColumn get title => text().nullable()();

  /// 小説の著者
  TextColumn get writer => text().nullable()();

  /// ユーザID
  IntColumn get userId => integer().nullable()();

  /// 小説のあらすじ
  TextColumn get story => text().nullable()();

  /// キャッチコピー
  TextColumn get catchphrase => text().nullable()();

  /// 小説の種別
  /// 0: 短編 1: 連載中
  IntColumn get novelType => integer().nullable()();

  /// 小説の状態
  /// 0: 短編 or 完結済 1: 連載中
  IntColumn get end => integer().nullable()();

  /// ジャンル
  /// サイト共通のジャンルID（文字列）
  TextColumn get genreId => text().nullable()();

  /// 作品に含まれる要素に「R15」が含まれる場合は1、それ以外は0
  IntColumn get isr15 => integer().nullable()();

  /// 作品に含まれる要素に「ボーイズラブ」が含まれる場合は1、それ以外は0
  IntColumn get isbl => integer().nullable()();

  /// 作品に含まれる要素に「ガールズラブ」が含まれる場合は1、それ以外は0
  IntColumn get isgl => integer().nullable()();

  /// 作品に含まれる要素に「残酷な描写あり」が含まれる場合は1、それ以外は0
  IntColumn get iszankoku => integer().nullable()();

  /// 作品に含まれる要素に「異世界転生」が含まれる場合は1、それ以外は0
  IntColumn get istensei => integer().nullable()();

  /// 作品に含まれる要素に「異世界転移」が含まれる場合は1、それ以外は0
  IntColumn get istenni => integer().nullable()();

  /// キーワード
  TextColumn get keyword => text().nullable()();

  /// 初回掲載日 YYYY-MM-DD HH:MM:SS
  IntColumn get generalFirstup => integer().nullable()();

  /// 最終掲載日 YYYY-MM-DD HH:MM:SS
  IntColumn get generalLastup => integer().nullable()();

  /// 総合評価ポイント (ブックマーク数×2)+評価ポイントで算出
  IntColumn get globalPoint => integer().nullable()();

  /// Noveltyのライブラリに登録されているかどうか
  /// 1: 登録済み、0: 未登録
  /// DEPRECATED: LibraryEntriesテーブルを使用するため、このカラムは使用しない
  IntColumn get fav => integer().nullable()();

  /// レビュー数
  IntColumn get reviewCount => integer().nullable()();

  /// フォロー数
  IntColumn get followCount => integer().nullable()();

  /// レビューの平均評価(?)
  IntColumn get rateCount => integer().nullable()();

  /// 評価ポイント
  IntColumn get allPoint => integer().nullable()();

  /// ポイント数(何の用途か不明)
  IntColumn get pointCount => integer().nullable()();

  /// 日間ポイント
  IntColumn get dailyPoint => integer().nullable()();

  /// 週間ポイント
  IntColumn get weeklyPoint => integer().nullable()();

  /// 月間ポイント
  IntColumn get monthlyPoint => integer().nullable()();

  /// 四半期ポイント
  IntColumn get quarterPoint => integer().nullable()();

  /// 年間ポイント
  IntColumn get yearlyPoint => integer().nullable()();

  /// 連載小説のエピソード数 短編は常に1
  IntColumn get generalAllNo => integer().nullable()();

  /// 総文字数
  IntColumn get totalCharacterCount => integer().nullable()();

  /// 作品の更新日時
  TextColumn get novelUpdatedAt => text().nullable()();

  /// キャッシュ日時(?)
  IntColumn get cachedAt => integer().nullable()();

  /// 非公開(凍結・削除等)かどうか
  /// true: 非公開、false: 公開中
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {source, workId};
}

/// ライブラリの小説と、ライブラリへの追加日時を組み合わせたデータ。
///
/// [Novels]テーブルには追加日時の情報が無いため、
/// [AppDatabase.watchLibraryNovels]の結果として利用する。
@immutable
class LibraryNovelEntry {
  /// コンストラクタ。
  const LibraryNovelEntry({
    required this.novel,
    required this.addedAt,
    this.lastViewedAt,
  });

  /// 小説データ。
  final Novel novel;

  /// ライブラリに追加された日時（UNIXミリ秒）。
  final int addedAt;

  /// アプリの閲覧履歴での最終閲覧日時（UNIXミリ秒）。
  ///
  /// 一度も読んでいない場合は`null`。
  final int? lastViewedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryNovelEntry &&
          runtimeType == other.runtimeType &&
          novel == other.novel &&
          addedAt == other.addedAt &&
          lastViewedAt == other.lastViewedAt;

  @override
  int get hashCode => Object.hash(novel, addedAt, lastViewedAt);
}

/// しおり更新(`ichiupdateajax`)に必要な、なろう本家のトークン情報。
@immutable
class NarouFavToken {
  /// コンストラクタ。
  const NarouFavToken({required this.useridFavncode, required this.token});

  /// なろう本家のブックマークID（"{userid}_{favncode}"形式）。
  final String useridFavncode;

  /// なろう本家のブックマーク操作用トークン。
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NarouFavToken &&
          runtimeType == other.runtimeType &&
          useridFavncode == other.useridFavncode &&
          token == other.token;

  @override
  int get hashCode => Object.hash(useridFavncode, token);
}

/// ライブラリ登録情報を格納するテーブル（正規化済み）
class LibraryEntries extends Table {
  /// 提供サイト（プロバイダ）
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// 小説の作品ID（参照整合性はアプリ層で担保）
  TextColumn get workId => text()();

  /// ライブラリに追加された日時
  /// UNIXタイムスタンプ形式で保存される
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {source, workId};
}

/// なろう本家へのブックマーク同期情報を格納するテーブル（正規化済み）
///
/// [Novels] / [LibraryEntries] とは別テーブルとして分離することで、
/// なろう固有の同期情報が他プロバイダ（カクヨム等）のテーブルを
/// 汚さないようにする。`source` が `NovelSource.narou` の行のみが対象。
class NarouSyncEntries extends Table {
  /// 提供サイト（プロバイダ）。常に[NovelSource.narou]。
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// 小説の作品ID（なろうのNコード。参照整合性はアプリ層で担保）
  TextColumn get workId => text()();

  /// なろう本家へのブックマーク登録が成功した日時（UNIXミリ秒）。
  /// nullの場合はなろう側への同期が未完了・未確認であることを示す。
  IntColumn get narouBookmarkSyncedAt => integer().nullable()();

  /// なろう本家のブックマークID（"{userid}_{favncode}"形式）。
  /// しおり更新(ichiupdateajax)のURL構築に使用する。
  TextColumn get narouUseridFavncode => text().nullable()();

  /// なろう本家のブックマーク操作用トークン（addajax登録時に発行される）。
  /// しおり更新(ichiupdateajax)のtokenパラメータとして再利用する。
  TextColumn get narouFavToken => text().nullable()();

  @override
  Set<Column> get primaryKey => {source, workId};
}

/// 閲覧履歴を格納するテーブル（正規化済み）
class ReadingHistory extends Table {
  /// 提供サイト（プロバイダ）
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// 小説の作品ID（参照整合性はアプリ層で担保）
  TextColumn get workId => text()();

  /// 最後に閲覧したエピソード番号
  IntColumn get lastEpisodeId => integer().nullable()();

  /// 閲覧日時
  IntColumn get viewedAt => integer()();

  /// 更新日時
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {source, workId};
}

/// エピソード目次(メタデータ)を格納するテーブル
/// 旧EpisodeEntitiesテーブルから目次情報を分離したもの
class EpisodeListEntries extends Table {
  /// 提供サイト（プロバイダ）
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// 小説の作品ID（参照整合性はアプリ層で担保）
  TextColumn get workId => text()();

  /// エピソード番号
  IntColumn get episodeId => integer()();

  /// サブタイトル（目次用）
  TextColumn get subtitle => text().nullable()();

  /// URL
  TextColumn get url => text().nullable()();

  /// 掲載日（APIのupdate）
  TextColumn get publishedAt => text().nullable()();

  /// 改稿日（APIのrevised）
  TextColumn get revisedAt => text().nullable()();

  /// 目次の最終取得日時（UNIXタイムスタンプ・ミリ秒）
  IntColumn get fetchedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {source, workId, episodeId};
}

/// エピソード本文(キャッシュ)を格納するテーブル
/// 旧EpisodeEntitiesテーブルから本文キャッシュを分離したもの
class EpisodeContents extends Table {
  /// 提供サイト（プロバイダ）
  TextColumn get source => text().map(const NovelSourceConverter())();

  /// 小説の作品ID（参照整合性はアプリ層で担保）
  TextColumn get workId => text()();

  /// エピソード番号
  IntColumn get episodeId => integer()();

  /// エピソードの内容（キャッシュ）
  /// JSON形式で保存される。空配列=失敗、中身あり=成功、NULL=未取得
  TextColumn get content => text().map(const ContentConverter()).nullable()();

  /// 本文の最終取得日時（UNIXタイムスタンプ・ミリ秒）
  IntColumn get fetchedAt => integer().nullable()();

  /// 本文改訂判定用の改稿日
  TextColumn get revisedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {source, workId, episodeId};
}

/// 目次と本文を結合したエピソード情報のDTO
@immutable
class EpisodeData {
  /// コンストラクタ
  const EpisodeData({
    required this.source,
    required this.workId,
    required this.episodeId,
    this.subtitle,
    this.url,
    this.publishedAt,
    this.revisedAt,
    this.content,
    this.fetchedAt,
  });

  /// 提供サイト（プロバイダ）
  final NovelSource source;

  /// サイト共通の作品ID
  final String workId;

  /// エピソード番号
  final int episodeId;

  /// サブタイトル
  final String? subtitle;

  /// URL
  final String? url;

  /// 掲載日
  final String? publishedAt;

  /// 改稿日
  final String? revisedAt;

  /// エピソードの内容（キャッシュ）
  final List<NovelContentElement>? content;

  /// 本文の最終取得日時
  final int? fetchedAt;
}

@DriftDatabase(
  tables: [
    Novels,
    LibraryEntries,
    NarouSyncEntries,
    ReadingHistory,
    EpisodeListEntries,
    EpisodeContents,
  ],
)
/// アプリケーションのデータベース
class AppDatabase extends _$AppDatabase {
  /// コンストラクタ
  AppDatabase() : super(_openConnection());

  /// テスト用コンストラクタ
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// テスト用コンストラクタ（任意のQueryExecutorを指定する）
  AppDatabase.test(super.e);

  /// 現在のデータベーススキーマバージョン
  static const int currentSchemaVersion = 23;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _migrateToV22();
        await _migrateToV23();
      },
      onUpgrade: (m, from, to) async {
        try {
          if (from < 12) {
            // 以前のマイグレーション失敗などでテーブルが中途半端に存在する可能性があるため、
            // 既存の新規テーブルはそのまま残し、不足データを補填する形で移行する。
            // なお、これらのテーブルは v16 形状（ncode 主キー）で作成する。
            // v17 への再構築はこの onUpgrade の末尾（from < 17 ブランチ）で行う。

            // 1. 新規テーブルが存在しない場合のみ作成する（v16形状）
            await customStatement(_v16CreateNovelsSql);
            await customStatement(_v16CreateLibraryEntriesSql);
            await customStatement(_v16CreateReadingHistorySql);
            // 旧episodesテーブル(v12〜v15で使用)を作成する
            // v16マイグレーションで目次・本文テーブルへ分割される
            await customStatement('''
                  CREATE TABLE IF NOT EXISTS episodes (
                    ncode TEXT NOT NULL REFERENCES novels(ncode),
                    episode_id INTEGER NOT NULL,
                    subtitle TEXT,
                    url TEXT,
                    published_at TEXT,
                    revised_at TEXT,
                    content TEXT,
                    fetched_at INTEGER,
                    PRIMARY KEY (ncode, episode_id)
                  );
                ''');

            // 2. library_novels から library_entries と novels へ移行
            final libraryNovelsResult = await customSelect(
              '''
                SELECT name FROM sqlite_master
                WHERE type='table' AND name='library_novels'
                ''',
            ).get();
            if (libraryNovelsResult.isNotEmpty) {
              await customStatement('''
                    INSERT OR IGNORE INTO novels (
                      ncode, title, writer, story, novel_type, "end", general_all_no, novel_updated_at
                    )
                    SELECT
                      ncode, title, writer, story, novel_type, "end", general_all_no, novel_updated_at
                    FROM library_novels;
                  ''');

              await customStatement('''
                    INSERT OR IGNORE INTO library_entries (ncode, added_at)
                    SELECT ncode, added_at FROM library_novels;
                  ''');
            }

            // 3. history から reading_history と novels へ移行
            final historyResult = await customSelect(
              '''
                SELECT name FROM sqlite_master
                WHERE type='table' AND name='history'
                ''',
            ).get();
            if (historyResult.isNotEmpty) {
              await customStatement('''
                    INSERT OR IGNORE INTO novels (ncode, cached_at)
                    SELECT ncode, viewed_at FROM history
                    WHERE viewed_at IS NOT NULL;
                  ''');

              await customStatement('''
                    UPDATE novels
                    SET cached_at = (
                      SELECT viewed_at FROM history
                      WHERE history.ncode = novels.ncode
                    )
                    WHERE EXISTS (
                      SELECT 1 FROM history
                      WHERE history.ncode = novels.ncode
                    );
                  ''');

              await customStatement('''
                    INSERT OR IGNORE INTO reading_history
                      (ncode, last_episode_id, viewed_at, updated_at)
                    SELECT ncode, last_episode, viewed_at, updated_at FROM history;
                  ''');
            }

            // 4. cached_episodes から episodes へ移行

            // 古いキャッシュエピソードテーブルが存在するか確認する
            final cachedEpisodesResult = await customSelect(
              'SELECT name FROM sqlite_master '
              "WHERE type='table' AND name='cached_episodes'",
            ).get();

            if (cachedEpisodesResult.isNotEmpty) {
              await customStatement('''
                    INSERT OR IGNORE INTO episodes
                      (ncode, episode_id, content, fetched_at, revised_at)
                    SELECT ncode, episode, content, cached_at, revised FROM cached_episodes;
                  ''');
            }

            // 5. 旧テーブルを削除する
            await customStatement('DROP TABLE IF EXISTS library_novels');
            await customStatement('DROP TABLE IF EXISTS history');
            await customStatement('DROP TABLE IF EXISTS cached_episodes');
          }

          if (from < 13) {
            // バージョン13のマイグレーション（トリガー方式のFTS）
            // - バージョン14で上書きされるためスキップ
          }

          if (from < 16) {
            // 旧episodesテーブルを目次・本文の2テーブルに分割する
            // ここでは v16 形状（ncode 主キー）で作成する（v17再構築は末尾）
            await customStatement(_v16CreateEpisodeListEntriesSql);
            await customStatement(_v16CreateEpisodeContentsSql);

            // episodes テーブルが存在する場合のみデータを引き継ぐ
            // （マイグレーション中断により episodes が既に削除されている可能性もあるため）
            if (await m.tableExists('episodes')) {
              // 目次データの引き継ぎ(目次の取得日時は旧スキーマに存在しないためNULL)
              // 競合時は episodes 側の完全な値で上書きする
              await customStatement('''
                    INSERT OR IGNORE INTO episode_list_entries
                      (ncode, episode_id, subtitle, url, published_at, revised_at, fetched_at)
                    SELECT ncode, episode_id, subtitle, url, published_at, revised_at, NULL
                    FROM episodes;
                  ''');

              await customStatement('''
                    UPDATE episode_list_entries
                    SET subtitle = (
                        SELECT subtitle FROM episodes
                        WHERE episodes.ncode = episode_list_entries.ncode
                          AND episodes.episode_id = episode_list_entries.episode_id
                      ),
                      url = (
                        SELECT url FROM episodes
                        WHERE episodes.ncode = episode_list_entries.ncode
                          AND episodes.episode_id = episode_list_entries.episode_id
                      ),
                      published_at = (
                        SELECT published_at FROM episodes
                        WHERE episodes.ncode = episode_list_entries.ncode
                          AND episodes.episode_id = episode_list_entries.episode_id
                      ),
                      revised_at = (
                        SELECT revised_at FROM episodes
                        WHERE episodes.ncode = episode_list_entries.ncode
                          AND episodes.episode_id = episode_list_entries.episode_id
                      )
                    WHERE EXISTS (
                      SELECT 1 FROM episodes
                      WHERE episodes.ncode = episode_list_entries.ncode
                        AND episodes.episode_id = episode_list_entries.episode_id
                    );
                  ''');

              // 本文データの引き継ぎ(content IS NOT NULL の行のみ)
              // 競合時は episodes 側の完全な値で上書きする
              await customStatement('''
                    INSERT OR IGNORE INTO episode_contents
                      (ncode, episode_id, content, fetched_at, revised_at)
                    SELECT ncode, episode_id, content, fetched_at, revised_at
                    FROM episodes
                    WHERE content IS NOT NULL;
                  ''');

              await customStatement('''
                    UPDATE episode_contents
                    SET content = (
                        SELECT content FROM episodes
                        WHERE episodes.ncode = episode_contents.ncode
                          AND episodes.episode_id = episode_contents.episode_id
                      ),
                      fetched_at = (
                        SELECT fetched_at FROM episodes
                        WHERE episodes.ncode = episode_contents.ncode
                          AND episodes.episode_id = episode_contents.episode_id
                      ),
                      revised_at = (
                        SELECT revised_at FROM episodes
                        WHERE episodes.ncode = episode_contents.ncode
                          AND episodes.episode_id = episode_contents.episode_id
                      )
                    WHERE EXISTS (
                      SELECT 1 FROM episodes
                      WHERE episodes.ncode = episode_contents.ncode
                        AND episodes.episode_id = episode_contents.episode_id
                    );
                  ''');

              await customStatement('DROP TABLE IF EXISTS episodes');
            }

            // 非公開フラグカラムの追加
            // (v12未満からのマイグレーションではNovelsが新スキーマで作成済みのため不要)
            if (from >= 12) {
              await m.addColumnIfNotExists(novels, novels.isPrivate);
            }
          }

          if (from >= 12 && from < 15) {
            await m.addColumnIfNotExists(novels, novels.userId);
          }

          if (from < 17) {
            // v17: 複数プロバイダ対応（カクヨム対応 #240）
            // 全テーブルの主キーを (source, work_id)（エピソード系は
            // (source, work_id, episode_id)）に移行する。
            // 既存データは source='narou' として100%維持する。
            // ジャンルは INTEGER → TEXT（genre_id）に変換する。
            await _migrateToV17();
          }

          if (from < 18) {
            // v18: Hybrid JSON への移行と episodes_search 廃止
            // episode_contents.content を verbose → Hybrid {txt,rb} に変換し、
            // 巨大な episodes_search FTS を削除して DB を半減させる
            await _migrateToV18();
          }

          if (from < 19) {
            // v19: novels_search FTS5 の撤去（本文検索は機能ごと削除）
            // 小説検索は SQL の LIKE 部分一致へ置換し、FTS5 仮想テーブルと
            // index 用コードを削除する。
            // DROP 後に VACUUM を実行し、物理ファイルのサイズも回収する。
            await _migrateToV19();
          }

          if (from < 20) {
            // v20: なろう本家ブックマーク同期用の情報を、既存テーブルを汚さず
            // 専用テーブル（narou_sync_entries）に分離して追加する。
            await _migrateToV20();
          }

          if (from < 21) {
            // v21: サイト共通作品メタデータ（キャッチコピー・文字数・フォロー数）を追加する。
            await _migrateToV21(m);
          }

          if (from < 22) {
            await _migrateToV22();
          }

          if (from < 23) {
            await _migrateToV23();
          }
        } on MigrationException {
          rethrow;
        } on Object catch (e) {
          final exception = MigrationException(
            fromVersion: from,
            toVersion: to,
            step: 'onUpgrade',
            cause: e,
          );
          await _saveMigrationErrorReport(exception);
          throw exception;
        }

        await _clearMigrationErrorReports();
      },
    );
  }

  Future<void> _saveMigrationErrorReport(MigrationException exception) async {
    try {
      final dbFilePath = await _databaseFilePath();
      final report = MigrationErrorReport.fromException(
        exception,
        dbFilePath: dbFilePath,
      );
      await saveMigrationErrorReport(report);
    } on Exception catch (e) {
      // レポート保存自体の失敗は無視する（マイグレーション失敗より重要ではない）
      debugPrint('マイグレーションエラーレポートの保存に失敗しました: $e');
    }
  }

  Future<String?> _databaseFilePath() async {
    try {
      final rows = await customSelect('PRAGMA database_list').get();
      for (final row in rows) {
        if (row.read<int>('seq') == 0) {
          return row.read<String?>('file');
        }
      }
      return null;
    } on Exception {
      return null;
    }
  }

  Future<void> _clearMigrationErrorReports() async {
    try {
      await clearMigrationErrorReports();
    } on Exception catch (e) {
      debugPrint('マイグレーションエラーレポートの削除に失敗しました: $e');
    }
  }

  /// v16 → v17 マイグレーションを実行する。
  ///
  /// 複数プロバイダ対応（カクヨム対応 #240）の一環で、全テーブルの主キーを
  /// `(source, work_id)`（エピソード系は `(source, work_id, episode_id)`）に
  /// 移行する。既存データは `source='narou'` として100%維持する。
  /// ジャンルは INTEGER → TEXT（genre_id）に変換する。
  Future<void> _migrateToV17() async {
    // 外部キー制約を一時的に無効化してテーブル再構築を行う
    await customStatement('PRAGMA foreign_keys = OFF');

    /// テーブルの存在確認（旧バージョンでは存在しないテーブルがあるため）
    Future<bool> tableExists(String name) async {
      final result = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        variables: [Variable.withString(name)],
      ).get();
      return result.isNotEmpty;
    }

    // デバッグ用: 各ステップの失敗箇所を特定する
    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } on Object catch (e) {
        debugPrint('MIGRATE_V17_STEP_FAILED: $name -> $e');
        rethrow;
      }
    }

    // ---- novels ----
    await step('novels', () async {
      await customStatement('''
      CREATE TABLE novels_v17 (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        title TEXT,
        writer TEXT,
        user_id INTEGER,
        story TEXT,
        novel_type INTEGER,
        "end" INTEGER,
        genre_id TEXT,
        isr15 INTEGER,
        isbl INTEGER,
        isgl INTEGER,
        iszankoku INTEGER,
        istensei INTEGER,
        istenni INTEGER,
        keyword TEXT,
        general_firstup INTEGER,
        general_lastup INTEGER,
        global_point INTEGER,
        fav INTEGER,
        review_count INTEGER,
        rate_count INTEGER,
        all_point INTEGER,
        point_count INTEGER,
        daily_point INTEGER,
        weekly_point INTEGER,
        monthly_point INTEGER,
        quarter_point INTEGER,
        yearly_point INTEGER,
        general_all_no INTEGER,
        novel_updated_at TEXT,
        cached_at INTEGER,
        is_private INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source, work_id)
      )
    ''');
      await customStatement('''
      INSERT INTO novels_v17 (
        source, work_id, title, writer, user_id, story, novel_type, "end",
        genre_id, isr15, isbl, isgl, iszankoku, istensei, istenni, keyword,
        general_firstup, general_lastup, global_point, fav, review_count,
        rate_count, all_point, point_count, daily_point, weekly_point,
        monthly_point, quarter_point, yearly_point, general_all_no,
        novel_updated_at, cached_at, is_private
      )
      SELECT 'narou', ncode, title, writer, user_id, story, novel_type, "end",
        CAST(genre AS TEXT), isr15, isbl, isgl, iszankoku, istensei, istenni,
        keyword, general_firstup, general_lastup, global_point, fav,
        review_count, rate_count, all_point, point_count, daily_point,
        weekly_point, monthly_point, quarter_point, yearly_point,
        general_all_no, novel_updated_at, cached_at, is_private
      FROM novels
    ''');
      await customStatement('DROP TABLE novels');
      await customStatement('ALTER TABLE novels_v17 RENAME TO novels');
    });

    // ---- library_entries ----
    await step('library_entries', () async {
      if (!await tableExists('library_entries')) return;
      await customStatement('''
      CREATE TABLE library_entries_v17 (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (source, work_id)
      )
    ''');
      await customStatement('''
      INSERT INTO library_entries_v17 (source, work_id, added_at)
      SELECT 'narou', ncode, added_at FROM library_entries
    ''');
      await customStatement('DROP TABLE library_entries');
      await customStatement(
        'ALTER TABLE library_entries_v17 RENAME TO library_entries',
      );
    });

    // ---- reading_history ----
    await step('reading_history', () async {
      if (!await tableExists('reading_history')) return;
      await customStatement('''
      CREATE TABLE reading_history_v17 (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        last_episode_id INTEGER,
        viewed_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source, work_id)
      )
    ''');
      await customStatement('''
      INSERT INTO reading_history_v17 (
        source, work_id, last_episode_id, viewed_at, updated_at
      )
      SELECT 'narou', ncode, last_episode_id, viewed_at, updated_at
      FROM reading_history
    ''');
      await customStatement('DROP TABLE reading_history');
      await customStatement(
        'ALTER TABLE reading_history_v17 RENAME TO reading_history',
      );
    });

    // ---- episode_list_entries ----
    await step('episode_list_entries', () async {
      if (!await tableExists('episode_list_entries')) return;
      await customStatement('''
      CREATE TABLE episode_list_entries_v17 (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        episode_id INTEGER NOT NULL,
        subtitle TEXT,
        url TEXT,
        published_at TEXT,
        revised_at TEXT,
        fetched_at INTEGER,
        PRIMARY KEY (source, work_id, episode_id)
      )
    ''');
      await customStatement('''
      INSERT INTO episode_list_entries_v17 (
        source, work_id, episode_id, subtitle, url, published_at, revised_at,
        fetched_at
      )
      SELECT 'narou', ncode, episode_id, subtitle, url, published_at,
        revised_at, fetched_at
      FROM episode_list_entries
    ''');
      await customStatement('DROP TABLE episode_list_entries');
      await customStatement(
        'ALTER TABLE episode_list_entries_v17 RENAME TO episode_list_entries',
      );
    });

    // ---- episode_contents ----
    await step('episode_contents', () async {
      if (!await tableExists('episode_contents')) return;
      await customStatement('''
      CREATE TABLE episode_contents_v17 (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        episode_id INTEGER NOT NULL,
        content TEXT,
        fetched_at INTEGER,
        revised_at TEXT,
        PRIMARY KEY (source, work_id, episode_id)
      )
    ''');
      await customStatement('''
      INSERT INTO episode_contents_v17 (
        source, work_id, episode_id, content, fetched_at, revised_at
      )
      SELECT 'narou', ncode, episode_id, content, fetched_at, revised_at
      FROM episode_contents
    ''');
      await customStatement('DROP TABLE episode_contents');
      await customStatement(
        'ALTER TABLE episode_contents_v17 RENAME TO episode_contents',
      );
    });

    await customStatement('PRAGMA foreign_keys = ON');
  }

  /// v18 マイグレーション: Hybrid JSON への変換と episodes_search 廃止
  Future<void> _migrateToV18() async {
    // 1. episode_contents.content を verbose → Hybrid {txt,rb} に変換
    // 11,077件 × 平均13KB なのでメモリに全件載せてバッチ更新する
    final rows = await customSelect(
      'SELECT source, work_id, episode_id, content FROM episode_contents '
      'WHERE content IS NOT NULL',
      readsFrom: {episodeContents},
    ).get();

    for (final row in rows) {
      final content = row.read<String>('content');
      final trimmed = content.trimLeft();

      // 空の表現は Hybrid 空値へ正規化する。
      // それ以外の表現はそのままの形を維持しても DB 上の意味は同等だが、
      // 集計 SQL が '{"txt":"","rb":[]}' を「未ダウンロード」として扱うため、
      // ここで統一しておく（空文字や '[]' が誤って成功扱いされるのを防ぐ）。
      const hybridEmpty = '{"txt":"","rb":[]}';
      if (content.isEmpty || content == '[]' || content == hybridEmpty) {
        if (content != hybridEmpty) {
          await customStatement(
            'UPDATE episode_contents SET content = ? '
            'WHERE source = ? AND work_id = ? AND episode_id = ?',
            [
              hybridEmpty,
              row.read<String>('source'),
              row.read<String>('work_id'),
              row.read<int>('episode_id'),
            ],
          );
        }
        continue;
      }

      // 既に Hybrid ならスキップ
      if (trimmed.startsWith('{"txt"') || trimmed.startsWith('{"rb"')) {
        continue;
      }
      try {
        final elements = HybridConverter.fromHybridJson(content);
        final hybrid = HybridConverter.toHybridJson(elements);
        if (hybrid == content) continue;
        await customStatement(
          'UPDATE episode_contents SET content = ? '
          'WHERE source = ? AND work_id = ? AND episode_id = ?',
          [
            hybrid,
            row.read<String>('source'),
            row.read<String>('work_id'),
            row.read<int>('episode_id'),
          ],
        );
      } on Object {
        // パース失敗はスキップ（元のまま残す）
        continue;
      }
    }

    // 2. 巨大な episodes_search FTS を削除（456MB削減）
    // 仮想テーブルを DROP すると shadow テーブルも自動削除されるが、念のため個別にも DROP
    await customStatement('DROP TABLE IF EXISTS episodes_search');
    await customStatement('DROP TABLE IF EXISTS episodes_search_data');
    await customStatement('DROP TABLE IF EXISTS episodes_search_idx');
    await customStatement('DROP TABLE IF EXISTS episodes_search_content');
    await customStatement('DROP TABLE IF EXISTS episodes_search_docsize');
    await customStatement('DROP TABLE IF EXISTS episodes_search_config');
  }

  /// v19 マイグレーション: novels_search FTS5 の撤去とファイルサイズの回収
  ///
  /// - 本文・サブタイトル検索は機能ごと削除し、小説検索は SQL の LIKE 部分一致へ
  ///   置換するため、FTS5 仮想テーブル novels_search（および shadow テーブル）を
  ///   DROP する。
  /// - DROP だけでは解放されたページが物理ファイル内に残ってサイズが減らないため、
  ///   続けて VACUUM を実行してファイルを切り詰める。
  ///   （Drift の onCreate / onUpgrade はトランザクション外で実行されるため、
  ///     VACUUM をそのまま呼び出せることを確認済み）
  Future<void> _migrateToV19() async {
    // novels_search を撤去（shadow テーブルも念のため個別に DROP）
    await customStatement('DROP TABLE IF EXISTS novels_search');
    await customStatement('DROP TABLE IF EXISTS novels_search_data');
    await customStatement('DROP TABLE IF EXISTS novels_search_idx');
    await customStatement('DROP TABLE IF EXISTS novels_search_content');
    await customStatement('DROP TABLE IF EXISTS novels_search_docsize');
    await customStatement('DROP TABLE IF EXISTS novels_search_config');

    // 物理ファイルサイズを回収する。FTS 撤去で生じた空きページもここで詰められる。
    await customStatement('VACUUM');
  }

  Future<void> _migrateToV20() async {
    // なろう本家ブックマーク同期用の情報を、既存テーブル（library_entries等）
    // を汚さず専用テーブルとして新設する。以前のバージョンではこの情報は
    // どこにも保存されていなかったため、データ移行は不要。
    await customStatement('''
      CREATE TABLE IF NOT EXISTS narou_sync_entries (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        narou_bookmark_synced_at INTEGER,
        narou_userid_favncode TEXT,
        narou_fav_token TEXT,
        PRIMARY KEY (source, work_id)
      )
    ''');
  }

  Future<void> _migrateToV21(Migrator m) async {
    await m.addColumnIfNotExists(novels, novels.catchphrase);
    await m.addColumnIfNotExists(novels, novels.totalCharacterCount);
    await m.addColumnIfNotExists(novels, novels.followCount);
  }

  Future<void> _migrateToV22() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS remote_reading_histories (
        source TEXT NOT NULL,
        work_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        last_read_at INTEGER,
        synced_at INTEGER NOT NULL,
        title TEXT,
        episode_title TEXT,
        PRIMARY KEY (source, work_id, episode_id)
      )
    ''');
  }

  Future<void> _migrateToV23() async {
    final tables = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'episode_list_entries'",
    ).get();
    if (tables.isEmpty) return;

    await customStatement('''
      UPDATE episode_list_entries
      SET subtitle = NULLIF(subtitle, ''),
          url = NULLIF(url, ''),
          published_at = NULLIF(published_at, ''),
          revised_at = NULLIF(revised_at, '')
      WHERE subtitle = ''
         OR url = ''
         OR published_at = ''
         OR revised_at = ''
    ''');
  }

  /// 小説情報の取得
  Future<Novel?> getNovel(NovelSource source, String workId) {
    return (select(novels)..where(
          (t) => t.source.equalsValue(source) & t.workId.equals(workId),
        ))
        .getSingleOrNull();
  }

  /// 小説情報の監視
  Stream<Novel?> watchNovel(NovelSource source, String workId) {
    return (select(novels)..where(
          (t) => t.source.equalsValue(source) & t.workId.equals(workId),
        ))
        .watchSingleOrNull();
  }

  /// 小説の検索
  ///
  /// ライブラリ登録済みの小説を対象に、クエリ文字列をそのまま タイトル / 作者 /
  /// あらすじ のいずれかに部分一致する小説を返す。
  /// 並び順はライブラリ追加日時の新しい順とする（一覧表示と一致）。
  ///
  /// 全件をメモリにロードせず、SQL の LIKE で絞り込んでから返す。
  Future<List<Novel>> searchNovels(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // LIKE のワイルドカード（% / _）をエスケープし、クエリを文字通り検索する
    final pattern = '%${_escapeLike(trimmed)}%';

    final results = await customSelect(
      r'''
      SELECT n.* FROM novels n
      JOIN library_entries le
        ON n.source = le.source AND n.work_id = le.work_id
      WHERE n.title LIKE ? ESCAPE '\'
         OR n.writer LIKE ? ESCAPE '\'
         OR n.story LIKE ? ESCAPE '\'
      ORDER BY le.added_at DESC
      ''',
      variables: [
        Variable.withString(pattern),
        Variable.withString(pattern),
        Variable.withString(pattern),
      ],
      readsFrom: {novels, libraryEntries},
    ).get();

    return results.map((row) => novels.map(row.data)).toList();
  }

  /// LIKE パターン内で特別な意味を持つ文字を、ESCAPE 文字でエスケープする
  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Novelsテーブルに小説が存在しない場合のみ最小限のレコードを挿入する。
  ///
  /// LibraryEntriesはNovelsへの外部キーを持つため、
  /// addToLibraryの前にこのメソッドを呼ぶ必要がある。
  Future<void> ensureNovelExists(NovelSource source, String workId) {
    return into(novels).insert(
      NovelsCompanion(source: Value(source), workId: Value(workId)),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// ライブラリに小説を追加
  Future<int> addToLibrary(NovelSource source, String workId) {
    return into(libraryEntries).insert(
      LibraryEntriesCompanion(
        source: Value(source),
        workId: Value(workId),
        addedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// ライブラリから小説を削除
  Future<int> removeFromLibrary(NovelSource source, String workId) {
    return (delete(
          libraryEntries,
        )..where((t) => t.source.equalsValue(source) & t.workId.equals(workId)))
        .go();
  }

  /// ライブラリの小説リストを取得（追加日時の降順）
  Future<List<Novel>> getLibraryNovels() async {
    final query = select(libraryEntries).join([
      innerJoin(
        novels,
        novels.source.equalsExp(libraryEntries.source) &
            novels.workId.equalsExp(libraryEntries.workId),
      ),
    ])..orderBy([OrderingTerm.desc(libraryEntries.addedAt)]);

    final results = await query.get();
    return results.map((row) => row.readTable(novels)).toList();
  }

  /// ライブラリの小説リストを監視（JOIN）
  ///
  /// 追加日時（[LibraryNovelEntry.addedAt]）・アプリ内の最終閲覧日時
  /// （[LibraryNovelEntry.lastViewedAt]）でのソートをアプリ側で行えるよう、
  /// [Novel]と併せて返す。閲覧履歴が無い小説は[LibraryNovelEntry.lastViewedAt]が
  /// `null`になる。
  Stream<List<LibraryNovelEntry>> watchLibraryNovels() {
    final query = select(libraryEntries).join([
      innerJoin(
        novels,
        novels.source.equalsExp(libraryEntries.source) &
            novels.workId.equalsExp(libraryEntries.workId),
      ),
      leftOuterJoin(
        readingHistory,
        readingHistory.source.equalsExp(libraryEntries.source) &
            readingHistory.workId.equalsExp(libraryEntries.workId),
      ),
    ])..orderBy([OrderingTerm.desc(libraryEntries.addedAt)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => LibraryNovelEntry(
              novel: row.readTable(novels),
              addedAt: row.readTable(libraryEntries).addedAt,
              lastViewedAt: row.readTableOrNull(readingHistory)?.viewedAt,
            ),
          )
          .toList(),
    );
  }

  /// 小説がライブラリに追加されているかを確認
  Future<bool> isInLibrary(NovelSource source, String workId) async {
    final result =
        await (select(libraryEntries)..where(
              (t) => t.source.equalsValue(source) & t.workId.equals(workId),
            ))
            .getSingleOrNull();
    return result != null;
  }

  /// ライブラリ登録状態の監視
  Stream<bool> watchIsInLibrary(NovelSource source, String workId) {
    return (select(
          libraryEntries,
        )..where((t) => t.source.equalsValue(source) & t.workId.equals(workId)))
        .watchSingleOrNull()
        .map((entry) => entry != null);
  }

  /// なろう本家へのブックマーク登録が完了したことを記録する。
  ///
  /// [useridFavncode]・[favToken]を指定した場合、しおり更新
  /// (`ichiupdateajax`)に必要な情報として併せて保存する。
  ///
  /// なろう本家との同期情報は[NarouSyncEntries]（専用テーブル）に保存し、
  /// [LibraryEntries]等の共通テーブルはなろう固有の情報で汚さない。
  /// 呼び出し元は[NovelSource.narou]の小説に対してのみ呼ぶこと。
  Future<void> markNarouBookmarkSynced(
    NovelSource source,
    String workId, {
    String? useridFavncode,
    String? favToken,
  }) async {
    await into(narouSyncEntries).insertOnConflictUpdate(
      NarouSyncEntriesCompanion(
        source: Value(source),
        workId: Value(workId),
        narouBookmarkSyncedAt: Value(DateTime.now().millisecondsSinceEpoch),
        narouUseridFavncode: useridFavncode != null
            ? Value(useridFavncode)
            : const Value.absent(),
        narouFavToken: favToken != null
            ? Value(favToken)
            : const Value.absent(),
      ),
    );
  }

  /// しおり更新(`ichiupdateajax`)に必要なトークン情報を取得する。
  ///
  /// [markNarouBookmarkSynced]で保存されていない場合はnullを返す。
  Future<NarouFavToken?> getNarouFavToken(
    NovelSource source,
    String workId,
  ) async {
    final result =
        await (select(narouSyncEntries)..where(
              (t) => t.source.equalsValue(source) & t.workId.equals(workId),
            ))
            .getSingleOrNull();
    final useridFavncode = result?.narouUseridFavncode;
    final token = result?.narouFavToken;
    if (useridFavncode == null || token == null) return null;
    return NarouFavToken(useridFavncode: useridFavncode, token: token);
  }

  /// なろう本家へのブックマーク登録が完了しているかを確認する。
  Future<bool> isNarouBookmarkSynced(NovelSource source, String workId) async {
    final result =
        await (select(narouSyncEntries)..where(
              (t) =>
                  t.source.equalsValue(source) &
                  t.workId.equals(workId) &
                  t.narouBookmarkSyncedAt.isNotNull(),
            ))
            .getSingleOrNull();
    return result != null;
  }

  /// なろう本家へのブックマーク解除が完了したことを記録する。
  ///
  /// 同期用の情報（トークン等）を削除し、未同期状態に戻す。
  Future<void> clearNarouBookmarkSynced(
    NovelSource source,
    String workId,
  ) async {
    await (delete(narouSyncEntries)..where(
          (t) => t.source.equalsValue(source) & t.workId.equals(workId),
        ))
        .go();
  }

  /// 小説情報の保存
  Future<int> insertNovel(NovelsCompanion novel) async {
    // 小説検索は SQL の LIKE 部分一致のため、FTS インデックス更新は不要
    final id = await into(novels).insert(
      novel,
      mode: InsertMode.insertOrReplace,
    );

    return id;
  }

  /// 小説の非公開フラグを更新する
  Future<int> updateNovelPrivateFlag(
    NovelSource source,
    String workId, {
    required bool isPrivate,
  }) {
    return (update(
          novels,
        )..where((t) => t.source.equalsValue(source) & t.workId.equals(workId)))
        .write(
          NovelsCompanion(
            isPrivate: Value(isPrivate),
          ),
        );
  }

  /// 小説の取得状態を確保する
  ///
  /// 指定したsource/workIdの行が存在しない場合はプレースホルダー行を挿入し、
  /// 存在する場合はcachedAtを更新する。
  /// [isPrivate]を指定した場合は非公開フラグも更新する。
  Future<void> ensureNovelFetchState(
    NovelSource source,
    String workId, {
    required int cachedAt,
    bool? isPrivate,
  }) async {
    final existing = await getNovel(source, workId);
    if (existing == null) {
      await insertNovel(
        NovelsCompanion(
          source: Value(source),
          workId: Value(workId),
          isPrivate: Value(isPrivate ?? false),
          cachedAt: Value(cachedAt),
        ),
      );
    } else {
      await (update(
            novels,
          )..where(
            (t) => t.source.equalsValue(source) & t.workId.equals(workId),
          ))
          .write(
            NovelsCompanion(
              isPrivate: isPrivate != null
                  ? Value(isPrivate)
                  : const Value.absent(),
              cachedAt: Value(cachedAt),
            ),
          );
    }
  }

  /// 指定範囲の目次データのうち、最も古い取得日時を返す
  ///
  /// 対象範囲に取得日時が未設定(fetched_at IS NULL)の行が含まれる場合は
  /// 期限切れとして扱えるようNULLを返す。
  Future<int?> getEpisodeListOldestFetchedAt(
    NovelSource source,
    String workId,
    int start,
    int end,
  ) async {
    final result = await customSelect(
      'SELECT '
      'CASE '
      'WHEN COUNT(*) = COUNT(fetched_at) THEN MIN(fetched_at) '
      'ELSE NULL '
      'END as oldest '
      'FROM episode_list_entries '
      'WHERE source = ? AND work_id = ? AND episode_id BETWEEN ? AND ?',
      variables: [
        Variable.withString(source.dbId),
        Variable.withString(workId),
        Variable.withInt(start),
        Variable.withInt(end),
      ],
      readsFrom: {episodeListEntries},
    ).getSingleOrNull();
    return result?.read<int?>('oldest');
  }

  /// 履歴の追加
  Future<int> addToHistory(ReadingHistoryCompanion history) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(readingHistory).insert(
      history.copyWith(
        viewedAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// カクヨムの閲覧履歴を保存し、既存の履歴画面用履歴へ反映する。
  Future<RemoteHistoryMergeResult> mergeKakuyomuReadingHistories(
    List<KakuyomuHistoryEntry> entries,
  ) async {
    var inserted = 0;
    var updated = 0;
    final syncedAt = DateTime.now().millisecondsSinceEpoch;

    for (final entry in entries) {
      final episodeId = entry.episodeId;
      if (episodeId == null || episodeId.isEmpty) continue;
      final existing = await customSelect(
        'SELECT last_read_at FROM remote_reading_histories '
        'WHERE source = ? AND work_id = ? AND episode_id = ?',
        variables: [
          Variable.withString(entry.source.dbId),
          Variable.withString(entry.workId),
          Variable.withString(episodeId),
        ],
      ).getSingleOrNull();
      final previous = existing?.read<int?>('last_read_at');
      final incoming = entry.lastReadAt?.millisecondsSinceEpoch;
      final isNewer =
          previous == null || (incoming != null && incoming > previous);

      await customStatement(
        'INSERT INTO remote_reading_histories '
        '(source, work_id, episode_id, last_read_at, synced_at, title, '
        'episode_title) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(source, work_id, episode_id) DO UPDATE SET '
        'last_read_at = CASE WHEN excluded.last_read_at IS NULL THEN '
        'remote_reading_histories.last_read_at WHEN '
        'remote_reading_histories.last_read_at IS NULL OR '
        'excluded.last_read_at > remote_reading_histories.last_read_at '
        'THEN excluded.last_read_at ELSE '
        'remote_reading_histories.last_read_at END, '
        'synced_at = excluded.synced_at, '
        'title = COALESCE(excluded.title, remote_reading_histories.title), '
        'episode_title = COALESCE(excluded.episode_title, '
        'remote_reading_histories.episode_title)',
        [
          entry.source.dbId,
          entry.workId,
          episodeId,
          incoming,
          syncedAt,
          entry.title,
          entry.episodeTitle,
        ],
      );
      if (existing == null) {
        inserted++;
      } else if (isNewer) {
        updated++;
      }

      if (incoming == null) continue;
      final episodes = await getEpisodes(entry.source, entry.workId);
      final localEpisode = episodes.where((episode) {
        final url = episode.url;
        return url != null &&
            extractKakuyomuEpisodeId(workId: entry.workId, url: url) ==
                episodeId;
      }).firstOrNull;
      final localEpisodeId = localEpisode?.index;
      if (localEpisodeId == null || localEpisodeId < 1) continue;
      final local = await customSelect(
        'SELECT viewed_at FROM reading_history '
        'WHERE source = ? AND work_id = ?',
        variables: [
          Variable.withString(entry.source.dbId),
          Variable.withString(entry.workId),
        ],
      ).getSingleOrNull();
      final localViewedAt = local?.read<int>('viewed_at');
      if (localViewedAt != null && localViewedAt >= incoming) continue;
      await customUpdate(
        'INSERT INTO reading_history '
        '(source, work_id, last_episode_id, viewed_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?) ON CONFLICT(source, work_id) DO UPDATE SET '
        'last_episode_id = excluded.last_episode_id, '
        'viewed_at = excluded.viewed_at, '
        'updated_at = excluded.updated_at',
        variables: [
          Variable.withString(entry.source.dbId),
          Variable.withString(entry.workId),
          Variable.withInt(localEpisodeId),
          Variable.withInt(incoming),
          Variable.withInt(syncedAt),
        ],
        updates: {readingHistory},
      );
    }
    return RemoteHistoryMergeResult(inserted: inserted, updated: updated);
  }

  /// 履歴の取得（JOIN）
  Future<List<HistoryData>> getHistory() async {
    final query = select(readingHistory).join([
      innerJoin(
        novels,
        novels.source.equalsExp(readingHistory.source) &
            novels.workId.equalsExp(readingHistory.workId),
      ),
    ])..orderBy([OrderingTerm.desc(readingHistory.viewedAt)]);

    final results = await query.get();

    return results.map((row) {
      final novel = row.readTable(novels);
      final history = row.readTable(readingHistory);

      return HistoryData(
        source: novel.source,
        workId: novel.workId,
        title: novel.title,
        writer: novel.writer,
        lastEpisode: history.lastEpisodeId,
        viewedAt: history.viewedAt,
        updatedAt: history.updatedAt,
      );
    }).toList();
  }

  /// 履歴の監視（JOIN）
  Stream<List<HistoryData>> watchHistory() {
    final query = select(readingHistory).join([
      innerJoin(
        novels,
        novels.source.equalsExp(readingHistory.source) &
            novels.workId.equalsExp(readingHistory.workId),
      ),
    ])..orderBy([OrderingTerm.desc(readingHistory.viewedAt)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final novel = row.readTable(novels);
        final history = row.readTable(readingHistory);
        return HistoryData(
          source: novel.source,
          workId: novel.workId,
          title: novel.title,
          writer: novel.writer,
          lastEpisode: history.lastEpisodeId,
          viewedAt: history.viewedAt,
          updatedAt: history.updatedAt,
        );
      }).toList();
    });
  }

  /// 履歴の削除
  Future<int> deleteHistory(NovelSource source, String workId) {
    return (delete(
          readingHistory,
        )..where((t) => t.source.equalsValue(source) & t.workId.equals(workId)))
        .go();
  }

  /// 履歴の全削除
  Future<int> clearHistory() {
    return delete(readingHistory).go();
  }

  /// 特定小説の読書履歴を1件取得する。
  Future<ReadingHistoryData?> getReadingHistoryEntry(
    NovelSource source,
    String workId,
  ) {
    return (select(readingHistory)..where(
          (t) => t.source.equalsValue(source) & t.workId.equals(workId),
        ))
        .getSingleOrNull();
  }

  /// エピソード情報（目次）の保存
  Future<void> upsertEpisodes(
    List<EpisodeListEntriesCompanion> newEpisodes,
  ) async {
    if (newEpisodes.isEmpty) return;

    // 目次の取得日時
    final now = DateTime.now().millisecondsSinceEpoch;

    await batch((batch) {
      for (final episode in newEpisodes) {
        batch.customStatement(
          '''
          INSERT INTO episode_list_entries
            (source, work_id, episode_id, subtitle, url, published_at,
             revised_at, fetched_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(source, work_id, episode_id) DO UPDATE SET
            subtitle =
              COALESCE(excluded.subtitle, episode_list_entries.subtitle),
            url = COALESCE(excluded.url, episode_list_entries.url),
            published_at = COALESCE(
              excluded.published_at,
              episode_list_entries.published_at
            ),
            revised_at =
              COALESCE(excluded.revised_at, episode_list_entries.revised_at),
            fetched_at = excluded.fetched_at;
          ''',
          [
            episode.source.value.dbId,
            episode.workId.value,
            episode.episodeId.value,
            _presentValueOrNull(episode.subtitle),
            _presentValueOrNull(episode.url),
            _presentValueOrNull(episode.publishedAt),
            _presentValueOrNull(episode.revisedAt),
            now,
          ],
          // Batch.customStatement の updates は既定が空で、指定しないと
          // watchEpisodesRange などのストリームへ更新が通知されない
          [TableUpdate.onTable(episodeListEntries)],
        );
      }
    });
    markTablesUpdated({episodeListEntries});
  }

  /// エピソード本文の保存
  Future<void> updateEpisodeContent({
    required NovelSource source,
    required String workId,
    required int episodeId,
    required List<NovelContentElement> content,
    required int fetchedAt,
    String? revisedAt,
    String? subtitle,
    String? url,
    String? publishedAt,
  }) async {
    // メタデータが指定されている場合は目次テーブルも更新する
    // 指定されなかった項目は既存の値を保持する
    await customUpdate(
      '''
      INSERT INTO episode_list_entries
        (source, work_id, episode_id, subtitle, url, published_at, revised_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source, work_id, episode_id) DO UPDATE SET
        subtitle = COALESCE(excluded.subtitle, episode_list_entries.subtitle),
        url = COALESCE(excluded.url, episode_list_entries.url),
        published_at =
          COALESCE(excluded.published_at, episode_list_entries.published_at),
        revised_at =
          COALESCE(excluded.revised_at, episode_list_entries.revised_at);
    ''',
      variables: [
        Variable.withString(source.dbId),
        Variable.withString(workId),
        Variable.withInt(episodeId),
        Variable(subtitle),
        Variable(url),
        Variable(publishedAt),
        Variable(revisedAt),
      ],
      updates: {episodeListEntries},
    );

    // 本文テーブルを更新する
    await into(episodeContents).insertOnConflictUpdate(
      EpisodeContentsCompanion(
        source: Value(source),
        workId: Value(workId),
        episodeId: Value(episodeId),
        content: Value(content),
        fetchedAt: Value(fetchedAt),
        revisedAt: revisedAt != null ? Value(revisedAt) : const Value.absent(),
      ),
    );
  }

  // ...

  /// 特定エピソードのデータ（目次 + 本文）を取得
  Future<EpisodeData?> getEpisodeData(
    NovelSource source,
    String workId,
    int episodeId,
  ) {
    return _episodeDataSelect(source, workId, episodeId).getSingleOrNull();
  }

  /// 特定エピソードのデータ（目次 + 本文）を監視
  Stream<EpisodeData?> watchEpisodeData(
    NovelSource source,
    String workId,
    int episodeId,
  ) {
    return _episodeDataSelect(
      source,
      workId,
      episodeId,
    ).watchSingleOrNull();
  }

  /// 特定エピソードのデータ（目次 + 本文）を監視
  @Deprecated('watchEpisodeDataを使用してください')
  Stream<EpisodeData?> watchEpisodeEntity(
    NovelSource source,
    String workId,
    int episodeId,
  ) {
    return watchEpisodeData(source, workId, episodeId);
  }

  /// 目次と本文を結合したエピソードデータを取得するSELECT
  Selectable<EpisodeData> _episodeDataSelect(
    NovelSource source,
    String workId,
    int episodeId,
  ) {
    return customSelect(
      'SELECT l.source, l.work_id, l.episode_id, l.subtitle, l.url, '
      'l.published_at, '
      'COALESCE(c.revised_at, l.revised_at) AS revised_at, '
      'c.content AS content, c.fetched_at AS fetched_at '
      'FROM episode_list_entries l '
      'LEFT JOIN episode_contents c '
      'ON c.source = l.source AND c.work_id = l.work_id '
      'AND c.episode_id = l.episode_id '
      'WHERE l.source = ? AND l.work_id = ? AND l.episode_id = ?',
      variables: [
        Variable.withString(source.dbId),
        Variable.withString(workId),
        Variable.withInt(episodeId),
      ],
      readsFrom: {episodeListEntries, episodeContents},
    ).map((row) {
      final contentJson = row.read<String?>('content');
      return EpisodeData(
        source: NovelSource.values.byName(row.read<String>('source')),
        workId: row.read<String>('work_id'),
        episodeId: row.read<int>('episode_id'),
        subtitle: row.read<String?>('subtitle'),
        url: row.read<String?>('url'),
        publishedAt: row.read<String?>('published_at'),
        revisedAt: row.read<String?>('revised_at'),
        content: contentJson != null
            ? const ContentConverter().fromSql(contentJson)
            : null,
        fetchedAt: row.read<int?>('fetched_at'),
      );
    });
  }

  /// エピソード一覧を取得
  Future<List<Episode>> getEpisodes(NovelSource source, String workId) {
    return _episodeListSelect(source, workId).get();
  }

  /// 指定エピソードのURLを取得する。
  ///
  /// なろうはncodeからURLを組み立てられるが、カクヨムは
  /// グローバルなエピソードIDが必要なため、目次キャッシュから解決する。
  Future<String?> getEpisodeUrl(
    NovelSource source,
    String workId,
    int episodeId,
  ) async {
    final row =
        await (select(episodeListEntries)..where(
              (e) =>
                  e.source.equalsValue(source) &
                  e.workId.equals(workId) &
                  e.episodeId.equals(episodeId),
            ))
            .getSingleOrNull();
    return row?.url;
  }

  /// 指定範囲のエピソード一覧を取得 (Optimized)
  Future<List<Episode>> getEpisodesRange(
    NovelSource source,
    String workId,
    int start,
    int end,
  ) {
    return _episodeListSelect(
      source,
      workId,
      start: start,
      end: end,
    ).get();
  }

  /// 指定範囲のエピソード一覧を監視 (Optimized)
  Stream<List<Episode>> watchEpisodesRange(
    NovelSource source,
    String workId,
    int start,
    int end,
  ) {
    return _episodeListSelect(
      source,
      workId,
      start: start,
      end: end,
    ).watch();
  }

  /// 目次と本文を結合したエピソード一覧のSELECT
  Selectable<Episode> _episodeListSelect(
    NovelSource source,
    String workId, {
    int? start,
    int? end,
  }) {
    final hasRange = start != null && end != null;
    return customSelect(
      'SELECT '
      'l.source, l.work_id, l.episode_id, l.subtitle, l.url, l.published_at, '
      'l.revised_at, '
      // ignore: lines_longer_than_80_chars, reason: SQL リテラルのため
      "CASE WHEN c.content IS NOT NULL AND c.content NOT IN ('[]', '{\"txt\":\"\",\"rb\":[]}') "
      'THEN 1 ELSE 0 END as is_downloaded '
      'FROM episode_list_entries l '
      'LEFT JOIN episode_contents c '
      'ON c.source = l.source AND c.work_id = l.work_id '
      'AND c.episode_id = l.episode_id '
      'WHERE l.source = ? AND l.work_id = ? '
      '${hasRange ? 'AND l.episode_id BETWEEN ? AND ? ' : ''}'
      'ORDER BY l.episode_id',
      variables: [
        Variable.withString(source.dbId),
        Variable.withString(workId),
        if (hasRange) Variable.withInt(start),
        if (hasRange) Variable.withInt(end),
      ],
      readsFrom: {episodeListEntries, episodeContents},
    ).map(_mapEpisodeRow);
  }

  static Episode _mapEpisodeRow(QueryRow row) {
    final source = NovelSource.values.byName(row.read<String>('source'));
    final workId = row.read<String>('work_id');
    return Episode(
      source: source,
      // ncodeはなろうの作品ID。なろう以外ではnull
      ncode: source == NovelSource.narou ? workId : null,
      index: row.read<int>('episode_id'),
      subtitle: row.read<String?>('subtitle'),
      url: row.read<String?>('url'),
      update: row.read<String?>('published_at'),
      revised: row.read<String?>('revised_at'),
      isDownloaded: row.read<int>('is_downloaded') == 1,
    );
  }

  /// ダウンロード中の小説を監視
  Stream<List<NovelDownloadSummary>> watchDownloadingNovels() {
    return _watchDownloadSummaries(downloadStatus: 1);
  }

  /// 完了済みダウンロード小説を監視
  Stream<List<NovelDownloadSummary>> watchCompletedDownloads() {
    return _watchDownloadSummaries(downloadStatus: 2);
  }

  /// ダウンロード状態ごとの小説集計を監視する共通処理。
  ///
  /// 全エピソードの集計（GROUP BY）と、全ノベル情報を結合してストリーム化する。
  /// [downloadStatus] は [NovelDownloadSummary.downloadStatus] の値
  /// （1=ダウンロード中, 2=完了）。
  Stream<List<NovelDownloadSummary>> _watchDownloadSummaries({
    required int downloadStatus,
  }) {
    // GROUP BY source, work_id
    final query = customSelect(
      'SELECT '
      'e.source, e.work_id, '
      // ignore: lines_longer_than_80_chars, reason: SQL リテラルのため
      "COUNT(CASE WHEN e.content IS NOT NULL AND e.content NOT IN ('[]', '{\"txt\":\"\",\"rb\":[]}') "
      'THEN 1 END) as success_count, '
      // ignore: lines_longer_than_80_chars, reason: SQL リテラルのため
      "COUNT(CASE WHEN e.content IN ('[]', '{\"txt\":\"\",\"rb\":[]}') THEN 1 END) as failure_count, "
      'n.general_all_no '
      'FROM episode_contents e '
      'JOIN novels n ON e.source = n.source AND e.work_id = n.work_id '
      'WHERE e.content IS NOT NULL '
      'GROUP BY e.source, e.work_id',
      readsFrom: {episodeContents, novels},
    ).watch();

    return query.map((rows) {
      final summaries = <NovelDownloadSummary>[];
      for (final row in rows) {
        final workId = row.read<String>('work_id');
        final successCount = row.read<int>('success_count');
        final failureCount = row.read<int>('failure_count');
        final totalEpisodes = row.read<int?>('general_all_no');

        if (totalEpisodes == null) continue;

        final summary = NovelDownloadSummary(
          // P1時点ではなろうのみのため ncode = workId（カクヨム対応はP2）
          ncode: workId,
          successCount: successCount,
          failureCount: failureCount,
          totalEpisodes: totalEpisodes,
        );

        if (summary.downloadStatus == downloadStatus) {
          summaries.add(summary);
        }
      }
      return summaries;
    });
  }
}

T? _presentValueOrNull<T>(Value<T?> value) {
  return value.present ? value.value : null;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'novelty.db'));
    return NativeDatabase.createInBackground(file);
  });
}

// === Providers moved to database_providers.dart ===
