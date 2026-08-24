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

## 追加調査（2026-08-25）

通常のブラウザ相当ヘッダー付き `curl`（環境の証明書チェーン問題のため `-k` を使用）で追加取得した。Headless Browser / WebViewは未使用。取得間隔は1秒以上。

- 利用規約: `https://syosetu.org/?mode=rule`
- FAQ: `?mode=faq_list`、`?mode=faq_view&fid=50/74/77/118`
- 通常ランキング: `https://syosetu.org/?mode=rank`
- 通常検索: `https://syosetu.org/search/?mode=search&word=原作：オリジナル`
- 100話超作品: 作品ID `408150`（目次133話）
- ルビ・傍点本文: 作品ID `399831` 第38話

未確認だった通常ページは今回、CloudflareチャレンジではなくHTML本文を取得できた。実測結果と判定は各項目へ追記した。
