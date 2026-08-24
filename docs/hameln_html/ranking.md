# ランキング

トップページからランキングURL `https://syosetu.org/?mode=rank` を確認した。素のcurlで取得を試みたところHTTPレスポンス本文はCloudflareのJavaScriptチャレンジ（`Just a moment...`、`Enable JavaScript and cookies to continue`）となった。チャレンジ回避は行っていない。

したがって、ランキング種別の完全な一覧、各ランキングのURL、DOM、1ページ件数、ページングURLは未確認。`RankingTypeMaster`への確定マッピング不可。`?mode=rank`という入口だけを確認済みとする。
