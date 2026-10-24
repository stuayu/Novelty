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

## アクセス方針（外部サイト）

- **資格情報**: サイトログイン機能はなく、サイトへのリクエストにCookieや認証情報を送らない
- **なろうAPI**: HTTPSで接続し、`api.syosetu.com` と `ncode.syosetu.com` を別々に1秒間隔で制限する
- **カクヨム**: HTTPSの `kakuyomu.jp:443` のみ許可し、robots.txtの禁止パスを初回URL・目次URL・リダイレクト先で検査する
- **レート制限**: 同一ホストへの各リクエストは、開始時刻の間隔を1秒以上あける
- **タイムアウト**: APIとHTML取得に接続10秒、受信30秒を設定
- **エラー処理**: HTTP 403/429を自動再試行しない
- **キャッシュファースト**: 本文は DB（`EpisodeContents`）にキャッシュし、差分（改稿日時）でのみ再取得

2026-10-24に確認したカクヨムのrobots.txtでは `/shared_drafts/`、
`/works/*/episodes/*/read`、ログイン・通報・フィードバック関連のパスが禁止されている。
なろうAPI側のrobots.txtは `api.syosetu.com` と `ncode.syosetu.com` の両方に
`Crawl-delay: 1` を指定している。アプリのホスト別1秒間隔制限もこれに合わせている。

## パーサーパッケージ

| パッケージ | 対象 | 入力 |
|---|---|---|
| `novel_parser_core` | 共通モデル（`NovelContentElement`） | - |
| `narou_parser` | なろう本文 | `.p-novel__text` の innerHtml |
| `kakuyomu_parser` | カクヨム本文 | `widget-episodeBody` の innerHtml |

本文表示（`NovelContentView`）は `NovelContentElement` のみに依存するため、パーサーを追加しても表示層は無変更。

## ドキュメント

- HTML構造: [docs/kakuyomu_html/](../kakuyomu_html/) / [docs/narou_html/](../narou_html/)
- プロバイダ追加ガイド: [adding_a_provider.md](adding_a_provider.md)
