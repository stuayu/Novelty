# 検索

## URL・パラメータ

確認URL: `https://www.alphapolis.co.jp/search?query=異世界`

確認できたパラメータ:

| パラメータ | 用途 | 実例 |
|---|---|---|
| `query` | 検索語 | `異世界` |
| `category` | 検索対象 | `novel`, `official_manga`, `manga`, `prize`, `book` |
| `page` | ページ番号 | `2` |

検索結果ページ内の検索条件テンプレートで、以下も確認。実際のGET生成結果は未確認のため、実装仕様として断定しない。

`free_words`, `ng_free_words`, `episodes`, `complete`, `ratings`, `is_author_content`, `is_prize_winner`, `tag_ids[]`, `last_update`。

## 結果DOM

ランキングと同一ではない。検索結果は `.section.novels.content-block`。

- 作品: `.content-title .title a`
- 著者: `.author a`
- あらすじ: `.abstract .summary`
- ポイント: `.meta .point`
- タグ: `.meta.tag-blocks .tags .tag`
- 文字数: `.other .wordcount`
- 最終更新: `.other .updated`
- 登録日: `.other .created`
- 状態・種別: `.content-statuses .content-status`

検索結果は1ページ20件の実例。ページャーは `page=2`、最終 `page=3164`。全体63,271件に対して20件/ページの計算と一致する。

## ソート・絞り込み

検索URLでソートパラメータを指定した実例は未確認。検索モーダルのHTMLには文字数範囲、完結状態、R15/R18区分、更新時期、タグ、書籍化作家、受賞作品の条件が存在する。ただしGETキーと値の完全な対応は未確認。

小説だけに限定する場合は `category=novel` を付ける。漫画・絵本等は別カテゴリまたは別ドメインに分かれる。
