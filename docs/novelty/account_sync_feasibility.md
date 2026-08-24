# 4サイト アカウント同期実現性調査

- 調査日: 2026-08-25
- 方法: ログイン・アカウント作成・資格情報入力なし。`curl` による公開HTML、`robots.txt`、既存の `docs/{site}_html/` の確認のみ。
- 未実施: ログイン後ページ、API/GraphQL mutation、POST操作。Headless Browser/WebView、CAPTCHA回避、robots禁止パスへのアクセスも未実施。

## 結論

今回の4サイトについて、確認済み仕様だけで `AccountSyncAdapter` の4メソッドを実装開始できるサイトはない。

- **ノベルアップ＋**: `/my/` と `/api/` が `robots.txt` で禁止。ブックマーク・しおりのリンクは確認できるがアクセス不可。現条件では実装不可。
- **ハーメルン**: `mode=favo_` と `mode=siori2_` が `robots.txt` で禁止。フォームは確認できるが、同期対象の操作仕様を確認済みとして扱えない。現条件では実装不可。
- **アルファポリス**: フォームPOSTログインは確認できたが、一覧・追加・削除・読書位置のエンドポイント、CSRF仕様、規約上の許可が未確認。実装可とは判定しない。
- **エブリスタ**: メール・パスワードフォーム、OAuth認可、SNS連携は確認できたが、ログイン後同期エンドポイントが未確認。実装可とは判定しない。

ログインHTMLに `recaptcha`、`hcaptcha`、`turnstile` は見つからなかった。ただしサーバー側判定や遷移先は未確認のため「CAPTCHAなし」と断定しない。2要素認証も4サイトとも未確認。

## ログイン方式比較

| サイト | ログインページ | 方式 | CAPTCHA | 2FA | 素のHTTPで可能か | 判定 |
|---|---|---|---|---|---|---|
| アルファポリス | `https://www.alphapolis.co.jp/login` | `POST https://www.alphapolis.co.jp/login`。メール・パスワード | 公開HTMLでは未確認 | 未確認 | フォームとCSRFは観察できるが成功可否未確認 | 同期実装保留 |
| ハーメルン | `https://syosetu.org/?mode=login` → `?mode=login_entry&auth_failed=1` | `POST ./`。`id`、`pass`、hiddenの `mode`、`redirect_mode` | 公開HTMLでは未確認 | 未確認 | フォームは観察できるが成功未確認 | 同期実装不可（robots） |
| エブリスタ | `https://estar.jp/login` → `https://auth.estar.jp/auth/sign_in` | OAuth認可導線。メール・パスワードPOST、LINE/Twitter/Google/D account/Apple連携 | 公開HTMLでは未確認 | 未確認 | 認可・CSRF・Cookie未確定。単純Dioログインとは判定しない | 同期実装保留 |
| ノベルアップ＋ | `https://novelup.plus/login` | `POST https://novelup.plus/login`。メール・パスワード、任意のremember | 公開HTMLでは未確認 | 未確認 | フォームとCSRFは観察できるが同期先がrobots禁止 | 同期実装不可（robots） |

### フォームの観察結果

| サイト | POST先 | 全入力name | hidden値の出どころ | 必要ヘッダー |
|---|---|---|---|---|
| アルファポリス | `https://www.alphapolis.co.jp/login` | `_token`, `email`, `password` | `_token` はログインHTMLのhidden。Cookie `XSRF-TOKEN` との関係は未確認 | `Content-Type`、`Referer`、`Origin`、`X-Requested-With` は未確認 |
| ハーメルン | `./` | `id`, `pass`, `mode`, `redirect_mode`（表示制御用checkboxもあり） | `mode=login_entry_end`、`redirect_mode` はHTMLのhidden。CSRF hiddenは未確認 | 未確認 |
| エブリスタ | `/auth/sign_in`（認証ホスト） | `authenticity_token`, `user[email]`, `user[password]`, `commit` | tokenは認証ホストHTML。SNSフォームにも固有token | 未確認 |
| ノベルアップ＋ | `https://novelup.plus/login` | `_token`, `mail`, `password`, `remember` | `_token` はログインHTMLのhidden。Cookie `XSRF-TOKEN` との関係は未確認 | `Content-Type`、`Referer`、`Origin`、`X-Requested-With` は未確認 |

## セッションの観察結果

未ログインGETで発行されたCookieを、ログイン後セッションCookieとは断定しない。値は保存していない。

| サイト | Cookie名 | 期限表示 | ログイン状態の判定候補 |
|---|---|---|---|
| アルファポリス | `AWSALB`, `AWSALBCORS`, `XSRF-TOKEN`, `alpl_v2_front_session`, `device_uuid` | XSRF/session約7日、device約180日 | ログイン後専用ページまたはログイン導線の有無。具体仕様未確認 |
| ハーメルン | `uaid`、空値の `uu` | `uaid` は2037年表示。`uu` は過去日付で無効化 | ログインフォームredirectまたはマイページ要素。成功時仕様未確認 |
| エブリスタ | `estar_session`、`_tama_auth_session` | `estar_session`約1年、認証session約7日 | OAuth callback後の会員ページ。成功判定未確認 |
| ノベルアップ＋ | `XSRF-TOKEN`、`_s` | 約30日 | `/my/` の会員ページ。ただしrobots禁止 |

## AccountSyncAdapter の実装可否

「不可」は機能が絶対に存在しないという意味ではなく、今回の制約下で確認済み根拠だけでは実装してはならないという意味である。

| サイト | `pullLibrary` | `addToRemoteLibrary` | `removeFromRemoteLibrary` | `pushReadingProgress` |
|---|---|---|---|---|
| アルファポリス | 不可（一覧未確認） | 不可（追加・CSRF未確認） | 不可（削除・CSRF未確認） | 不可（しおり未確認） |
| ハーメルン | 不可（`mode=favo_` robots禁止） | 不可（同左） | 不可（同左） | 不可（`mode=siori2_` robots禁止） |
| エブリスタ | 不可（本棚・フォロー一覧未確認） | 不可（追加操作未確認） | 不可（削除操作未確認） | 不可（しおり・位置未確認） |
| ノベルアップ＋ | 不可（`/my/` robots禁止） | 不可（`/api/` robots禁止） | 不可（`/api/` robots禁止） | 不可（`/my/`・`/api/` robots禁止） |

### 公開HTMLで確認できた導線

- アルファポリス: ログインHTMLに「お気に入りの作品登録」の説明。具体的な操作URLは未確認。
- ハーメルン: robots.txtに `mode=favo_` と `mode=siori2_`。公開作品HTMLの集計値はアカウント同期仕様ではない。
- エブリスタ: ログイン・OAuth・SNS導線のみ確認。ログイン後の本棚、フォロー、しおり、履歴URLは未確認。
- ノベルアップ＋: `/my/bookmark` と `/my/guidebook` のリンクを確認。ただし `/my/` はrobots禁止。履歴・追加削除・更新URLは未確認。

## robots.txt 判定

| サイト | 結果 | 影響 |
|---|---|---|
| アルファポリス | HTTP 200。対象ログイン関連の禁止規則は未確認 | robotsだけでは不可としないが、規約・エンドポイント未確認 |
| ハーメルン | HTTP 200。`mode=favo_`、`mode=siori2_` を `User-agent: *` で禁止 | お気に入り・しおり同期へアクセスしない |
| エブリスタ | HTTP 404 JSON。規則を取得できず許可とは解釈しない | ログイン後操作未実施 |
| ノベルアップ＋ | HTTP 200。`/my/`、`/api/` を `User-agent: *` で禁止 | 会員一覧・内部APIへアクセスしない |

## 未確認項目

- 4サイトともログイン成功レスポンス、認証Cookieの発行条件、更新・失効条件。
- 4サイトとも2FA、ログイン後追加チャレンジ、サーバー側CAPTCHA判定。
- アルファポリスの一覧・追加・削除・しおり・履歴のURL、method、CSRF。
- ハーメルンのログイン成功HTMLとrobots禁止対象を使わない公式代替API。
- エブリスタのOAuth code交換、redirect URI、state/nonce、ログイン後同期API。
- ノベルアップ＋のrobots許可範囲内の公式同期API。`/api/` は未取得。
- 4サイトの自動ログイン、第三者アプリへのアカウント情報提供、非公式クライアントに関する明示条項。

## 実装推奨順序

実装は開始しない。再開条件がそろった場合の順序は次のとおり。

1. アルファポリス: 運営許諾、同期エンドポイント、CSRF、規約適合が確認できた場合。
2. エブリスタ: 公式OAuthまたは運営許諾と、ログイン後HTTP同期仕様が確認できた場合。
3. ハーメルン: robots禁止対象を使わない公式代替手段が確認できた場合のみ。
4. ノベルアップ＋: `/my/`・`/api/` を使わない公式手段、または運営許諾が確認できた場合のみ。

同期失敗は `AccountSyncOutcome.failed` 等に局所化し、ローカル読書機能を停止させない。秘密Cookie、CSRF値、OAuth codeはログ・fixture・文書へ保存しない。

---

## 方針決定（2026-08-25 追記）

プロジェクトオーナーが以下を決定した。

### 1. robots.txt はアカウント同期には適用しない

robots.txt はクローラー向けの規約であり、利用者が自分のアカウントに対して明示的に
実行する同期操作には適用しないと判断する。

これにより、上記の表で「robots禁止」を理由に実装不可としていた以下が対象に戻る。

- ハーメルン: `?mode=favo_`（お気に入り）、`?mode=siori2_`（しおり）
- ノベルアップ＋: `/my/`（ブックマーク・しおり）、`/api/`

**ただし読書コア（作品情報・目次・本文・ランキング・検索）の取得については、
従来どおり robots.txt を遵守する。** 適用外とするのは、ログイン済みユーザーが
自分のアカウントに対して行う同期操作に限る。レート制限とキャッシュファーストは
引き続き必須とする。

### 2. 同期APIの仕様はアプリ解析で入手する

ログインしないと観測できないエンドポイントについては、公式Androidアプリを解析して
仕様を特定する方針とする。

#### 公式アプリの有無（2026-08-25 確認）

| サイト | Android | iOS | 解析可否 |
|---|---|---|---|
| エブリスタ | `jp.everystar.android.estarap1` | `id468596070` | 解析可能 |
| アルファポリス | `jp.co.alphapolis.viewer` | 未確認 | 解析可能 |
| ノベルアップ＋ | 公式サイトにリンクなし | なし | **アプリ無し。Web調査で対応** |
| ハーメルン | 公式サイトにリンクなし | なし | **アプリ無し。Web調査で対応** |

エブリスタとアルファポリスはサイトのフッター等からストアへのリンクを確認した。
ノベルアップ＋とハーメルンはリンクが見つからず、Webのみのサービスと判断する。
この2サイトについては、robots.txt の適用外判断により、ログイン後のページを
直接調査して同期仕様を特定する。

#### 留意事項

- 非公開APIは予告なく変更されうる。バージョン差分で壊れることを前提に、
  同期失敗がローカルの読書機能を止めない設計を維持する
  （`docs/novelty/native_account_sync_review.md` の絶対条件）
- 解析で得た仕様は、実際のレスポンスで裏を取ってから実装する。
  逆コンパイル結果の読み取りだけを根拠にしない
