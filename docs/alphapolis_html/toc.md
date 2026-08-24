# 目次

目次は別URLではなく、作品詳細ページ内の `#ScrollUp.p-table-of-contents` に含まれる。目次タブのhrefは作品URL自身。

## データ構造

`script#app-cover-data` の `chapterEpisodes[]` を解析する。

| JSONキー | 意味 | 実値 |
|---|---|---|
| `chapterId` | 章ID。章なしは `null` | `11579378` / `null` |
| `title` | 章名 | `深夜の清掃員と、ありえない攻略記録` |
| `episodes[].episodeNo` | 話ID | `11502116` |
| `episodes[].url` | 話URL | `/novel/480761512/519070183/episode/11502116` |
| `mainTitle` | サブタイトル | `第1話「数字にならない男」` |
| `upTime` | 投稿日時 | `2026.07.12 07:20` |
| `counterText` | 文字数表示 | `3,442文字` |
| `isPublic` | 公開状態 | `true` |
| `dispOrder` | 表示順 | `2` |
| `likes` | 話への反応数 | `856` |

## 章

章あり。`chapterId` と `title` が設定され、同じ章の `episodes` が配列でまとまる。章なしは `chapterId: null`, `title: ""`, `episode.chapter: null`。

## ページング

採取した連載作品は多数話を1ページの `chapterEpisodes` に含む。100話以上の作品でページングが発生するか、`cover.json` 等の追加取得が必要かは未確認。実装では件数を検査し、欠落を成功扱いしないこと。

## エピソードID

URL末尾の数値 `/episode/{episodeNo}` が一意な話IDとして使える実例を確認。`episodeNo` と一致する。共通モデルの `episodeIndex` は `dispOrder` または目次走査順、サイト固有URLは `url` に保持する。
