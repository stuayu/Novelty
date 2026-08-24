# マルチプロバイダ対応のアーキテクチャ（サイト抽象レイヤー）

Novelty が複数の小説提供サイト（プロバイダ）を扱うための設計を説明する。
実装は ADR-0001（複数プロバイダ抽象化）に基づく。

## 3層のマスタデータ

1. **`NovelSource` enum（身分）**: `dbId` / `label` / `baseUrl`
2. **サイト実装が提供するマスタデータ（コード定義）**: ジャンル（`GenreMaster`）・ランキング種別（`RankingTypeMaster`）
3. **レジストリ**: `Map<NovelSource, NovelSite>`

```
lib/sites/
├── novel_source.dart            # NovelSource enum
├── novel_site.dart              # NovelSite 抽象 + GenreMaster / RankingTypeMaster
├── novel_site_registry.dart     # Map<NovelSource, NovelSite>
├── narou/
│   └── narou_site.dart          # なろう（マスタデータのみ）
└── kakuyomu/
    └── kakuyomu_site.dart       # カクヨム（マスタデータ + 読書コア + 探索）
```

## NovelSite の責務

| カテゴリ | メソッド | 説明 |
|---|---|---|
| マスタデータ | `genres` / `rankingTypes` | ジャンル・ランキング種別の一覧 |
| 読書コア | `fetchNovelInfo(workId)` | 作品情報 |
| | `fetchToc(workId)` | 目次（エピソード一覧） |
| | `fetchEpisode(workId, index, {url})` | エピソード本文（`index` は目次順連番） |
| 探索 | `searchNovels(query)` | キーワード検索 |
| | `fetchRanking(rankingType, {page})` | ランキング |

未対応のメソッドは既定で `UnsupportedError` を投げる（レジストリ経由でサイトを取得する側が
`source` で分岐するため、実際には呼ばれない）。

## データフロー

### 読書（追加 → 目次 → 本文）

```
UI (NovelListTile / NovelDetailPage)
  └─ NovelRepository (source で分岐)
       ├─ narou   → ApiService (なろうAPI/HTML)
       └─ kakuyomu → KakuyomuSite (公開HTML)
  └─ DB: Novels / LibraryEntries / ReadingHistory / EpisodeListEntries / EpisodeContents
       (source, work_id[, episode_id]) 複合キー
```

- 本文キャッシュは `EpisodeContents.content`（`List<NovelContentElement>` のJSON）
- カクヨムのエピソードURL（19桁ID）は `EpisodeListEntries.url` に保存し、
  本文取得時にレポジトリがDBから解決してサイトへ渡す

### 探索（検索 / ランキング）

```
ExplorePage (source 切替)
  ├─ RankingNotifier(source, rankingType)
  │    ├─ narou   → ApiService.searchNovels (order パラメータ)
  │    └─ kakuyomu → KakuyomuSite.fetchRanking (HTML)
  └─ SearchState → source で分岐して検索
```

- フィルタ状態（`RankingFilterState` / `LibraryFilterState`）は `source` + `selectedGenreId: String?` を持つ
- ジャンル一覧はサイト実装の `genres` から取得（なろう: 大/小2階層、カクヨム: 単層）

## アクセス方針（カクヨム）

- **robots.txt 遵守**: `KakuyomuSite` がリクエスト前に禁止パス（`/read` ページ等）を検証して拒否
- **レート制限**: サイトごとに単一の `RequestRateLimiter`（`lib/utils/request_rate_limiter.dart`）を
  `siteRateLimiterProvider` で共有する。間隔はなろう250ms、カクヨム1秒、アルファポリス1秒。
  Future チェーンで直列化しており、並行呼び出しでも間隔が守られる
- **HTTPクライアント**: `createNoveltyDio()`（`lib/services/http_client.dart`）を共通で使う。
  タイムアウト（接続15秒・送受信30秒）、User-Agent、429/503 の指数バックオフを集約している
- **キャッシュファースト**: 本文は DB（`EpisodeContents`）にキャッシュし、差分（改稿日時）でのみ再取得

## パーサーパッケージ

| パッケージ | 対象 | 入力 |
|---|---|---|
| `novel_parser_core` | 共通モデル（`NovelContentElement`） | - |
| `narou_parser` | なろう本文 | `.p-novel__text` の innerHtml |
| `kakuyomu_parser` | カクヨム本文 | `widget-episodeBody` の innerHtml |
| `alphapolis_parser` | アルファポリス本文 | `POST /novel/episode_body` のレスポンス、または `#novelBody` を含むページ |

本文表示（`NovelContentView`）は `NovelContentElement` のみに依存するため、パーサーを追加しても表示層は無変更。

## ドキュメント

- HTML構造: [docs/kakuyomu_html/](../kakuyomu_html/) / [docs/narou_html/](../narou_html/)
- プロバイダ追加ガイド: [adding_a_provider.md](adding_a_provider.md)

## アルファポリス固有の注意点

- **複合ID**: 作品は `{authorId}/{workId}` の2要素で識別される。アプリ内では
  `{authorId}-{workId}` の単一文字列を `workId` として扱い、DBスキーマ・ルータ・
  `NovelSite` インターフェースは変更していない。分解と組み立ては
  `lib/utils/alphapolis_uri.dart` に閉じ込める
- **本文取得**: 本文は HTML に埋め込まれていない。エピソードページから CSRF トークンと
  32文字の `token` を抽出し、`POST /novel/episode_body` で取得する。
  仕様は実レスポンスで確認した内容を `docs/alphapolis_html/episode.md` に記録している
- **目次**: `script#app-cover-data` の JSON に全話が含まれる。341話の作品でも
  1レスポンスで取得でき、ページングは発生しない
- **取得できない話**: CSRF 不一致は 419、レンタル非公開は 403 を返す。
  いずれも `AlphapolisHttpException` として明確に失敗させる
