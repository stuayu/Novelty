# アルファポリス対応 調査指示書（実装前フェーズ）

作成日: 2026-08-24
担当: 調査エージェント（read-only）
関連: `docs/novelty/alphapolis_support_plan.md`, `docs/architecture/adding_a_provider.md`, ADR-0001

---

## 目的

Novelty に3つ目の小説サイトとしてアルファポリス（https://www.alphapolis.co.jp）を追加する。
本フェーズでは**コードを一切変更せず**、実装に必要な事実を収集してドキュメントに記録する。

先例として `docs/kakuyomu_html/` と `docs/novelty/kakuyomu_terms_review.md` が既にある。
出力の形式はこれらに揃えること。

## 絶対条件

`docs/novelty/native_account_sync_review.md:18-25` の方針を継承する。

- **推測でHTML構造やAPI仕様を書かないこと。** 実際に取得したHTMLに基づく事実のみを記録する。
  確認できなかった項目は「未確認」と明記する
- Headless Browser / WebView を使わないこと。`curl` 等の素のHTTP取得で確認する
- robots.txt を遵守すること。取得は最小限にとどめ、1秒以上の間隔を空けること
- 本フェーズでは `lib/` 配下および `packages/` 配下を一切変更しないこと

## 事前に判明している事実

以下は確認済みなので再調査は不要。裏取りだけしてよい。

- **robots.txt**: `Disallow: /dreambookclub/`（`Allow: /dreambookclub/image/`）のみ。
  小説領域は全許可。`Crawl-delay` は bingbot 向けのみ。Googlebot 向けに
  `Disallow: /search?*page=*` と `Disallow: /novel/*?*page=*` があるが、
  これは同社のDBスロークエリ対策であり `User-agent: *` には適用されない
- **作品ページURL**: `https://www.alphapolis.co.jp/novel/{authorId}/{workId}`
  （例: `/novel/480761512/519070183`）
- **一覧・ランキングURL**: `https://www.alphapolis.co.jp/novel/index?category_ids={id}&sort={key}`
- **判明しているカテゴリID**: 110400=ファンタジー, 110500=恋愛, 110600=青春,
  111400=キャラ文芸, 111500=ライトノベル, 119000=BL
- **著者ページURL**: `https://www.alphapolis.co.jp/author/detail/{authorId}`
- **公式APIは存在しない**。サーバサイドレンダリングされたHTMLで、
  `__NEXT_DATA__` や JSON-LD のような構造化データは見当たらない
  → カクヨムと同じくCSSセレクタベースのパーサが必要

## 調査項目

### 1. 作品詳細ページの DOM 構造

`https://www.alphapolis.co.jp/novel/{authorId}/{workId}` について、以下の各要素の
**CSSセレクタと実際の値**を記録する。

- 作品タイトル
- 著者名、著者ページへのリンク
- あらすじ（本文と、折りたたみの有無）
- タグ / ジャンル
- 総話数
- 総文字数
- 初回投稿日時、最終更新日時（フォーマットも記録すること）
- 完結 / 連載中の判別方法
- ポイント・お気に入り数などの評価指標（`NovelSite.metaText` の実装に使う）
- カバー画像URL（存在する場合）

**注意**: 短編作品（1話完結）と連載作品でDOM構造が異なる可能性がある。両方確認すること。

### 2. 目次の DOM 構造

- 目次が作品詳細ページ内にあるのか、別URLなのか
- 各話リンクの href 形式（絶対 / 相対、話数IDの形式）
- 各話のサブタイトル、投稿日時、文字数のセレクタ
- 章（`chapter`）構造の有無とその表現
- **話数が多い作品（100話以上）でページングが発生するか**。
  発生する場合はそのURL形式と、全件取得の方法
- 各話のURLからエピソードを一意に特定できるか
  （`lib/utils/kakuyomu_uri.dart` の `extractKakuyomuEpisodeId` に相当するものが作れるか）

### 3. 本文ページの DOM 構造

- 本文コンテナのセレクタ
- エピソードタイトルのセレクタ
- **ルビの記法**（`<ruby>` タグか、`|漢字《かんじ》` のような記法か、独自クラスか）
- 傍点の表現
- 挿絵・画像の表現
- 改ページ / 区切り線の表現
- 空行の扱い（`<br>` の連続か、空の `<p>` か）
- 前後の話へのナビゲーションリンク
- 改稿日時の表示有無（キャッシュの鮮度判定に使う）

`packages/novel_parser_core` の `NovelContentElement` にどうマッピングするかの
方針まで書くこと。既存の `packages/kakuyomu_parser/lib/src/parser.dart` が参考になる。

### 4. ランキングページ

- `sort` パラメータの取り得る値の**完全な一覧**とその意味
  （判明しているのは `24hpt`、`completed`）
- ランキング一覧の各項目のDOM構造（作品へのリンク、タイトル、著者、あらすじ抜粋、
  ポイント、タグ、話数など）
- ページングのURL形式と、1ページあたりの件数
- ジャンル別ランキングの指定方法（`category_ids` の複数指定は可能か）

### 5. 検索

- 検索ページのURLとクエリパラメータの一覧
- 検索結果のDOM構造（ランキングと同一か）
- ソート順の指定方法
- 絞り込み条件（文字数、完結状態など）の指定方法

### 6. カテゴリ（ジャンル）の完全な一覧

`category_ids` の値と名称の対応表を全件。
大ジャンル / 小ジャンルの2階層構造になっているかも確認すること
（`GenreMaster` は `bigGenreId` / `isBigGenre` で2階層を表現できる）。

小説以外のカテゴリ（漫画、絵本など）が同じ体系に含まれる場合は、
小説のみを対象とするための絞り込み方法も記録すること。

### 7. 利用規約のレビュー

**利用規約の正しいURLがまだ特定できていない**（`/terms` と `/help/terms` はいずれも404）。
まずURLを特定すること。

特定後、以下の観点で条項番号付きに原文を引用して評価する。
形式は `docs/novelty/kakuyomu_terms_review.md` に揃える。

- 自動化されたアクセス、クローラー、スクレイピング、ロボットの禁止条項の有無
- コンテンツの複製・転載・ローカル保存の禁止条項の有無
- 非公式クライアントアプリケーションの扱い
- 禁止行為の条項全般

各条項について「適合 / 要注意 / 不適合」を判定し、不適合があれば
**実装に着手する前に flag すること**。

## 成果物

1. `docs/alphapolis_html/` 配下に、上記1〜6のDOM構造をまとめたMarkdown。
   `docs/kakuyomu_html/` の構成に揃える。
   実HTMLのサンプルも `test/fixtures/alphapolis/` に配置する
   （短編1件、連載1件、目次、本文、ランキング1ページ、検索結果1ページ）
2. `docs/novelty/alphapolis_terms_review.md` — 利用規約の逐条レビュー
3. 実装上の懸念事項リスト。特に以下について明確な結論を出すこと:
   - 話数の多い作品の目次全件取得が現実的なリクエスト数で可能か
   - ルビの記法が `NovelContentElement` と `packages/tategaki` の縦書きレンダリングで
     正しく扱えるか
   - ログインなしで本文が読めない作品（有料・R18等）の存在と、その判別方法

## 検証

コードを変更しないため通常のテストは不要だが、以下を守ること。

- 記録したセレクタは、実際に採取したHTMLフィクスチャに対して
  `package:html` のパーサで一致することを確認してから書くこと
- 「未確認」と「確認済み」を明確に区別すること
