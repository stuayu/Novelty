# ランキング・作品一覧

確認URL: `https://www.alphapolis.co.jp/novel/index?category_ids=110400&sort=24hpt`

## sort

作品一覧HTMLの `sort-form` の `init-sort-list` で確認した全値:

| 値 | 意味 |
|---|---|
| `completed` | 最近完結した順 |
| `24hpt` | 24h.ポイント順 |
| `episode_recent` | 最近更新された順 |
| `weekly` | 週間ポイント順 |
| `monthly` | 月間ポイント順 |
| `yearly` | 年間ポイント順 |
| `total` | 累計ポイント順 |
| `favorite` | お気に入りの多い順 |
| `comment` | 感想の多い順 |
| `char` | 文字数の多い順 |
| `recent` | 新着順 |
| `episode_old` | 更新が古い順 |

## 一覧項目

実ページの構造は1作品ごとに `.p-content.is-novel`（別表示では `.section.novels.content-block`）で、代表セレクタは以下。

- 作品リンク・タイトル: `.p-content__title a` または `.content-title .title a`
- 著者: `.p-content__author-bookinfo a` または `.author a`
- あらすじ: `.p-content__abstract` / `.abstract .summary`
- 状態・カテゴリ: `.p-content__statuses .c-attribute-tag` / `.content-statuses .content-status`
- ポイント: `.p-content__meta .c-point--24h` / `.meta .point`
- タグ: `.p-content__tags .c-tag` または `.tags .tag`
- 文字数・更新日・登録日: `.p-content__other .wordcount`, `.updated`, `.created`

話数は一覧項目の安定した専用フィールドとして未確認。作品詳細の `chapterEpisodes` を使う設計にする。

## ページング・件数

- URL: `&page=2`。最終ページは `rel="last"`。例: ファンタジー全体53,716件、最終 `page=1343`
- 既定件数: 40件。HTMLのlimit選択肢は `40`, `80`, `120`
- `category_ids` は1ページのフォームに `category_ids[]` が複数存在するため複数指定を受け付けるUIは確認。ただし複数値をURLへ送った結果の意味（OR/AND）は未確認
