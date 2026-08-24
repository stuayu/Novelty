# 既存実装のバグ・設計課題トリアージ

作成日: 2026-08-24
対象: なろう / カクヨム対応済みの現行実装（schemaVersion 22, app v1.4.0+146）
目的: 第3の小説サイト（アルファポリス）を追加するにあたり、事前に潰すべき問題を優先度付きで整理する。

関連:
- ADR-0001（複数プロバイダ対応のためのサイト抽象レイヤー）
- `docs/architecture/adding_a_provider.md`
- `docs/novelty/alphapolis_support_plan.md`

---

## 総評

サイト抽象化レイヤー自体の設計は良好である。

- DBは全テーブルが `(source, work_id[, episode_id])` 複合主キーに移行済みで、ncode前提は解消されている
- ルータは `/novel/:source/:workId`
- 探索画面のランキングタブ、ライブラリのジャンル絞り込み、ソース選択ドロップダウンは
  `NovelSource.values` とレジストリから自動生成されており、サイト追加時に触る必要がない
- `lib/utils/work_url.dart` の `switch` は exhaustive なので、enum追加時にコンパイラが漏れを検出する

したがって第3サイトの追加は「enum 1行 + サイト実装1つ + レジストリ1行 + パーサーパッケージ1つ」で
おおむね通る。ただし以下のP0を先に潰す必要がある。

---

## P0: 第3サイト追加で即座に壊れる（着手前に必須）

### P0-1. `_parseEpisodeBody` の `else` が無条件でカクヨムパーサ

**場所**: `lib/repositories/novel_repository.dart:394-402`

```dart
/// エピソード本文をコンテンツ要素へパースするヘルパーメソッド。
List<NovelContentElement> _parseEpisodeBody(
  NovelSource source,
  String body,
) {
  if (source == NovelSource.narou) {
    return parseNovelContent(body);
  }
  return parseKakuyomuEpisodeBody(body);
}
```

**問題**: 第3サイトのHTMLがカクヨムのパーサに渡される。`NovelSource` の switch ではなく
if/else なのでコンパイルエラーにならず、本文が静かに壊れる。

`fetchNovelInfo` / `fetchToc` / `fetchEpisode` は `NovelSite` のメソッドとして抽象化されているのに、
**本文パースだけが抽象化から漏れている**のが原因。

**対策**:

1. `lib/sites/novel_site.dart` の `NovelSite` に抽象メソッドを追加する。
   他の任意メソッド（`fetchNovelInfo` 等）と違い、**既定実装を持たせない**。
   未実装のサイトがコンパイルエラーになることが狙いである。

   ```dart
   /// エピソード本文HTMLをコンテンツ要素へパースする。
   List<NovelContentElement> parseEpisodeBody(String html);
   ```

2. `lib/sites/narou/narou_site.dart` に実装を追加し、`packages/narou_parser` の
   `parseNovelContent(html)` へ委譲する。
3. `lib/sites/kakuyomu/kakuyomu_site.dart` に実装を追加し、`packages/kakuyomu_parser` の
   `parseKakuyomuEpisodeBody(html)` へ委譲する。
4. `novel_repository.dart` の `_parseEpisodeBody` を削除し、呼び出し元（`downloadSingleEpisode` 等）を
   `_sites[source]!.parseEpisodeBody(body)` に置き換える。

**テスト**:
- `test/sites/narou/narou_site_test.dart` / `test/sites/kakuyomu/kakuyomu_site_test.dart` に
  `parseEpisodeBody` が正しいパーサへ委譲することを検証するケースを追加する
- 既存の本文ダウンロード系テストが緑のままであること

**受け入れ条件**: `mise run test` 全緑、`mise run analyze` 0件（info含む）、
なろう・カクヨム双方で本文表示に回帰がないこと。

### 参考: 同型だが安全な分岐

以下も「narouなら `ApiService`、それ以外は `NovelSite`」という構造だが、第3サイトが
`NovelSite` を正しく実装していれば動作する。今回は変更しない。

- `lib/repositories/novel_repository.dart:347`（`_fetchEpisode`）
- `lib/repositories/novel_repository.dart:366`（`_fetchNovelInfo`）
- `lib/repositories/novel_repository.dart:381`（`_fetchEpisodeList`）
- `lib/domain/search_state.dart:215`
- `lib/providers/ranking_provider.dart:152-156`

根本原因は `NarouSite` が空殻で、なろうの読書コアが `ApiService` にあること（ADR-0001の決定5）。
`NarouSite` への統合は将来のフェーズの課題として据え置く。

---

## P1: 既存2サイトの重大バグ（アルファポリス実装と並行して修正）

マルチサイト化とは独立した問題だが、実害が大きい。

### C-2. シークレットモード中もリモートへ読書位置を送信している

**場所**: `lib/screens/novel_page.dart:219-241`

```dart
void _updateHistory(WidgetRef ref, NovelInfo novelInfo, int episode) {
  unawaited(
    ref.read(novelRepositoryProvider).addToHistory(...),   // isIncognito を尊重する
  );

  final adapter = ref.read(accountSyncRegistryProvider)[source];
  if (adapter != null) {
    unawaited(
      adapter.pushReadingProgress(workId: workId, episode: episode),  // 尊重しない
    );
  }
}
```

ローカル側の `NovelRepository.addToHistory` は `lib/repositories/novel_repository.dart:308` で
`isIncognito` を見て早期 return するが、直後の `pushReadingProgress` にはガードがない。
結果、**シークレットモード中でもなろうのしおり・カクヨムの「続きから読む」がサーバ側に記録される**。
ユーザーの期待と真逆の挙動である。

`isOfflineMode` のガードも同様に存在しないため、オフラインモード設定中も通信が発生する。

**対策**: `pushReadingProgress` の呼び出しを `isIncognito` / `isOfflineMode` でガードする。
**回帰防止テストを必ず追加すること**（テストが無かったことが見逃しの原因である）。

優先度は最上位。修正自体は数行で済む。

### C-1. Dio のタイムアウトが全く設定されていない

`connectTimeout` / `receiveTimeout` / `sendTimeout` / `BaseOptions` の grep ヒットが **0件**。
素の `Dio()` が以下10箇所以上で個別に生成されており、サーバが応答を返さない場合に無期限待機する。

| ファイル:行 |
|---|
| `lib/services/api_service.dart:55` |
| `lib/services/narou_sync_service.dart:78` |
| `lib/sites/kakuyomu/kakuyomu_site.dart:76` |
| `lib/sites/kakuyomu/kakuyomu_history_client.dart:47` |
| `lib/services/kakuyomu_graphql_service.dart:100` |
| `lib/services/kakuyomu_reading_progress_service.dart:106` |
| `lib/services/kakuyomu_auth_service.dart:48` |
| `lib/services/narou_auth_service.dart:45`, `:108`, `:141` |
| `lib/sites/kakuyomu/kakuyomu_account_sync_adapter.dart:126` |

モバイル回線では `NovelPage` のローディングが永久に回り続ける。
また `NarouAuthService` は1リクエストごとに `final dio = Dio();` を新規生成しており、
コネクションプールが効いていない。

**対策**: `BaseOptions`（タイムアウト + 統一User-Agent）を持つ共通の Dio ファクトリを1つ作り、
全箇所を差し替える。後述の M-5 と同時に解決できる。

### C-3. `customStatement` による書き込みが Drift のストリームを更新しない

Drift の公式ドキュメントは「データを更新する custom statement には `customInsert` /
`customUpdate` を使うか、`markTablesUpdated` を手動で呼べ」と明記している。
本リポジトリには `markTablesUpdated` も `customUpdate` も一切存在しない。

**該当箇所1**: `lib/database/database.dart:1645-1655`（`mergeKakuyomuReadingHistories`）

```dart
await customStatement(
  'INSERT INTO reading_history '
  '(source, work_id, last_episode_id, viewed_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?) ON CONFLICT(source, work_id) DO UPDATE SET ...',
```

`watchHistory()`（履歴画面）、`watchLastReadEpisode()`（`novel_repository.dart:960`、しおり位置表示）、
`groupedHistoryProvider` が**同期直後に更新されない**。アプリを再起動するまで反映されない。

**該当箇所2**: `lib/database/database.dart:1745-1760`（`updateEpisodeContent` の
`episode_list_entries` upsert）。subtitle / url / published_at の更新が `watchEpisodesRange` に
通知されない。直後の `episodeContents` 側の drift insert が同一クエリの `readsFrom` に
含まれるため偶然マスクされているが、依存関係が変われば壊れる。

**対策**: 2箇所を `customUpdate(..., updates: {readingHistory})` 等に置換する。

### C-6. `pullLibrary` の N+1 ネットワークストーム

**場所**: `lib/sites/kakuyomu/kakuyomu_account_sync_adapter.dart:221-245`

```dart
for (final entry in parsed.entries) {
  ...
  await _syncRemoteReadingProgress(entry.workId);   // 1件ごとに /works/{id} を全文取得
}
```

`_syncRemoteReadingProgress` → `fetchRemoteState` →
`KakuyomuReadingProgressService._fetchRemoteState`（`kakuyomu_reading_progress_service.dart:216-235`）は
**レートリミッタを一切通らない**。さらに目次未取得なら `KakuyomuSite.fetchToc`（作品ページ + sidebar の
2リクエスト）も走る。

フォロー500件のユーザーなら1回の同期で500〜1500リクエストがノンストップで飛ぶ。
`KakuyomuSite` 側で1秒間隔を守っている努力が、この経路で完全に無効化されている。

`KakuyomuHistoryClient._fetchPage`（`kakuyomu_history_client.dart:114-135`）も同様に
レートリミッタを通らず、かつ `resume_reading` の解決で1エントリあたり1リクエストを追加している。

### H-1. `KakuyomuRateLimiter.wait()` が並行呼び出しに無防備

**場所**: `lib/sites/kakuyomu/kakuyomu_site.dart:32-42`

2つの `Future` が同時に `wait()` を呼ぶと、両方が同じ `elapsed` を読んで同じ遅延を待ち、
**同時にリクエストを発射する**。ミューテックス（`Future` チェーン）による直列化が必要。

初回呼び出し（`_stopwatch.isRunning == false`）が待たずに素通りする点も、
`KakuyomuSite` と `KakuyomuAccountSyncAdapter`（`:136`）が別インスタンスを持っている現状と
相まってバースト要因になっている。

**対策**: C-6 / M-6 とまとめて、アプリ横断で単一のレートリミッタに集約する。

### H-2. Secure Storage への並列書き込み

`lib/repositories/auth_repository.dart:50-52` は自ら次のように警告している。

> flutter_secure_storage の Windows 実装は全キーを単一ファイルへ読み込み→更新→保存で
> 書き込むため、並列に書き込むと後勝ちで他のキーが消える。必ず直列に書き込むこと。

にもかかわらず `lib/services/narou_auth_service.dart:88-92` が並列実行している。

```dart
await Future.wait([
  authRepository.saveNarouid(narouid),
  authRepository.saveUsername(username),
  authRepository.saveSessionCookies(ks2: ks2, ses: ses, userl: userl),
]);
```

Windows でログイン情報が欠損する典型パターン。`saveSessionCookies` の内部が直列でも、
外側で3本を並列に走らせては意味がない。

**対策**: 順次 `await` に変更する。

### H-4. `upsertEpisodes` の `insertOrReplace` が目次メタデータを破壊する

**場所**: `lib/database/database.dart:1699-1709`（`InsertMode.insertOrReplace`）

Companion に含まれないカラムは NULL に落ちる。呼び出し側が2系統あり挙動も異なる。

- `lib/repositories/novel_repository.dart:930-940`（`_refreshEpisodeList`）:
  `Value(e.subtitle ?? '')`, `Value(e.url ?? '')` → **null を空文字で上書き**
- `lib/repositories/novel_repository.dart:761-772`（`fetchEpisodeList`）:
  `Value(e.subtitle)` → **null で上書き**

一方 `updateEpisodeContent` は `COALESCE(excluded.url, episode_list_entries.url)` で保護している
（`database.dart:1750`）。この非対称性のため、目次パースが href を取れなかったとき
（`kakuyomu_site.dart:434` の `_toAbsoluteUrl(link?.attributes['href'])` が null）に
既存の正しい URL が `''` で潰れる。`''` は NULL ではないので `COALESCE` による復旧も効かない。

結果、`getEpisodeUrl` が `''` を返し、`kakuyomu_account_sync_adapter.dart:354` の
`episodeUrl.isEmpty` で常に false となり、**カクヨムの読書位置同期が黙って死ぬ**。

同じパターンが `kakuyomu_account_sync_adapter.dart:286-300` にもある。

### H-5. パース失敗が「ダウンロード成功」として記録される

**場所**: `lib/repositories/novel_repository.dart:430-448`

```dart
final ep = await _fetchEpisode(source, workId, episode);
final content = ep.body != null ? _parseEpisodeBody(source, ep.body!) : <NovelContentElement>[];
await _db.updateEpisodeContent(..., content: content, ...);
return true;   // content が空でも true
```

`KakuyomuSite._parseEpisode`（`kakuyomu_site.dart:456`）は `.widget-episodeBody` が
見つからないと `body: null` を返す。`ApiService.fetchEpisode`（`api_service.dart:499-506`）も
`.p-novel__text` が変わると空文字列を返す。

**HTML構造の変更やログイン要求ページを掴んだ場合、例外は出ず、空本文が「成功」として保存され、
`revisedAt` も更新されるため以降キャッシュヒットして再取得もされない。**

一方 `_watchDownloadSummaries`（`database.dart:2022-2028`）は空コンテンツを `failure_count` に
数えている。同じデータがリポジトリでは成功、DB集計では失敗という二重管理になっている。

既存 issue #186（ダウンロード済みエピソードのアイコンが消える）と関連している可能性がある。

**対策**: 空本文を失敗として扱い、`revisedAt` を更新しない。判定基準をリポジトリとDB集計で揃える。

### M-5. User-Agent の不統一・詐称

| 場所 | 値 |
|---|---|
| `lib/services/api_service.dart:45` | Chrome/143 |
| `lib/services/narou_auth_service.dart:12` | **Chrome/126**（同じなろうなのに別バージョン） |
| `kakuyomu_site.dart:80` / `kakuyomu_graphql_service.dart:141` / `kakuyomu_auth_service.dart:70` / `kakuyomu_account_sync_adapter.dart:169` | Chrome/143 |
| `kakuyomu_history_client.dart:121`, `kakuyomu_reading_progress_service.dart:228` | **`'Mozilla/5.0'` だけ**（書き漏れ） |

いずれもブラウザを詐称しており、アプリ名・連絡先を名乗っていない。
なろうAPI利用規約・カクヨムのスクレイピングマナーの観点からは
`Novelty/1.4.0 (+contact)` 形式が望ましい。少なくとも定数を1箇所に集約すべきである。

**対策**: C-1 の共通 Dio ファクトリに統合する。

### M-6. リトライ・指数バックオフが皆無

`retry` / `Interceptor` の grep ヒットが0件。429 / 503 を受けても即座に失敗扱いになる。

`downloadNovel`（`lib/repositories/novel_repository.dart:603-626`）は失敗した話も含めて
全話をノーウェイトで連続リクエストする。`downloadSingleEpisode` の間にレート制限はなく、
なろう経路は `ApiService` を通るため `KakuyomuRateLimiter` すら通らない。
1000話の作品をダウンロードすると1000リクエストが全力で飛ぶ。

**対策**: C-1 の Dio ファクトリに指数バックオフの Interceptor を載せ、
H-1 で集約したレートリミッタをダウンロードループにも通す。

---

## P2: マルチサイト観点の残穴（アルファポリス追加時に顕在化）

### `NovelDownloadSummary` に `source` がない

`lib/models/novel_download_summary.dart:8,15` は `ncode` フィールドのみを持つ。
SQL 自体は `GROUP BY e.source, e.work_id` と正しくソース別に集計している
（`database.dart:1996-2008`）のに、モデルで `source` を捨てている。

結果、UI 側で `NovelSource.narou` をハードコードせざるを得なくなっている。

- `lib/database/database.dart:2022-2024`
- `lib/screens/download_manager_page.dart:142`, `:156`, `:251`

**アルファポリスのダウンロードが管理画面で誤表示されるため、Phase 3 完了までに修正が必要。**

### カクヨム閲覧履歴同期が未完成

1. **`remote_reading_histories` が Drift スキーマ外**:
   `database.dart:1219-1231`（`_migrateToV22`）で生SQLのみで作成されており、
   `@DriftDatabase(tables: [...])`（`database.dart:575-583`）に含まれていない。
   型安全性・`readsFrom` によるストリーム連携・スキーマ検証がすべて効かない。
2. **読み出し箇所が存在しない**: 参照はすべて `_migrateToV22` と
   `mergeKakuyomuReadingHistories` 内のみ。同期して保存したデータがUIで一切使われていない。
3. **目次キャッシュ済みの作品でしか機能しない**: `database.dart:1618-1626` で
   `localEpisodeId == null` の場合に黙って `continue` する。
   カクヨムで読んだがアプリで開いたことがない作品の履歴は一切反映されない。
4. **孤児レコードが発生する**: `watchHistory()`（`database.dart:1655-1663`）は `novels` と
   INNER JOIN しているが、`mergeKakuyomuReadingHistories` は `ensureNovelExists` を呼んでいない
   （`narou_sync_service.dart:119` は呼んでいる）。

### `mergeKakuyomuReadingHistories` がコアDBにサイト固有型を持ち込んでいる

`lib/database/database.dart:1569-1650`。DB層が
`lib/sites/kakuyomu/kakuyomu_history_parser.dart` と `lib/utils/kakuyomu_uri.dart` を
import しており（`database.dart:13`, `:15`）、`KakuyomuHistoryEntry` を直接受け取る。

「リモート閲覧履歴のマージ」というサイト共通の概念が、カクヨム型に固定されている。
共通モデル `lib/models/remote_library_entry.dart` が既にあるのに使われていない。

### 認証・アカウントUIに横断抽象がない

- `lib/screens/more_page.dart:110-120` がアカウントタイル（`NarouAccountTile` / `KakuyomuAccountTile`）を
  直書きで列挙している。`NovelSource.values` 駆動ではない
- `AccountSyncAdapter`（`lib/sites/account_sync_adapter.dart:19-42`）に
  `isLoggedIn` / `login` / `logout` がなく、認証状態のサイト横断抽象が存在しない
- `lib/providers/auth_provider.dart:69`, `:89` が `NovelSource.narou` 決め打ち
- なろうは `authProvider`（`User?`）、カクヨムは `kakuyomuSessionValidProvider`（`bool`）と
  型も系統も別
- カクヨムのログイン画面がルータ未登録。`kakuyomu_account_tile.dart:64-68` で
  生の `Navigator.push` を使っており、ログイン導線がサイト間で非対称

アカウント同期フェーズに着手する前に整理すべき。

### その他

- `lib/screens/library_page.dart:191` — source が null（「すべて」）のとき
  `NovelSource.narou` のジャンルへフォールバックしている
- `lib/widgets/sort_selection_sheet.dart:58-59` — `ncodeasc` / `ncodedesc`（Nコード順）が
  サイト分岐なしで常時表示される
- `lib/widgets/search_modal.dart:120`, `:328`, `:351` — サイト別の条件ブロックが直書きで、
  サイト追加のたびに線形に増える（allow-list型なので第3サイトは安全側に倒れる）
- `lib/domain/novel_enrichment.dart:26-32` — カバー画像URLがなろう専用
  （`img.syosetu.com`）。現状lib内から未参照
- `lib/models/library_toggle_result.dart:11,17` — フィールド名が `narouSyncFailed` だが
  カクヨムでも使われている
- `lib/utils/app_constants.dart:2-56` — `genreList` / `novelTypes` / `novelOrders` が
  なろう定数としてレガシー残存（`NarouSite.genres` と重複）
- `lib/screens/search_page.dart` — `NovelSource` を一切扱わず、ルータにも未登録
- `packages/riverpod_swr/` が空ディレクトリの残骸。`custom_lint.log` がコミットされている
- `AGENTS.md:3` がまだ「なろう専用ビューア」と記述しており README と乖離。
  `DESIGN.md` 全体がマルチサイト化以前の記述

### テストが無い領域

| 対象 | 状況 |
|---|---|
| マイグレーション v19→v20 / v20→v21 / v21→v22 | 各段とも**なし**（v16/v17/v18/v19 のみ存在） |
| 旧版→v22 の通しマイグレーション | **なし** |
| `lib/sites/kakuyomu/kakuyomu_history_parser.dart`（203行） | 専用テスト**なし**。`_findLastReadAt` の「N月N日閲覧」年跨ぎがノーガード |
| incognito / offline 時のリモート同期抑止 | **なし**（C-2 が見逃された原因） |
| `lib/providers/auth_provider.dart` | **なし** |
| `lib/repositories/kakuyomu_session_repository.dart` | **なし**。Cookie の破損JSON・期限切れフィルタが未検証 |
| `RankingNotifier` の並行 refresh レース | 未検証 |
| Dio タイムアウト / リトライ | 実装自体が存在しない |

---

## 推奨対応順序

1. **P0-1**（第3サイト着手の前提。単独PR）
2. **C-2**（プライバシー。実質数行）
3. **C-1 + M-5**（共通 Dio ファクトリ）
4. **C-3**（`customUpdate` への置換、2箇所）
5. **H-1 + C-6 + M-6**（レート制限をアプリ横断で1つに集約 + バックオフ）
6. **H-2 / H-4 / H-5**（データ破壊系）
7. **P2 の `NovelDownloadSummary`**（Phase 3 完了までに必要）
8. **マイグレーション通しテストの追加**
