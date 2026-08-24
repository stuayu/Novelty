# ハーメルン HTML 調査

調査日: 2026-08-24

対象: `https://syosetu.org/`

取得方法: `curl` による素のHTTP取得。Headless Browser / WebViewは未使用。リクエスト間隔は1秒以上。R18ドメイン・R18本文は取得していない。

## 取得できたサンプル

- 連載目次: `https://syosetu.org/novel/328453/`
- 短編本文: `https://syosetu.org/novel/424174/`（作品URLから第1話へ遷移）
- トップページ: `https://syosetu.org/`

## 未確認

利用規約、通常ランキング、通常検索、非公開・削除作品の詳細レスポンスは、調査中にCloudflareのJavaScriptチャレンジへ切り替わったため未確認。チャレンジ回避は行っていない。

詳細は各ファイルと `concerns.md` を参照。
