# ランキング

トップページからランキングURL `https://syosetu.org/?mode=rank` を確認した。素のcurlで取得を試みたところHTTPレスポンス本文はCloudflareのJavaScriptチャレンジ（`Just a moment...`、`Enable JavaScript and cookies to continue`）となった。チャレンジ回避は行っていない。

したがって、ランキング種別の完全な一覧、各ランキングのURL、DOM、1ページ件数、ページングURLは未確認。`RankingTypeMaster`への確定マッピング不可。`?mode=rank`という入口だけを確認済みとする。

## 追加確認済み（2026-08-25）

`?mode=rank`は日間ランキングを返し、`div.section3[id^="nid_"]`を100件含んでいた。今回取得ページにページャーはなく、100件超のページURLは未確認。

|id|label|urlPath|
|---|---|---|
|rank_day|一般総合・日間|`/?mode=rank_day`|
|rank_2_day|一般二次・日間|`/?mode=rank_2_day`|
|rank_ori_day|一般オリ・日間|`/?mode=rank_ori_day`|
|rank_ss_day|一般短編・日間|`/?mode=rank_ss_day`|
|rank_week|週間|`/?mode=rank_week`|
|rank_month|月間|`/?mode=rank_month`|
|rank_3month|四半期|`/?mode=rank_3month`|
|rank_year|年間|`/?mode=rank_year`|
|rank_total|累計|`/?mode=rank_total`|
|rank_relative|相対|`/?mode=rank_relative`|
|rank_complete_total|完結累計|`/?mode=rank_complete_total`|
|rank_complete_relative|完結相対|`/?mode=rank_complete_relative`|
|rank_wsi|WSI|`/?mode=rank_wsi`|
|rank_favo_ratio_nocolor|お気に入り率|`/?mode=rank_favo_ratio_nocolor`|
|rank_add_day2|透明|`/?mode=rank_add_day2`|
|rank_new_user|ルーキー|`/?mode=rank_new_user`|
|rank_new|新作|`/?mode=rank_new`|
|rank_add_day|日間加点|`/?mode=rank_add_day`|

一般系の各期間リンクをHTMLで確認した。R18総合・R18二次・R18オリは別ドメインの`rank_r18_day`、`rank_r18_2_day`、`rank_r18_ori_day`へのリンクのみ確認し、本文は取得していない。ページング形式は未確認。

各項目は同一`section3`内に、作品リンク `.blo_title_base > a[href*="/novel/"]`、著者 `.blo_title_sak`、状態・話数・総文字数 `.blo_wasuu_base`、調整平均 `.blo_hyouka .blo_mix`、順位 `.blo_rank`、原作等 `.blo_genre`、最終更新 `.blo_date[title="最終更新日"]`、あらすじ `.all_arasuji .blo_inword`、タグ・評価等 `.all_keyword`を持つ。評価指標は`調整平均`、`評価`、UA、お気に入り、感想、投票者、平均文字数。
