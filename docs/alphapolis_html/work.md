# 作品詳細ページ

対象: `https://www.alphapolis.co.jp/novel/{authorId}/{workId}`

## DOM

| 項目 | セレクタ | 採取値・確認結果 |
|---|---|---|
| タイトル | `.p-content-info__title.is-novel` | 作品タイトル。短編・連載で同一 |
| 著者名 | `.p-content-info__author` | 短編: `キムラましゅろう`、連載: `さくらろ` |
| 著者URL | `.p-content-info__author[href]` | `/author/detail/{authorId}` の絶対URL |
| あらすじ | `.p-content-info__abstract` | 本文テキスト。`br`を含む。短編・連載で同一 |
| タグ | `.p-content-info__tags .c-tag a` | 例: `読み切り`, `現代ダンジョン` |
| 24時間ポイント | `.p-content-info__meta .c-point--24h` | `2,172pt`、`5,631pt` |
| お気に入り相当 | `.p-content-info__meta-heart` | `1,702`、`34,291`。サイドバーのJSONでは短編 `1,702` も確認 |
| カテゴリ | `.c-category-rank__name a.c-attribute-tag--novel` | 短編 `恋愛`、連載 `ファンタジー`。一般の `小説` も存在 |
| 初回公開 | `.p-sidebar-content-info__detail-label` が `初回公開日時` の親要素 | `2023.11.29 20:30`、`2026.07.12 07:20` |
| 更新日時 | 同上、ラベル `更新日時` | `2023.11.29 20:30`、連載ページ採取時 `2026.08.24 20:00` |
| 初回完結日時 | ラベル `初回完結日時` の親要素 | 短編で `2023.11.29 20:30`。連載では未確認 |
| 作品総文字数 | ラベル `文字数` の親要素 | 短編 `10,256`。連載ページの総文字数は未確認 |
| 完結状態 | `.content-status.complete` または `.c-attribute-tag` の表示文字列 | `完結` / `連載中`。fixtureの1話作品は `完結` |
| 作品種別 | `.content-status.volume` | `短編`、`ｼｮｰﾄｼｮｰﾄ`。1話完結作品で専用表示は未確認だが、目次件数1で判定可能 |
| 表紙画像 | `script#app-cover-data` JSONの `content.coverImageUrl` | 短編はCDN絶対URL、連載採取例は `null` |

あらすじに折りたたみ用の専用クラスは確認できず、詳細ページでは `.p-content-info__abstract` 内に全文が存在。検索・一覧では `.details.ReadMore > .summary`。

## `app-cover-data` JSON

CSSで値を取得するDOMではなく、`script#app-cover-data` のJSONを解析する。確認できた主なキー:

```json
{
  "content": {
    "id": 873826540,
    "url": "/novel/600144500/873826540",
    "coverImageUrl": "https://cdn-image.alphapolis.co.jp/...",
    "user": {"name": "キムラましゅろう"}
  },
  "chapterEpisodes": [
    {"chapterId": null, "title": "", "episodes": [
      {"episodeNo": 7782422, "url": "/novel/.../episode/7782422",
       "mainTitle": "あのひとのいちばん大切なひと",
       "upTime": "2023.11.29 20:30", "counterText": "10,256文字"}
    ]}
  ]
}
```

## 未確認

- 連載作品の総文字数を表示する専用項目の安定した位置
- 改稿日時と最終更新日時の意味の差
- ログイン必須・レンタル・R18作品で同じDOMが返るか
