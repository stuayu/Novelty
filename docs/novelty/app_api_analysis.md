# 公式 Android アプリの API 静的解析

## 1. 調査範囲と表記

本書は、2026-08-25 時点で提供された jadx 逆コンパイル済みソースだけを対象にした静的解析結果である。実際の API への通信、証明書回避、動的計測は行っていない。したがって、「確認」と記した内容も「公式アプリのコード上で確認できた」という意味であり、現在のサーバーで受理されることや実レスポンスとの一致を保証しない。

秘密値になり得る API キー、`client_secret`、署名鍵は記録していない。広告 SDK の URL・ヘッダー・DTO は調査対象から除外した。

根拠パスは、次の逆コンパイルルートからの相対パスで記す。

- なろう: `/private/tmp/claude-501/-Users-ayumu-prog-Novelty/008702a4-f047-4744-8634-540ed01e2033/scratchpad/apk/narou/src`
- カクヨム: `/private/tmp/claude-501/-Users-ayumu-prog-Novelty/008702a4-f047-4744-8634-540ed01e2033/scratchpad/apk/kakuyomu/src`
- エブリスタ: `/private/tmp/claude-501/-Users-ayumu-prog-Novelty/008702a4-f047-4744-8634-540ed01e2033/scratchpad/apk/estar/src`
- アルファポリス: `/private/tmp/claude-501/-Users-ayumu-prog-Novelty/008702a4-f047-4744-8634-540ed01e2033/scratchpad/apk/alphapolis/src`

## 2. なろう（`com.syosetu.android`）

### 2.1 確認できた構成

`sources/com/syosetu/android/MainActivity.java` の `MainActivity` は、アプリ固有処理を持たず `C8.AbstractActivityC0533f` を継承するだけである。`sources/C8/AbstractActivityC0533f.java` には `io.flutter.*`、`FlutterActivity`、Flutter entrypoint の処理があり、このアプリが Flutter シェルであることを確認できる。

今回提供された jadx の Java ソースには、なろう固有のホスト名、Retrofit インターフェース、ログイン処理、同期 DTO が現れなかった。主要処理が Flutter AOT スナップショット側にあるため、Java/Kotlin ソースの文字列追跡だけでは到達できないと判断する。

### 2.2 確認できなかった情報

- API ベース URL
- ブックマーク／お気に入り一覧、追加、削除のエンドポイント
- しおり／読書位置および閲覧履歴のエンドポイント
- ログインエンドポイント、認証トークンまたは Cookie の仕様
- 共通ヘッダー
- 同期用レスポンス DTO

「公式 API が存在しない」という意味ではなく、提供された Java ソースからは確認できなかったという結論である。

### 2.3 AccountSyncAdapter 実装可否

`pullLibrary`、`addToRemoteLibrary`、`removeFromRemoteLibrary`、`pushReadingProgress` の全てについて、要求仕様を確定できる静的証拠がない。現資料だけでは公式アプリ API を用いた実装は不可。Flutter AOT 側の別手法による静的解析、または別タスクでの正規な実通信観測が必要である。

## 3. カクヨム（`jp.kadokawa.el.kakuyomu`）

### 3.1 API ベース URL

確認できたベース URL は `https://kakuyomu.jp/` である。

- `sources/defpackage/ho7.java` の Retrofit builder 相当処理が `https://kakuyomu.jp` を base URL に設定する。
- `sources/defpackage/np1.java` が GraphQL URL `https://kakuyomu.jp/api/app/graphql` を構築する。

### 3.2 同期関連エンドポイント

Retrofit インターフェースは `sources/defpackage/g32.java`。難読化後のアノテーションは、使用箇所から `@oh3 = GET`、`@e46 = POST`、`@gp1 = DELETE`、`@v86 = Path`、`@xk0 = Body` と読める。下表のパスには先頭 `/` がない宣言もあるが、ベース URL と結合した完全パスは同一である。同期関連メソッドにはクエリパラメータがない。

| 用途 | HTTP | 完全な URL | パラメータ／ボディ | レスポンス |
|---|---|---|---|---|
| フォロー作品一覧 | GET | `https://kakuyomu.jp/api/app/followings/works` | なし | `WorksJson` |
| 作品フォロー追加 | POST | `https://kakuyomu.jp/api/app/followings/works/{id}` | path: `id`（作品 ID、`String`）、body なし | `FollowingWorkJson` |
| 作品フォロー削除 | DELETE | `https://kakuyomu.jp/api/app/followings/works/{id}` | path: `id`（作品 ID、`String`）、body なし | `FollowingWorkJson` |
| 閲覧履歴／読書位置取得 | GET | `https://kakuyomu.jp/api/app/histories` | なし | `HistoriesJson` |
| 閲覧履歴／読書位置更新 | POST | `https://kakuyomu.jp/api/app/histories` | JSON: `{"histories":[UpdateHistoryJson, ...]}` | `HistoriesJson` |
| エピソード既読化 | POST | `https://kakuyomu.jp/api/app/works/{workId}/episodes/{episodeId}/read` | path: `workId`, `episodeId`（ともに `String`）、body なし | body なし（Kotlin `Unit`） |

`UpdateHistoryJson` の JSON は次の構造である。

```json
{
  "work_id": "作品ID",
  "episode_id": "エピソードID",
  "updated_at": "日時文字列",
  "position": "読書位置文字列"
}
```

根拠は `sources/defpackage/u49.java`（外側の `histories`）、`sources/defpackage/x49.java`（4フィールド）。`updated_at` の文字列書式と `position` の値域・単位は、静的 DTO からは確認できなかった。

### 3.3 認証方式

OAuth 2.0 Authorization Code + PKCE を使用するコードを確認した。

- 認可エンドポイント: `https://kakuyomu.jp/api/v2/oauth/authorize`
- トークンエンドポイント: `https://kakuyomu.jp/api/v2/oauth/token`
- client ID: `kakuyomu-android`
- redirect URI: `kakuyomu://kakuyomu.jp/oauth`
- response type: `code`
- PKCE: SHA-256 の `S256`。端末が SHA-256 非対応の場合は `plain` へフォールバック
- `state`、`nonce`: SecureRandom で生成
- scope: 認可リクエスト生成時に `null` であり、明示的な scope 指定なし

根拠は `sources/defpackage/yp9.java` の AppAuth 認可リクエスト生成と、`sources/com/tiktok/appevents/edp/TTEDPEventConstants.java` の `code` 定数である。`client_secret` は確認対象外であり、値は記録していない。

トークン更新は `sources/defpackage/a40.java` の AppAuth 処理に `refresh_token` grant がある。失効処理は `sources/defpackage/w30.java` の `POST /api/v2/oauth/revoke` で、form field は `token` と `token_type_hint`。ただし、アクセストークン／リフレッシュトークンの実レスポンス JSON 名や有効期間は、この調査では確定していない。

API リクエストへの認証付与は Bearer ではない。`sources/defpackage/h32.java` の interceptor が、Android `AccountManager` から得た認証値を次の独自ヘッダーへ設定する。

```http
X-Dcv-Login-Session: <認証値>
```

401 応答時には account type `jp.kadokawa.el.kakuyomu` の保存済み auth token を invalidate する。OAuth token と `X-Dcv-Login-Session` 値の変換・同一性はコード上で確定できなかったため、同一トークンとは断定しない。

### 3.4 共通ヘッダー

`sources/defpackage/ct0.java` とクライアント組み立て箇所 `sources/defpackage/np1.java` から、次を確認した。

```http
Accept: application/json
X-Requested-With: XMLHttpRequest
User-Agent: <System http.agent> Kakuyomu-Android/<アプリ版>
X-Dcv-Login-Session: <ログイン時の認証値>
```

`Accept` は `g32.java` の各同期メソッドに付いた Retrofit `@Headers`。端末固有 ID や API バージョン専用ヘッダーは確認できなかった。

### 3.5 同期用レスポンススキーマ

- `WorksJson`: `{"works":[WorkJson, ...]}`。根拠: `sources/defpackage/a4a.java`, `y3a.java`。
- `FollowingWorkJson`: `{"work_id": String, "is_following": bool}`。根拠: `sources/defpackage/fx9.java`, `dx9.java`。
- `HistoriesJson`: `{"histories":[HistoryJson, ...]}`。根拠: `sources/defpackage/mu3.java`, `ku3.java`。
- `HistoryJson`: `work`, `episode`, `position: String`, `updated_at: Long`, `unread_count: Int`。根拠: `sources/defpackage/uu3.java`。
- `EpisodeJson`: `id: String`, `number: Int`, `public_number: Int?`, `title: String`, `character_count: Int`, `body_html_url`, `permalink` など。根拠: `sources/defpackage/zi2.java`, `xi2.java`。
- `WorkJson`: `id`, `title`, `is_following`, `episodes`, `last_published_episode`, `followed_at`, `history` などを持つ。根拠: `sources/defpackage/yy9.java`。

`HistoryJson.updated_at` は受信時 `Long`、更新要求の `UpdateHistoryJson.updated_at` は `String` である点に注意が必要。どちらの時間単位・形式も実レスポンスでの確認が必要である。

### 3.6 AccountSyncAdapter 実装可否

アプリコード上は4メソッド全てに対応するエンドポイントがそろう。

- `pullLibrary`: `GET /api/app/followings/works`
- `addToRemoteLibrary`: `POST /api/app/followings/works/{id}`
- `removeFromRemoteLibrary`: `DELETE /api/app/followings/works/{id}`
- `pushReadingProgress`: `POST /api/app/histories`。エピソード単位の既読だけなら `/read` も利用候補

よって仕様候補としては実装可能。ただし `updated_at` と `position` の表現、OAuth token から login-session header への関係、ページング／件数上限、サーバーの現行挙動は未検証。既存 ADR の「公式 API なし」という記述は、この静的解析で公式アプリ専用 API の存在が確認できたため再検討対象になるが、実利用可否を確定するものではない。

## 4. エブリスタ（`jp.everystar.android.estarap1`）

### 4.1 API ベース URL

`sources/c7/l.java` は Retrofit 相当クライアントの base URL を `"https://" + R.string.web_domain` として構築する。`sources/Y6/b.java` も同じ文字列を `X-FROM` に使う。しかし、提供物の `resources` に `web_domain` の文字列値がなく、`sources/jp/everystar/android/estarap1/R.java` には整数リソース ID しか残っていない。このため、完全なベース URL は確認できなかった。

同様にログイン用ホストは `"https://" + R.string.auth_domain` まで確認できるが、ホスト名は未確認。

### 4.2 確認できた native API

同期以外を含め、アプリ固有 API の存在を確認する根拠として記す。

| HTTP | パス | パラメータ／ボディ | 根拠 |
|---|---|---|---|
| GET | `/api/native/versions/info` | query: `os`, `appVersion`, `osVersion` | `sources/p032e4/d.java` |
| POST | `/api/native/notice/device_tokens` | body DTO | `sources/p032e4/a.java` |
| POST | `/api/native/notice/device_tokens/delete` | body DTO | `sources/p032e4/a.java` |
| GET | `/api/native/pay/read_tickets/google/items` | アノテーション上は追加パラメータなし | `sources/p032e4/c.java` |
| POST | `/api/native` | JSON: `query` と `data`。`native/selfUser` など | `sources/p032e4/b.java`, `d.java` |

一方、ブックシェルフは `sources/Q4/o.java` で WebView の `/bookshelf` へ遷移し、閲覧画面も WebView URL として構築される。Java/Kotlin の Retrofit 定義には、作品お気に入り一覧・追加・削除、しおり更新、閲覧履歴に対応すると確認できる endpoint／query 名が見つからなかった。WebView 内 JavaScript／サーバー側画面遷移に隠れている可能性があるが、推測では補わない。

### 4.3 認証方式

ネイティブ HTTP と WebView が Android `CookieManager` を共有する Cookie 認証経路を確認した。

- `sources/I1/C.java` は OkHttp `CookieJar` 相当処理で、リクエスト URL に対して `CookieManager.getCookie(...)` を読み、レスポンス Cookie を `setCookie(...)` へ保存する。
- `sources/Y6/b.java` もレスポンスの `Set-Cookie` を `CookieManager` に保存する。
- `sources/Q4/G.java` は WebView の `/login`、`/register`、`/logout` を認証状態に関係するパスとして扱う。
- `sources/Q4/C0259a.java` は `/app/login_complete` をログイン完了として検出し、外部認証画面を `https://<auth_domain>` で開く。

したがって、確認できた認証搬送は Cookie。Cookie 名、ログイン POST の URL、フォーム／JSON 構造、トークン更新 API、OAuth の client ID・redirect URI・scope は確認できなかった。Bearer または独自認証ヘッダーの常時付与も、アプリ固有クライアントからは確認できなかった。

### 4.4 共通ヘッダー

`sources/Y6/b.java` から次を確認した。

```http
Accept: application/json
X-FROM: https://<web_domain>/api/native
User-Agent: <System http.agent> Mobile EstarApp/<アプリ版> <パッケージ名>
Cookie: <CookieManager が返す Cookie>
```

User-Agent の組み立て根拠は `sources/com/google/android/gms/internal/play_billing/AbstractC0587p0.java` の `v()`。端末識別子や API バージョン専用ヘッダーは確認できなかった。

### 4.5 同期用レスポンススキーマ

同期 endpoint 自体を特定できなかったため、作品 ID、エピソード ID、読書位置を含む同期レスポンス DTO も確認できなかった。`native/selfUser` など別用途の DTO を同期仕様として転用できる根拠はない。

### 4.6 AccountSyncAdapter 実装可否

`pullLibrary`、`addToRemoteLibrary`、`removeFromRemoteLibrary`、`pushReadingProgress` の全てについて、完全なホスト名と同期 endpoint／body／response が未確認。現資料だけでは実装不可。WebView が実行する通信を別タスクで正規に観測し、Cookie 名を含む実仕様を裏取りする必要がある。

## 5. アルファポリス（`jp.co.alphapolis.viewer`）

### 5.1 API ベース URL

確認できた API ベース URL は `https://www.alphapolis-app.jp/`。

- `sources/jp/co/alphapolis/commonlibrary/BuildConfig.java` の `apiHost` がこの値を持つ。Web サイト用 `websiteHost` は別に `https://www.alphapolis.co.jp/`。
- `sources/defpackage/pv2.java` の Retrofit builder 相当処理が `BuildConfig.apiHost` を base URL に設定する。

### 5.2 作品お気に入り API

全て JSON body の POST。path／query パラメータはない。Retrofit 根拠は `sources/jp/co/alphapolis/network/api/FavoriteContentsApi.java`。

| 用途 | 完全な URL | JSON body | 主なレスポンス |
|---|---|---|---|
| お気に入り一覧 | `https://www.alphapolis-app.jp/api/mypage/favContentList.json` | `page: Int`, `limit: Int`, `token: String?`, `disp_kind: Int`, `sort: Int`, `search_word: String?`, `list_id: Int?` | `FavoriteContentListEntity` |
| お気に入り追加 | `https://www.alphapolis-app.jp/api/mypage/favContRegist.json` | `citi_cont_id: Int`, `favorite_content_list_ids: List?` | `FavoriteTotalEntity` |
| お気に入り削除 | `https://www.alphapolis-app.jp/api/mypage/favContDelete.json` | `citi_cont_id: Int` | `FavoriteTotalEntity` |
| 更新作品一覧 | `https://www.alphapolis-app.jp/api/mypage/updateContentList.json` | `disp_kind: Int`, `sort: Int`, `page: Int`, `limit: Int` | 更新作品一覧 DTO |

一覧 body の根拠は `sources/defpackage/ud4.java`, `sd4.java`、追加は `e3a.java`, `c3a.java`、削除は `j93.java`, `h93.java`。`ud4` と後述のブックマーク一覧 DTO のコンストラクタには `limit = 200` を渡す使用箇所があるが、サーバー上限とは断定しない。`token` は一覧 body のフィールド名として確認しただけで、認証トークンとの関係は未確認。

各 request は、継承元 `sources/defpackage/mp0.java` と各 serializer により、必要に応じて次の共通フィールドも持つ。

```json
{
  "app_name": "文字列",
  "platform": "文字列",
  "screen": {"inch": 0.0},
  "version": "文字列"
}
```

初期値は空文字列等で、serializer はデフォルト値を省略し得る。実際の各値は呼び出し側で設定されるため、固定値としては記録しない。

### 5.3 しおり・読了 API

「作品お気に入り」と「エピソード位置のブックマーク」は別 API である。Retrofit 根拠は `sources/jp/co/alphapolis/network/api/BookmarksApi.java` と `ContentsApi.java`。

| 用途 | HTTP／完全な URL | JSON body | レスポンス |
|---|---|---|---|
| ブックマーク一覧 | POST `https://www.alphapolis-app.jp/api/mypage/bookMarkList.json` | `page: Int`, `limit: Int`, `sort: Int` | `BookMarkListEntity` |
| ブックマーク登録 | POST `https://www.alphapolis-app.jp/api/webCont/bookMarkRegist.json` | `content_block_id: Int` | `BookMarkRegistEntity` |
| ブックマーク削除 | POST `https://www.alphapolis-app.jp/api/webCont/bookMarkDelete.json` | `citi_cont_id: Int` | `BookMarkDeleteEntity` |
| 読了位置送信 | POST `https://www.alphapolis-app.jp/api/webCont/finish_reading.json` | `citi_cont_id: Int`, `content_block_id: Int`, `app_login: bool` | 空レスポンス DTO |

body serializer の根拠は順に `sources/defpackage/t11.java`, `w2a.java`, `s83.java`, `mj4.java`。削除 body が `content_block_id` ではなく `citi_cont_id` であることは serializer の事実として記録し、意味は推測しない。

### 5.4 認証方式

ログイン API を確認した。

- HTTP／URL: `POST https://www.alphapolis-app.jp/api/login/alphapolis.json`
- JSON body: `email`, `citi_pass`, `token`, `iap_token` と前述の `app_name`, `platform`, `screen`, `version`
- Retrofit 根拠: `sources/jp/co/alphapolis/network/api/UsersApi.java`
- path 定数根拠: `sources/jp/co/alphapolis/commonlibrary/network/api/ApiConstants.java`
- body 根拠: `sources/defpackage/xbd.java`, `vbd.java`
- response: `LoginEntity`。`citi_id`, `profile_img_url`, `p_name`, 一時登録フラグ、`login_message`, `iap_info`。根拠: `sources/defpackage/wh6.java`, `uh6.java`

`sources/jp/co/alphapolis/viewer/domain/login/ViewerAutoLoginUseCase.java` は、保存した `email`, `citi_pass`, `token`, `iap_token` を用いて同じログイン処理を再実行する。明示的な refresh endpoint は確認できなかった。

一方、同期 API の Retrofit client で Bearer、独自認証ヘッダー、Cookie 名を付けるアプリ固有 interceptor は確認できず、`LoginEntity` にアクセストークン項目もない。したがって、認証状態が Cookie、body の `token`、または別の内部状態のどれで各 mypage API に運ばれるかは確定できない。`token`／`iap_token` の生成元と意味も未確認。秘密値は記録していない。

### 5.5 共通ヘッダー

同期 Retrofit インターフェースに固定 `@Headers` はなく、アプリ固有の User-Agent、API バージョン、端末 ID、認証ヘッダーを常時付けることも確認できなかった。確実に確認できた共通情報は JSON body の `app_name`, `platform`, `screen.inch`, `version` であり、ヘッダーではない。

### 5.6 同期用レスポンススキーマ

- `FavoriteContentListEntity`: `fav_content_list`, `disp_info`, `next_page`, `total_count`, `favorite_content_list`。根拠: `sources/defpackage/yc4.java`, `nc4.java`。
- お気に入り要素: `content_info`, `user_info`, `push_info`, `favorite_content_lists`, `total_content_block_count`, `displayInfo`。根拠: `sources/defpackage/xc4.java`, `sc4.java`。
- `content_info`: `title`, `citi_cont_id`（作品 ID、必須 `Int`）, `category_id`, `cover_url`, `last_update_time` など。根拠: `sources/defpackage/xf2.java`, `sf2.java`。
- `BookMarkListEntity`: `book_mark_info_list`, `disp_info`, `next_page`。根拠: `sources/defpackage/s11.java`, `h11.java`。
- ブックマーク要素: `content_info`, `book_mark_info`, `update_info`。根拠: `sources/defpackage/q11.java`, `i11.java`。
- `book_mark_info`: `content_block_title`, `content_block_id`（エピソード／ブロック ID）。根拠: `sources/defpackage/m11.java`, `k11.java`。
- `update_info`: `total: String`, `position: String`。根拠: `sources/defpackage/p11.java`, `n11.java` と、難読化定数の値を持つ `sources/com/ironsource/U3.java`。

`position` の単位、`total` との関係、同一作品に複数ブックマークを持てるか、`finish_reading` とブックマーク登録の使い分けは実レスポンスでの確認が必要である。

### 5.7 AccountSyncAdapter 実装可否

アプリコード上、作品ライブラリの3メソッドには直接対応する候補がある。

- `pullLibrary`: `POST /api/mypage/favContentList.json`
- `addToRemoteLibrary`: `POST /api/mypage/favContRegist.json`
- `removeFromRemoteLibrary`: `POST /api/mypage/favContDelete.json`

`pushReadingProgress` は `finish_reading.json` とブックマーク登録 API が候補だが、Novelty の任意 `position` を送るフィールドは確認できず、受信 DTO にだけ `position` がある。よってエピソード／ブロック単位の進捗送信は実装候補あり、章内の任意位置同期は現仕様だけでは不可。

さらに認証セッションの搬送方式が未確定であるため、4メソッド全体を実装可能と断定はできない。次タスクでログイン後の正規な実通信を観測し、Cookie／token、body の実値、ページング、削除 body の意味を確認する必要がある。

## 6. 静的解析からの総括

| サイト | ライブラリ3操作 | 読書位置送信 | 静的解析上の結論 |
|---|---|---|---|
| なろう | 未確認 | 未確認 | Flutter AOT 側に主要処理があり、提供 Java ソースだけでは実装不可 |
| カクヨム | 一覧・追加・削除を確認 | 履歴一括更新と既読化を確認 | 4メソッドの仕様候補がそろう。実通信での認証・値形式確認が必要 |
| エブリスタ | 未確認 | 未確認 | native API はあるが同期処理は WebView 側。現資料だけでは実装不可 |
| アルファポリス | 一覧・追加・削除を確認 | ブロック単位候補のみ | 認証搬送と任意位置更新が未確定。限定的な実装候補 |

いずれも、公式アプリの逆コンパイル結果だけを根拠に第三者クライアントからの利用可否、利用規約上の許諾、API の安定性を判断してはならない。次段階では秘密情報を収集せず、本人アカウントと通常の公式アプリ操作による通信だけで、ここに記した候補を検証する。
