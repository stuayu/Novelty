# Novelty カクヨム同期・読書支援機能 実装指示書

## 0. この文書の目的

この文書は、比較的小さいモデルでも判断を誤らずに実装できるよう、Novelty のカクヨムアカウント同期と、その後の読書支援機能を段階的に実装するための手順を固定する。

対象リポジトリ: `stuayu/Novelty`

対象ブランチ: `develop`

最終目標は以下。

1. 現在「小説家になろう」専用になっているアカウント同期処理をサイト共通化する。
2. カクヨムのログイン済みセッションを安全に扱えるようにする。
3. Novelty のライブラリとカクヨムの「小説フォロー」を同期する。
4. Novelty の読書位置とカクヨム側の閲覧履歴を、確認できる範囲で同期する。
5. 将来ほかの小説サイトを追加しやすい構造にする。
6. その後、未読管理・続きを読む・新着管理などの読書支援機能を追加する。

---

# 1. 絶対に守るルール

## 1.1 一度に全部実装しない

この文書は複数の Phase に分かれている。

**必ず Phase 1 → Phase 2 → Phase 3 ... の順番で進めること。**

1つの Phase が完了する前に次の Phase を実装してはいけない。

最初に依頼された場合は、**Phase 1 の実装計画だけを提示し、コード変更を開始しないこと。**

リポジトリの `AGENTS.md` に従い、計画承認後に TDD で実装すること。

## 1.2 未確認仕様を想像しない

特にカクヨムについて、以下を想像で作ってはいけない。

- API URL
- HTTP method
- GraphQL query / mutation
- POST body
- CSRF token 名
- Cookie 名
- HTML selector
- JavaScript 関数名
- 内部 API のレスポンス形式

分からないものは、実際の HTML、ブラウザ動作、既存 fixture、保存済み資料で確認する。

**存在を確認できない非公開 API を勝手に実装しないこと。**

## 1.3 認証制限を回避しない

CAPTCHA、Google ログイン、Apple ログイン、パスキーなどが表示された場合はユーザー自身に操作させる。

それらを自動突破する処理は作らない。

## 1.4 秘密情報をログへ出さない

以下を `debugPrint`、`print`、例外メッセージ、テストログへ出してはいけない。

- password
- Cookie 値
- Authorization 情報
- CSRF token
- session token

## 1.5 読書機能を同期処理で止めない

外部サイトとの同期は付加機能である。

同期失敗によって以下を止めてはいけない。

- 本文表示
- ページ送り
- ローカル履歴保存
- ローカルキャッシュ
- オフライン読書

外部サービスが障害中でも、Novelty 内の読書は可能な限り継続できること。

---

# 2. 作業開始前に必ず読むファイル

最初に以下を読む。

1. `AGENTS.md`
2. `CONTEXT.md`
3. `DESIGN.md`
4. `docs/architecture/multi_provider.md`
5. `lib/sites/novel_site.dart`
6. `lib/sites/novel_site_registry.dart`
7. `lib/services/narou_auth_service.dart`
8. `lib/services/narou_sync_service.dart`
9. `lib/repositories/auth_repository.dart`
10. `lib/repositories/novel_repository.dart`
11. `lib/screens/novel_page.dart`
12. `lib/providers/auth_provider.dart`
13. `lib/screens/more_page.dart`
14. `lib/database/database.dart`

現在の構造を理解せずに新しい抽象化を追加してはいけない。

---

# 3. 作業開始時の確認

実装前に以下を実行する。

```bash
git status
git branch --show-current
mise run get
mise run codegen
mise run test
mise run check
```

期待値:

- 現在ブランチが `develop`
- 既存テスト成功
- analyze error 0
- lint issue 0
- format 差分 0

最初から失敗しているものがある場合は、今回の変更による失敗と混同しないよう記録する。

---

# Phase 1: なろう同期をサイト共通インターフェースで包む

## 4. Phase 1 の目的

現在は概ね以下の依存になっている。

```text
NovelRepository
    ↓
NarouSyncService
```

```text
NovelPage
    ↓
NarouSyncService
```

これを以下へ変更する。

```text
NovelRepository / NovelPage
          ↓
 AccountSyncAdapter
          ↓
NarouAccountSyncAdapter
          ↓
   NarouSyncService
```

**Phase 1 ではカクヨム同期を実装しない。**

なろうの現在の挙動を維持しながら、呼び出し側から `NarouSyncService` への直接依存を除去することが目的。

---

## 4.1 `AccountSyncAdapter` を作る

新規ファイル:

```text
lib/sites/account_sync_adapter.dart
```

最低限、以下の型を定義する。

```dart
import 'package:novelty/sites/novel_source.dart';

enum AccountSyncOutcome {
  success,
  notLoggedIn,
  failed,
}

abstract interface class AccountSyncAdapter {
  NovelSource get source;

  Future<int> pullLibrary();

  Future<AccountSyncOutcome> addToRemoteLibrary(String workId);

  Future<AccountSyncOutcome> removeFromRemoteLibrary(String workId);

  Future<bool> pushReadingProgress({
    required String workId,
    required int episode,
  });
}
```

### 入れてはいけないもの

`AccountSyncAdapter` に以下を入れない。

- UI
- `BuildContext`
- `WidgetRef`
- なろう固有型
- カクヨム固有型
- HTTP 実装
- Cookie 実装

インターフェースはサイト共通語彙だけを使う。

---

## 4.2 `NarouAccountSyncAdapter` を作る

新規ファイル:

```text
lib/sites/narou/narou_account_sync_adapter.dart
```

このクラスは `AccountSyncAdapter` を実装する。

内部では既存の `NarouSyncService` を呼ぶ。

### コンストラクタ

最低限以下を注入できる構造にする。

- `NarouSyncService`
- `AppDatabase`

テストで差し替えられるようにする。

### `pullLibrary()`

既存の以下を呼ぶ。

```dart
syncBookmarksFromNarou()
```

返却されたリストの `length` を返す。

### `addToRemoteLibrary()`

既存の以下を呼ぶ。

```dart
addBookmarkToNarou(workId)
```

`NarouBookmarkSyncOutcome` を `AccountSyncOutcome` へ変換する。

成功時に既存の `useridFavncode` / `token` が返った場合は、既存 DB メソッド `markNarouBookmarkSynced(...)` を adapter 内で実行する。

つまり `NovelRepository` から以下を見えなくする。

- `NarouBookmarkSyncResult`
- `NarouBookmarkSyncOutcome`
- `useridFavncode`
- なろう用 token

### `removeFromRemoteLibrary()`

既存の以下を呼ぶ。

```dart
removeBookmarkFromNarou(workId)
```

結果を `AccountSyncOutcome` へ変換する。

### `pushReadingProgress()`

既存の以下を呼ぶ。

```dart
setShioriIfLoggedIn(
  ncode: workId,
  episode: episode,
)
```

返却された `bool` をそのまま返してよい。

---

## 4.3 Account Sync Registry を作る

新規ファイル:

```text
lib/sites/account_sync_registry.dart
```

Riverpod から取得できるレジストリを作る。

概念:

```dart
Map<NovelSource, AccountSyncAdapter>
```

Phase 1 では `NovelSource.narou` だけ登録する。

**カクヨムはまだ登録しない。**

呼び出し側はサイト名で `if` を書かず、レジストリから adapter を取得する。

---

## 4.4 `NovelRepository` を変更する

対象:

```text
lib/repositories/novel_repository.dart
```

同期処理に存在する以下のような分岐を除去する。

```dart
if (source == NovelSource.narou) {
  ...
}
```

代わりにレジストリから以下を取得する。

```text
adapter = registry[source]
```

adapter が存在しない場合は「同期機能なし」としてローカル操作だけ実行する。

### ライブラリ追加の処理順

必ず以下の順番にする。

```text
1. NovelInfo 取得
2. Novels 保存
3. LibraryEntries 追加
4. AccountSyncAdapter が存在すれば remote add
5. UI 更新
```

remote add が失敗してもローカル追加を取り消さない。

現在のなろう挙動を変えない。

### ライブラリ削除

現在のなろう挙動を維持する。

adapter なし:

```text
ローカル削除
```

adapter あり + `success`:

```text
ローカル削除
```

adapter あり + `notLoggedIn`:

```text
ローカル削除
```

adapter あり + `failed`:

```text
ローカル削除を中止
```

この Phase で削除仕様を変更してはいけない。

---

## 4.5 `NovelPage` を変更する

対象:

```text
lib/screens/novel_page.dart
```

現在の `source == NovelSource.narou` による同期分岐を削除する。

ローカル履歴保存後、レジストリから adapter を取得する。

adapter が存在する場合だけ以下を `unawaited` で呼ぶ。

```dart
adapter.pushReadingProgress(
  workId: workId,
  episode: episode,
)
```

adapter が無い場合は何もしない。

**本文表示やページ送りを同期完了待ちにしてはいけない。**

---

## 4.6 Phase 1 のテスト

最低限、新規テストを追加する。

```text
test/sites/narou/narou_account_sync_adapter_test.dart
```

確認項目:

- Narou success → Account success
- Narou notLoggedIn → Account notLoggedIn
- Narou failed → Account failed
- `pullLibrary()` が同期件数を返す
- `pushReadingProgress()` が既存なろう処理へ委譲する
- bookmark success 時に同期情報が DB へ保存される

`NovelRepository` についても確認する。

- adapter 無しでもライブラリ追加可能
- remote add 失敗でもローカルには追加される
- remote remove 失敗ならローカル削除しない
- remote remove が notLoggedIn ならローカル削除する

既存なろうテストもすべて成功させる。

---

## 4.7 Phase 1 完了条件

以下を実行する。

```bash
mise run codegen
mise run format
mise run test
mise run check
```

すべて成功すること。

Phase 1 が完了したら一度作業を止め、結果を報告する。

**Phase 2 へ自動的に進んではいけない。**

---

# Phase 2: カクヨム用ログインセッション基盤

## 5. Phase 2 の目的

Novelty 自身がカクヨムのパスワードを受け取ってログイン API を再実装する方式を避ける。

基本方針:

```text
Novelty
  ↓
カクヨム公式ログイン画面
  ↓
ユーザーが公式 UI でログイン
  ↓
ログイン済みセッションを確認
  ↓
必要な Cookie のみ Secure Storage へ保存
```

Google / Apple / パスキーなどの認証が必要な場合も、公式画面上でユーザー自身が操作する。

---

## 5.1 WebView 実装を選定する

Phase 2 開始時点で、現在の Flutter バージョンと各 OS の対応状況を調査する。

必要条件:

- Android
- iOS
- macOS
- Windows

Linux は最初から無理に対応しない。

Linux で安全な実装手段がない場合は、UI に以下の意味の表示を行う。

```text
カクヨムアカウント連携は現在この OS では利用できません
```

特定 WebView パッケージのバージョンをこの文書だけを根拠に固定しない。

---

## 5.2 `KakuyomuSessionRepository`

新規候補:

```text
lib/repositories/kakuyomu_session_repository.dart
```

責務は以下だけ。

- カクヨムのセッション情報保存
- セッション情報取得
- セッション削除
- 認証付き HTTP 用 Cookie header 構築

保存には既存依存の `flutter_secure_storage` を使用する。

例:

```text
kakuyomu_session_cookies
kakuyomu_username
```

Cookie は JSON として保存してよい。

保存対象はカクヨム本体へ送信すべき Cookie のみに限定する。

Google 等の外部認証ドメインの Cookie をまとめて保存しない。

### 禁止

```dart
debugPrint(cookie.toString());
debugPrint(cookieHeader);
```

のような秘密情報ログを作らない。

---

## 5.3 カクヨムログイン画面

新規候補:

```text
lib/screens/kakuyomu_login_page.dart
```

カクヨム公式ログインページを WebView で表示する。

ログイン操作自体はユーザーへ任せる。

Cookie が1個存在するだけでログイン成功判定してはいけない。

ログイン後に、実際にログイン必須ページへアクセスできるか、またはログイン済みユーザー固有 UI が確認できることを使って判定する。

ログイン確認後に必要なセッション情報だけを Secure Storage へ保存する。

---

## 5.4 `KakuyomuAuthService`

新規候補:

```text
lib/services/kakuyomu_auth_service.dart
```

最低限:

```dart
Future<bool> isSessionValid();
Future<void> logout();
```

を提供する。

`isSessionValid()` は保存済みセッションでログイン必須ページへアクセスし、ログインページへ戻されないことなど、実サイトで確認した条件で判断する。

ログアウト時は Novelty に保存したセッション情報を必ず削除する。

---

## 5.5 Phase 2 でやってはいけないこと

まだ以下を実装しない。

- カクヨムフォロー同期
- 閲覧履歴同期
- 読書用ラベル同期

ログイン・ログアウト・セッション確認までで一度止める。

---

# Phase 3: カクヨムのフォロー作品を Novelty へ取り込む

## 6. Phase 3 の目的

最初は一方向だけ実装する。

```text
Kakuyomu
   ↓
Novelty Library
```

Novelty → Kakuyomu のフォロー追加は次の Phase に分離する。

---

## 6.1 先に fixture を作る

実装より先に、ログイン済み状態のフォロー作品一覧ページの HTML を確認する。

個人情報を除去した fixture を以下へ保存する。

```text
test/fixtures/kakuyomu/
```

例:

```text
followed_works_page.html
followed_works_empty.html
followed_works_broken.html
login_required.html
```

実際の HTML を確認する前に selector を決めない。

---

## 6.2 Remote Library モデル

必要なら新規:

```text
lib/models/remote_library_entry.dart
```

最初は必要最小限にする。

```dart
class RemoteLibraryEntry {
  const RemoteLibraryEntry({
    required this.source,
    required this.workId,
  });

  final NovelSource source;
  final String workId;
}
```

タイトル等は既存の `KakuyomuSite.fetchNovelInfo()` から取得する。

---

## 6.3 `KakuyomuAccountSyncAdapter`

新規:

```text
lib/sites/kakuyomu/kakuyomu_account_sync_adapter.dart
```

`AccountSyncAdapter` を実装する。

Phase 3 では `pullLibrary()` を完成させる。

未実装メソッドについては、呼ばれたときにアプリをクラッシュさせない設計にする。

### `pullLibrary()` の処理順

```text
1. 保存済みカクヨムセッション取得
2. セッション無し → 0
3. フォロー一覧取得
4. workId 抽出
5. 各 workId の NovelInfo を既存 KakuyomuSite から取得
6. Novels 保存
7. LibraryEntries へ追加
8. 同期件数を返す
```

既に Novelty ライブラリへ存在する作品を重複追加しない。

---

## 6.4 Phase 3 テスト

実サイトへ接続するユニットテストは禁止。

fixture と Fake / Mock を使用する。

最低限:

- 0件
- 1件
- 複数件
- 不正 HTML
- ログイン切れ
- 既存ライブラリ作品との重複

を確認する。

---

# Phase 4: Novelty → カクヨム フォロー追加・解除

## 7. 最重要ルール

ここで未確認 URL を想像してはいけない。

例えば以下のようなものを根拠なく作らない。

```text
POST /api/follow
POST /api/works/{id}/follow
GraphQL mutation FollowWork
```

---

## 7.1 実際の Web 操作を調査する

カクヨムで実際に以下を確認する。

```text
未フォロー作品
↓
フォロー
↓
フォロー中
```

確認可能ならネットワークリクエストも調査する。

最低限、以下を記録する。

- HTTP method
- URL
- 必要 Header
- CSRF token 取得元
- body / query
- 成功時レスポンス
- 解除方法

結果を以下へ記録する。

```text
docs/kakuyomu_html/account_sync.md
```

---

## 7.2 Dio で直接実装してよい条件

以下がすべて確実に確認できた場合だけ直接 HTTP 実装してよい。

- 正確な URL
- 正確な HTTP method
- 正確な CSRF 処理
- 正確な Cookie
- 正確な成功判定

1つでも不明なら、推測で実装しない。

必要に応じて、ログイン済み WebView で通常 UI と同じ操作を行う方式を検討する。

---

## 7.3 `addToRemoteLibrary()`

期待動作:

```text
Novelty でライブラリ追加
↓
ローカル DB へ追加
↓
Kakuyomu adapter
↓
未ログイン? → notLoggedIn
↓
すでにフォロー済み? → success
↓
フォロー操作
↓
成功確認
↓
success
```

remote 操作失敗でローカル追加を消さない。

---

## 7.4 `removeFromRemoteLibrary()`

期待動作:

```text
フォロー状態確認
↓
未フォロー → success
↓
フォロー中
↓
フォロー解除
↓
解除確認
↓
success
```

Phase 1 で定義した削除失敗時のローカル挙動を維持する。

---

# Phase 5: 読書位置同期

## 8. Phase 5 の目的

Novelty の読書履歴をサイト共通の進捗データとして扱えるようにする。

カクヨムについては、話数だけでなく実際のエピソード識別子を使用する。

---

## 8.1 ReadingProgress モデル

必要なら新規:

```text
lib/models/reading_progress.dart
```

例:

```dart
class ReadingProgress {
  const ReadingProgress({
    required this.source,
    required this.workId,
    required this.episodeIndex,
    this.remoteEpisodeId,
    required this.updatedAt,
  });

  final NovelSource source;
  final String workId;
  final int episodeIndex;
  final String? remoteEpisodeId;
  final DateTime updatedAt;
}
```

既存モデルと重複する場合は、新規型を無理に増やさず既存設計へ統合する。

---

## 8.2 カクヨムの remote episode ID

カクヨムの実エピソード識別子は、既存の `EpisodeListEntries.url` など、実際に保存している URL から取得する。

話数から ID を推測してはいけない。

---

## 8.3 Novelty → Kakuyomu を先に作る

Novelty で第 N 話を開いたら以下の順番にする。

```text
ローカル ReadingHistory 保存
↓
KakuyomuAccountSyncAdapter.pushReadingProgress()
```

remote 側更新は非同期で実行する。

実サイト調査の結果、カクヨム側が通常のエピソード閲覧によって履歴を更新する仕様なら、ログイン済み WebView で該当ページを通常閲覧させる方法を優先して検討する。

必ず実機で「カクヨム側の続きから読む情報が実際に更新された」ことを確認する。

---

## 8.4 Kakuyomu → Novelty は後から作る

先にログイン済み閲覧履歴ページの fixture を取得する。

以下が確実に取得できるか確認する。

- workId
- 最後に読んだ episode ID
- 最終閲覧日時

取れない情報を推測しない。

---

## 8.5 競合ルール

単純に「話数が大きい方」を常に正としない。

remote 側にも時刻がある場合は、原則として `updatedAt` が新しい方を採用する。

remote 側に時刻が存在しない場合のみ、episode 位置を比較する fallback を検討する。

競合ルールはテストで固定する。

---

# Phase 6: アカウント UI の共通化

## 9. もっと画面

現在のなろう専用アカウント UI を、サイトごとに独立した小さな Widget へ分離する。

例:

```text
lib/widgets/accounts/narou_account_tile.dart
lib/widgets/accounts/kakuyomu_account_tile.dart
```

表示イメージ:

```text
アカウント

小説家になろう
  username
  同期
  ログアウト

カクヨム
  username
  同期
  ログアウト
```

`MorePage` に以下のようなサイト分岐を増やし続けない。

```dart
if (narou) ...
if (kakuyomu) ...
if (anotherSite) ...
```

---

# 10. カクヨム同期 MVP 完了条件

以下がすべて成立したら同期 MVP 完了。

- なろう同期が壊れていない
- カクヨムログイン
- カクヨムログアウト
- Kakuyomu → Novelty フォロー同期
- Novelty → Kakuyomu フォロー追加
- Novelty → Kakuyomu フォロー解除
- Novelty → Kakuyomu 読書位置連携
- 通信失敗でも本文を読める
- Cookie / token のログ漏洩なし
- 全テスト成功
- lint 0

---

# Phase 7: 未読管理

## 11. 基本計算

既存データとして利用可能な場合は以下から未読数を計算する。

```text
ReadingHistory.lastEpisodeId
Novels.generalAllNo
```

概念:

```dart
max(0, totalEpisodes - lastEpisode)
```

`null`、負数、不整合値をそのまま UI へ出さない。

## 11.1 Library UI

作品ごとに例えば以下を表示する。

```text
未読 13話
```

0話なら非表示、または `読了` とする。

## 11.2 Filter

候補:

- すべて
- 未読あり
- 読了
- 未読

既存 Library filter 設計へ統合する。

---

# Phase 8: 「続きを読む」

`ReadingHistory.viewedAt` の降順で最近読んだ作品を表示する。

例:

```text
続きを読む

作品タイトル
第123話
23分前
```

タップすると `lastEpisodeId` から直接 `NovelPage` を開く。

---

# Phase 9: 新着エピソードフィード

目的:

```text
今日
12:04 作品A 第101話
10:35 作品B 第52話
```

のような更新フィードを作る。

必要なら検出済みエピソード用テーブルを追加する。

最低限:

```text
source
workId
episodeId
detectedAt
publishedAt
```

primary key は以下。

```text
source + workId + episodeId
```

同じ更新を二重登録しない。

更新検出は、既存メタデータ更新処理で旧 `generalAllNo` と新 `generalAllNo` を比較する方式をまず検討する。

---

# Phase 10: 次話プリフェッチ

第 N 話を読んでいる場合、N+1、N+2 などの本文をバックグラウンド取得する。

条件:

- オフラインモードでは実行しない
- 既にキャッシュ済みなら取得しない
- 同一 episode の多重取得を防止する
- ユーザーが実際に要求した本文取得を優先する
- プリフェッチ失敗は読書画面へエラー表示しない

---

# Phase 11: 新着話の自動ダウンロード

設定候補:

```text
新着話を自動ダウンロード
Wi-Fiのみ
常に
```

ネットワーク種別判定に新しい依存パッケージが必要な場合は、依存導入を別の小さな作業単位に分ける。

適当な Wi-Fi 判定を自作しない。

---

# Phase 12: ローカルタグ / コレクション

サイト固有ラベルとは別に Novelty ローカルで管理する。

テーブル例:

```text
Collections
  id
  name
  createdAt
```

```text
CollectionEntries
  collectionId
  source
  workId
```

1作品に複数タグを付けられるようにする。

例:

- 読書中
- 積読
- お気に入り
- 一時停止
- 読了

---

# Phase 13: カクヨム読書用ラベル同期

ローカル Collections が安定した後に実装する。

最初からカクヨムのラベルと Novelty のローカル分類を同じ DB テーブルへ混ぜない。

概念:

```text
Novelty Collection
        ↕
Kakuyomu Reader Label
```

remote ID 等が必要なら同期用データとして別管理する。

---

# Phase 14: 作品内全文検索

SQLite FTS を使用する。

検索対象は **ダウンロード済み本文だけ** にする。

ネット上の作品全体を検索する機能にはしない。

結果例:

```text
第12話
「アリシアは振り返った……」

第37話
「アリシアとの約束を……」
```

タップで該当話へ移動する。

---

# Phase 15: ハイライト・メモ

必要なら新規テーブル:

```text
Annotations
```

最低限の候補:

```text
id
source
workId
episodeId
startOffset
endOffset
selectedText
note
createdAt
updatedAt
```

最初から横書き・縦書きの選択 UI を同時完成させようとしない。

まずデータモデルと、実装しやすい表示モードから安定させる。

---

# Phase 16: 読書統計

ローカルだけで集計する。

外部サーバーへ送信しない。

例:

```text
今日
12話

今週
87話

今月
315話
```

最初は「話数」「読書日数」程度から始めてよい。

文字数集計は後から追加可能。

---

# Phase 17: 自動スクロール

まず横書きから実装する。

最低限:

```text
開始
停止
速度
```

本文データそのものは変更せず、既存 ScrollController 等を利用して一定速度で移動させる。

---

# Phase 18: TTS

最後に別 PR で実装する。

OS 標準 TTS の利用を基本とする。

最低限:

- 再生
- 停止
- 一時停止
- 速度
- 次話へ自動移動

ルビについて、表示文字と読み文字のどちらを TTS に渡すかは既存 `NovelContentElement` の構造を確認して決める。

推測でルビを削除しない。

---

# 12. 共通テストルール

## 12.1 本番サイトへ接続するユニットテストは禁止

以下を利用する。

- Fake
- Mock
- fixture HTML
- Fake HttpClientAdapter

## 12.2 HTML Parser には fixture を用意する

HTML 構造依存処理では最低限、以下を考慮する。

- 正常
- 空
- 必要要素欠落
- ログイン切れ

実サイト HTML を fixture 化する場合は個人情報、Cookie、token を含めない。

---

# 13. セキュリティ確認

実装後、少なくとも以下のような検索で秘密情報ログを確認する。

```bash
grep -R "debugPrint.*cookie" lib test || true
grep -R "print.*cookie" lib test || true
grep -R "password.*debugPrint" lib test || true
```

この検索だけで安全だと断定せず、変更差分も目視確認する。

---

# 14. 各 Phase 終了時に必ず実行

```bash
mise run codegen
mise run format
mise run test
mise run check
```

すべて成功しない限り「完了」と報告しない。

ドキュメントのみを変更した Phase でコード生成が不要な場合でも、少なくとも `mise run test` と `mise run check` の結果を確認する。

---

# 15. 実装中の禁止事項

以下を行わない。

1. `dynamic` で型問題を隠す。
2. `catch (_) {}` だけで重要なエラーを握り潰す。
3. テストを削除して通す。
4. lint rule を無効化して通す。
5. `// ignore:` を安易に追加する。
6. 既存なろう機能を削って簡単にする。
7. カクヨム処理を `NarouSyncService` へ追加する。
8. `KakuyomuSite` にログイン UI を入れる。
9. Widget から直接 Dio を呼ぶ。
10. Cookie を SharedPreferences へ保存する。
11. Cookie を平文ファイルへ保存する。
12. Cookie / token / password をログに出す。
13. 未確認 API を想像して実装する。
14. robots.txt やサイト側制約を無視して scraper を作る。
15. 同期完了まで本文表示を待たせる。
16. 1つの PR で全 Phase を実装する。
17. カクヨム対応のためになろう側の既存挙動を意図せず変更する。

---

# 16. 目標アーキテクチャ

同期系:

```text
                    UI
                     │
          ┌──────────┴──────────┐
          │                     │
   NovelRepository         NovelPage
          │                     │
          └──────────┬──────────┘
                     │
           AccountSyncRegistry
                     │
        ┌────────────┴────────────┐
        │                         │
NarouAccountSyncAdapter  KakuyomuAccountSyncAdapter
        │                         │
 NarouSyncService          Kakuyomu Auth/Session
                                  │
                             Kakuyomu Web
```

読書データ:

```text
                    Novelty DB
                       │
            ┌──────────┴──────────┐
            │                     │
      LibraryEntries        ReadingHistory
            │                     │
            ↓                     ↓
      Remote Library       Remote Progress
      ┌─────┴─────┐       ┌──────┴──────┐
      │           │       │             │
   Narou      Kakuyomu   Narou       Kakuyomu
 Bookmark      Follow    Shiori     Read History
```

---

# 17. 最重要設計原則: Novelty のローカルデータを読書の基盤とする

外部サイトへの同期に失敗しても、以下は正常に動作させる。

- Novelty 内ライブラリ
- Novelty 内履歴
- Novelty 内本文キャッシュ
- ダウンロード済み作品

remote 状態は「Novelty を利用するための必須条件」にしない。

---

# 18. 各 Phase の作業報告フォーマット

各 Phase 完了後は以下の形式で報告する。

```text
## 実装内容
- ...

## 変更ファイル
- ...

## 追加テスト
- ...

## テスト結果
mise run test: PASS
mise run check: PASS

## 実機確認が必要な項目
- ...

## 未実装
- ...

## 次の Phase
Phase X: ...
```

「たぶん動く」ではなく、以下を分ける。

- 自動テストで確認済み
- fixture で確認済み
- 実機確認済み
- 実機確認がまだ必要

---

# 19. この文書を受け取った AI への最初の依頼

この文書を読んだ直後は、まだコードを変更しないこと。

まず以下を読む。

1. `AGENTS.md`
2. `CONTEXT.md`
3. `DESIGN.md`
4. `docs/architecture/multi_provider.md`
5. `lib/services/narou_sync_service.dart`
6. `lib/repositories/novel_repository.dart`
7. `lib/screens/novel_page.dart`
8. `lib/providers/auth_provider.dart`

その後、**Phase 1 だけの具体的な実装計画**を日本語で提示する。

計画には最低限以下を書く。

- 変更するファイル
- 新規作成するファイル
- 既存挙動を維持するポイント
- 最初に書くテスト
- 実装順序
- Phase 1 の完了条件

承認されるまではコードを変更しない。

**Phase 2 以降はまだ実装しない。**
