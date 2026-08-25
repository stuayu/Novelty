# 検索

確認URL: `https://estar.jp/novels?keyword=%E6%81%8B%E6%84%9B`

## URL・クエリ

検索語は`keyword`。同じ検索結果ページのJSON-LD canonical相当リンクから、次のGETパラメータ名を実測した。

|パラメータ|実測値|
|---|---|
|`keyword`|`恋愛`|
|`sort`|`score_desc`|
|`writing`|`0`|
|`finished`|`0`|
|`tag_only`|`0`|
|`ex_r18`|`0`|
|`ex_paused`|`0`|
|`ex_ticket`|`0`|
|`is_book_p`|`0`|
|`awarded`|`0`|
|`in_selection`|`0`|
|`published`|空値|

`page=2`を追加したURLもHTTP 200で取得できた。検索SSRの`perPageCount=30`、`novels.totalCount=795`、`pageInfo.hasNextPage=true`を確認。1ページ目は30件。ページング形式は`page`クエリ。

`keyword`が検索語。実HTMLはタイトル「【恋愛】おすすめの小説を無料で読む｜作品一覧」を返し、SSRの`ModelNovel`に作品ID群を含む。作品リンク形式は`/novels/{workId}`。タグリンクは`/novels?keyword=%23{タグ}`。

検索結果はSSR埋め込みJSON中心で、HTMLに作品本文は埋め込まれない。`ModelNovel`には`workId`、`title`、`description`、`catchphrase`、`user.nickname`、`genre.genreId/name`、`tags[].name`、`publishedBodyCount`、`bodyUpdatedAt`、`status`、`writingStatus`、`isRestricted`、`workPrice`などを確認。ランキングと同じ作品リンクを`/novels/{workId}`で構成できる。

ジャンル一覧はSSRの`genres`に`genreId`、`name`、`relatedTags`として含まれる。`genre=1020`と`genre_id=1020`を付けた公開GETでは検索結果の絞り込みを確認できず、ジャンル指定の正式なクエリ名・値は未確認。タグ検索は実レスポンスのリンクで`keyword=%23{タグ}`を確認。

実装時は`NovelSearchQuery.word`を`keyword`へ対応させ、検索結果の`workId`を文字列として保持する。確認済みの固定条件はクエリへ対応可能だが、UIの全フィルタ値とジャンル指定は追加確認が必要。
