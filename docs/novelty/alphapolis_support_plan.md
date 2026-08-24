# アルファポリス対応 実装計画

作成日: 2026-08-24
関連: ADR-0001（複数プロバイダ対応のためのサイト抽象レイヤー）,
`docs/architecture/adding_a_provider.md`, `docs/novelty/existing_bugs_triage.md`,
`docs/novelty/alphapolis_investigation_brief.md`

---

## 背景

Novelty は現在「小説家になろう」「カクヨム」の2サイトに対応している。
ADR-0001 で導入したサイト抽象レイヤーにより、DBスキーマは全テーブルが
`(source, work_id[, episode_id])` 複合主キーへ移行済み（schemaVersion 22）、
ルータも `/novel/:source/:workId` となっており、ncode 前提は解消されている。

3つ目のサイトとしてアルファポリス（https://www.alphapolis.co.jp）に対応する。

## スコープ

**初期スコープに含むもの**

- 読書コア: 作品情報取得、目次取得、本文取得、オフラインダウンロード
- 探索: ランキング、キーワード検索
- ライブラリ登録、閲覧履歴（ローカル）

**初期スコープに含まないもの（次フェーズ）**

- アカウント連携（ログイン、お気に入り同期、読書位置のリモート同期）
- 検索モーダルのアルファポリス固有条件UI

アカウント同期を含めない理由は、`AccountSyncAdapter` に `isLoggedIn` / `login` / `logout` が
存在せず認証状態のサイト横断抽象が無いこと、`more_page.dart:110-120` がアカウントタイルを
手動列挙していることから、先に抽象化の整理が必要なためである
（`docs/novelty/existing_bugs_triage.md` の P2 を参照）。

## 前提条件

**Phase 0（P0地雷の除去）が完了していること。**

`lib/repositories/novel_repository.dart:394-402` の `_parseEpisodeBody` は
`else` が無条件でカクヨムパーサになっており、第3サイトの本文が静かに壊れる。
詳細と対策は `docs/novelty/existing_bugs_triage.md` の P0-1 を参照。

**Phase 1（調査）が完了していること。**

`docs/alphapolis_html/` と `docs/novelty/alphapolis_terms_review.md` が揃っていること。
利用規約のレビューで不適合が見つかった場合は、実装に着手せず flag すること。
詳細は `docs/novelty/alphapolis_investigation_brief.md` を参照。

---

## 設計上の決定

### 複合IDの表現

アルファポリスの作品は `{authorId}/{workId}` の2要素で識別される
（例: `/novel/480761512/519070183`）。既存2サイトは単一IDなので、この点だけが新しい。

**`workId` に区切り文字を埋め込んだ単一文字列として保持する。**

```
ルータ:  /novel/alphapolis/480761512-519070183
DB:      (source='alphapolis', work_id='480761512-519070183')
Site内:  final parts = key.split('-');
         url = 'https://www.alphapolis.co.jp/novel/${parts[0]}/${parts[1]}'
```

この方式を選ぶ理由:

- DBスキーマ、ルータ、`NovelSite` インターフェース、`lib/utils/work_url.dart` の
  いずれも変更が不要で、なろう・カクヨムへの回帰リスクがゼロ
- ルータのパスパラメータにスラッシュを含める問題を回避できる
- 分解・組み立てのロジックを `AlphapolisSite` と `lib/utils/alphapolis_uri.dart` に
  閉じ込められる（`lib/utils/kakuyomu_uri.dart` が先例）

区切り文字は、実際のIDに含まれない文字を Phase 1 の調査結果に基づいて選ぶこと。
IDが数値のみであれば `-` でよい。

### `NovelInfo` のセマンティクス

`NovelInfo` の `end` / `novelType` は**なろうのセマンティクスがそのまま共通型の意味論**に
なっている。`KakuyomuSite._workToNovelInfo`（`kakuyomu_site.dart:300-341`）が
`'RUNNING' => 1, 'COMPLETED' => 0` と変換している。アルファポリスも同じ規約に合わせること。

`ncode` フィールドは「なろう以外は null」という規約（`lib/models/novel_info.dart:57`）。
`workId` が共通IDである。

### `NovelSearchQuery`

`NovelSearchQuery` はほぼなろうAPIのGETパラメータそのもの（50超フィールド）で、
カクヨム用に `serialStatus` / `totalCharacterCountRange` が後付けされている。
**初期スコープでは共通項目（`word` / `st` / ジャンル）のみを使う。**
アルファポリス固有条件を足したくなった場合は、この共通型を膨らませる前に相談すること。

### パース失敗時の方針

**セレクタが一致しなかった場合、空を返さず `FormatException` を投げること。**

現行の実装では `KakuyomuSite._parseRanking`（`kakuyomu_site.dart:322-325`）だけが
この方針を採っており、他のパーサはすべて「静かに空を返す」。
これが `docs/novelty/existing_bugs_triage.md` の H-5（パース失敗が「ダウンロード成功」として
記録される）の温床になっている。新規パーサは最初から正しい方に倒す。

---

## Phase 2: `packages/alphapolis_parser` の実装

`packages/kakuyomu_parser/` を雛形にする。

1. `packages/alphapolis_parser/` を作成し、`novel_parser_core` に依存させる
2. `parseAlphapolisEpisodeBody(String html) -> List<NovelContentElement>` を実装
3. ルート `pubspec.yaml` の `workspace:`（`:21-25`）と `dependencies:` に追加
4. Phase 1 で採取した実HTMLを `test/fixtures/alphapolis/` に置いて単体テスト

ルビの扱いは `packages/novel_parser_core/lib/src/models/hybrid_converter.dart` の
Hybrid JSON 形式（`{"txt":..., "rb":[{"off","base","ruby"}]}`、ADR-0002）に載る形にすること。
整合性は `txt.substring(off, off + base.length) == base` で検証される。

## Phase 3: `AlphapolisSite` の実装

1. `lib/sites/novel_source.dart` に enum を追加

   ```dart
   alphapolis('alphapolis', 'アルファポリス', 'https://www.alphapolis.co.jp'),
   ```

   `dbId` は enum 名と同一にすること（`NovelSourceConverter.fromSql` が
   `NovelSource.values.byName()` を使っている。`database.dart:30`）。

2. `lib/utils/alphapolis_uri.dart` — 複合IDの分解・組み立て・URL生成。
   `lib/utils/kakuyomu_uri.dart` が先例。

3. `lib/sites/alphapolis/alphapolis_site.dart` — `implements NovelSite`。
   `KakuyomuSite`（`kakuyomu_site.dart:69-484`）を構造の手本にする。

   実装するメンバ:

   | メンバ | 内容 |
   |---|---|
   | `source` | `NovelSource.alphapolis` |
   | `genres` | Phase 1 で採取した `category_ids` の一覧を `GenreMaster` で表現。2階層なら `bigGenreId` / `isBigGenre` を使う |
   | `rankingTypes` | `sort` パラメータの一覧を `RankingTypeMaster` で表現 |
   | `metaText` | リスト表示用のサイト固有情報サフィックス（なろうは「1.2k pt」、カクヨムは「★1,234」） |
   | `parseEpisodeBody` | Phase 2 の `parseAlphapolisEpisodeBody` へ委譲（Phase 0 で追加される抽象メソッド） |
   | `fetchNovelInfo` / `fetchToc` / `fetchEpisode` | 読書コア |
   | `searchNovels` / `fetchRanking` | 探索 |

   アクセス方針:
   - robots.txt 検証（`KakuyomuSite._assertAllowed`, `:257-263` が手本）
   - レートリミッタ経由でのHTTP。**H-1 の修正で共通化されたレートリミッタを使うこと。**
     まだ共通化されていなければ `KakuyomuRateLimiter` と同型のものを作り、
     ミューテックスによる直列化を最初から入れる
   - Dio は C-1 で導入する共通ファクトリ（タイムアウト + 統一User-Agent）を使う。
     まだ無ければ素の `Dio()` は使わず、`BaseOptions` でタイムアウトを明示すること

4. `lib/utils/work_url.dart:13-18` の `switch` に case を追加。
   exhaustive switch なのでコンパイラが漏れを検出する。

5. `lib/sites/novel_site_registry.dart:12-16` に登録

   ```dart
   NovelSource.alphapolis: AlphapolisSite(),
   ```

6. テスト: `test/sites/alphapolis/alphapolis_site_test.dart`。
   フィクスチャ + モックHTTP（Dioアダプタ）。
   `test/sites/kakuyomu/kakuyomu_site_test.dart`（493行）が手本。

## Phase 4: UI 対応

`docs/architecture/adding_a_provider.md:57-62` の指針に従う。

**変更が必要なもの**

- `lib/widgets/sort_selection_sheet.dart:58-59` — `ncodeasc` / `ncodedesc`（Nコード昇順・降順）が
  サイト分岐なしで常時表示されている。なろう限定表示に絞る
- `lib/screens/library_page.dart:191` — source が null（「すべて」）のとき
  `NovelSource.narou` のジャンルへフォールバックしている。修正する
- `lib/models/novel_download_summary.dart` — `source` フィールドを追加し、
  `database.dart:2022-2024` と `download_manager_page.dart:142,156,251` の
  `NovelSource.narou` ハードコードを除去する。
  SQL 自体は `GROUP BY e.source, e.work_id` と正しく集計しているので、モデルとUIのみの修正で済む。
  **これを怠るとアルファポリス作品のダウンロードが管理画面で誤表示される**

**変更が不要なもの**（`NovelSource.values` とレジストリ駆動で自動対応）

- `lib/screens/explore_page.dart:40,114,170` — ランキングタブとソース切替
- `lib/screens/library_page.dart:224` — ソース絞り込み
- `lib/widgets/source_selector.dart`, `lib/widgets/app_bar_source_dropdown.dart`
- `lib/widgets/novel_list_tile.dart:54,80`
- `lib/widgets/ranking_filter_sheet.dart`, `lib/widgets/library_filter_sheet.dart`
- `lib/router/router.dart:233,255,286`
- DBスキーマ全般（マイグレーション不要）

**触らないもの**

- `lib/widgets/search_modal.dart` — なろう固有条件は `if (source == narou)` ブロック内（`:120`）、
  カクヨム固有条件は `:328` にあり、アルファポリスは共通条件のみで安全側に倒れる。
  固有条件UIは初期スコープでは追加しない

## Phase 5: ドキュメント

- `CONTEXT.md:8-20` の `NovelSource` 表にアルファポリスの行を追加
- `docs/architecture/multi_provider.md` のパーサーパッケージ表を更新
- `README.md` の対応サイト記述を更新
- ADR-0001 に追記するか新規ADRを立てるかは、複合IDの扱いが既存の決定を変えるものかで判断する
  （変えないので追記で足りるはず）

---

## 開発規約

`AGENTS.md:43-48` に従うこと。

- 作業計画を先に立て、承認されるまで実装を開始しない
- t_wada の TDD サイクルに従い、テストを先に書く
- 各フェーズ完了時に lint 0件（`info` 分類のものも含む）を確認する
- コミットメッセージは日本語で書く
- ユーザーへの応答、実装計画、ウォークスルーはすべて日本語で行う
- コードコメントは日本語で書く
- `CONTEXT.md` の用語（`NovelSource` / `workId` / `episodeIndex` / `Hybrid`）を使う
- ADR と矛盾する判断が必要になった場合は、実装せず flag する

## 検証

```bash
mise run test      # flutter test — 全緑
mise run analyze   # flutter analyze — 0件（info含む）
mise run check     # dart analyze && dart format --dry-run .
mise run codegen   # NovelSource に enum を追加したら必ず実行する
```

`NovelSource` に enum を追加すると `novel_site_registry.g.dart` 等の生成物が変わるため、
`mise run codegen` の実行を忘れないこと。

### 手動確認

- 探索画面でアルファポリスに切り替え → ランキング表示 → 作品を開く → 目次 → 本文
- ライブラリ登録 → 履歴に残る → 全話ダウンロード →
  ダウンロード管理画面に**アルファポリス作品として**表示される
- 機内モードでダウンロード済みエピソードが読める
- 縦書き表示でルビが正しくレンダリングされる

### 回帰確認（必須）

なろう・カクヨムの以下がすべて従来どおり動作すること。

- 探索（ランキング・検索）
- 作品詳細・目次・本文
- ダウンロードとオフライン読書
- アカウント同期（ログイン、ブックマーク/フォロー同期、読書位置同期）
