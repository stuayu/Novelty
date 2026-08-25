# ランキング

確認URL: `https://estar.jp/novels/ranking?ranking_type=all&ranking_axis_type=general_popular`

## 種別とURL

実ページのタブ・リンクで確認できたランキング種別は次の5件。`RankingTypeMaster.urlPath`には確認済みの入口URLを設定できる。`type=pickup`はランキング種別ではなく、新着・完結ページの抽出指定。

実HTMLのタブとリンクで確認した種別:

|`ranking_type`|表示/意味|`ranking_axis_type`|
|---|---|---|
|`all`|総合|`general_popular`（人気）、`general`（トレンド）|
|`kiriban`|スター|`general_popular`|
|`new_arrivals`|新着|`general_popular`、`type=pickup`|
|`finished`|完結|`general_popular`、`type=pickup`|
|`trend`|トレンド|`general`、`general_popular`|

| id | label | urlPath |
|---|---|---|
| `all` | 総合 | `/novels/ranking?ranking_type=all&ranking_axis_type=general_popular` |
| `kiriban` | スター | `/novels/kiriban?ranking_type=all&ranking_axis_type=general_popular` |
| `new_arrivals` | 新着 | `/novels/new_arrivals?ranking_type=all&ranking_axis_type=general_popular&type=pickup` |
| `finished` | 完結 | `/novels/finished?ranking_type=all&ranking_axis_type=general_popular&type=pickup` |
| `trend` | トレンド | `/novels/trend?ranking_type=all&ranking_axis_type=general` |

実レスポンスのリンクでは、`kiriban`・`new_arrivals`・`finished`の3件も`ranking_type=all`を送っていた。上表は実際に取得したリンクの`ranking_type`を保持している。別の`ranking_type`値へ置換したURLの全件は未取得。

期間表示は`daily`（日間）、`weekly`（週間）、`monthly`（月間）、`total`（累計）をSSR HTML内で確認。期間をURLクエリで指定する全組み合わせは未取得。

## SSR JSONの構造

ランキングページの`script#__NUXT_DATA__`は、通常のオブジェクトではなくNuxtの参照配列。`data.novels_ranking.novels.nodes`相当の配列から`ModelNovel`への参照をたどると、次のフィールドを確認できる。

|用途|フィールド|
|---|---|
|作品|`workId`（文字列化された数字）、`title`|
|著者|`user.nickname`|
|あらすじ|`description`|
|ジャンル|`genre.genreId`、`genre.name`|
|タグ|`tags[].name`|
|話数・文字数|`episodeCount`、`bodyCount`|
|評価・順位|`starNum`、`metrics.star`、`rank`|
|更新|`bodyUpdatedAt`|
|次ページ|ランキングの`pageInfo.hasNextPage`|

実測1位作品では、作品ID`26544596`、タイトル、著者`春野カノン🌻コミカライズ配信中`、ジャンル`1020/恋愛`、タグ11件、`rank=1`を取得。`starNum`と`metrics.star`は取得できるが、対象作品の値は0だった。スター数を表示用評価指標として採用する正確な意味は未確認。

作品リンクはSSR JSONの`workId`から`/novels/{workId}`として構成できる。ランキング1ページは15件、`hasNextPage=true`。`?page=2`でもHTTP 200の別ページを取得でき、ページング形式は`page`クエリ。

ランキング作品はSSRの`ModelNovel`。作品ID、タイトル、著者、ジャンル、画像、文字数、更新日時、スター関連フィールドを持つ。全種別・全期間のURL組み合わせ、ランキングスコアの意味、スター数の表示形式は未確認。
