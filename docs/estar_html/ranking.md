# ランキング

確認URL: `https://estar.jp/novels/ranking?ranking_type=all&ranking_axis_type=general_popular`

実HTMLのタブとリンクで確認した種別:

|`ranking_type`|表示/意味|`ranking_axis_type`|
|---|---|---|
|`all`|総合|`general_popular`（人気）、`general`（トレンド）|
|`kiriban`|スター|`general_popular`|
|`new_arrivals`|新着|`general_popular`、`type=pickup`|
|`finished`|完結|`general_popular`、`type=pickup`|
|`trend`|トレンド|`general`、`general_popular`|

日間・週間・月間・累計の明示的な全組合せは、画面内の値 `daily`, `weekly`, `monthly`, `total` を確認したが、各URLを全件取得した結果ではない。`RankingTypeMaster`へ固定定義する前に追加確認が必要。

ランキング作品はSSRの`ModelNovel`。作品ID、タイトル、著者、ジャンル、画像、文字数、更新日時、スター関連フィールドを持つ。1ページの実件数とURLページングパラメータはfixtureの対象ページで未確認。
