# macOS Share サンプルアプリ実装計画書 v1

- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `MacLibraryExample`
- 対象設計書: artifact/designs/share/2026-07-11-macos-share-design.md
- 対象実装結果: artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md
- 対象実装レビュー: artifact/reviews/share/2026-07-11-macos-share-implementation-feature-review-v3.md
- 作成日: 2026-07-11
- 出力言語: 日本語

---

## 1. 前提情報（設計書・実装結果由来）

### 1.1 in-scope 機能（サンプルで見せる対象）

- ピッカー方式の共有: `MacShareManager.share(content:)`（async throws）/ `share(content:completion:)`（callback）
- 個別サービス直接実行: `shareViaService(content:serviceName:)`（async throws）/ `share(content:serviceName:completion:)`（callback）
- サービス可否照会: `canPerform(content:serviceName:)`
- 共有アイテム種別: `.text` / `.url` / `.imageFile(path:)` / `.file(path:)`
- メタ設定: `recipients` / `subject`（direct モードのみ有効）、`excludedServiceTitles`（picker モードのみ、best-effort）

### 1.2 公開 API と入力制約

| API | 形式 | 戻り値/結果 | 主な制約 |
| --- | --- | --- | --- |
| `share(content:) async throws -> ShareResult` | native | `ShareResult(completed, serviceName)` | picker 表示。`mouseDown` 起点必須（要検証・§実装結果 v2） |
| `shareViaService(content:serviceName:) async throws -> ShareResult` | native | 同上 | `serviceName` は raw `NSSharingService.Name`。空名は `serviceUnavailable` |
| `canPerform(content:serviceName:) async throws -> Bool` | native | `Bool` | items 空なら false |
| `ShareContent(items:recipients:subject:excludedServiceTitles:)` | 入力型 | - | `items` 空 → `noValidItems`。本文=`.text`、添付=`.file`（`messageBody`/`attachmentFileURLs` は readonly のためモデルに無い） |

- サンプルアプリはネイティブ Swift 呼び出し元であるため、common.md / mac.md の方針に従い **`async throws` 版を優先**して使用する（`Button` action は同期のため `Task { await ... }` で橋渡し）。

### 1.3 エラー契約（errorCode / errorMessage）

| ケース | errorCode | errorMessage |
| --- | --- | --- |
| `noValidItems` | 1401 | No shareable items were provided. |
| `invalidURL` | 1402 | Invalid URL: <value>. |
| `imageLoadFailed` | 1403 | Failed to load image at path: <path>. |
| `fileNotFound` | 1404 | File not found at path: <path>. |
| `noAnchorView` | 1405 | No key window available to anchor the sharing picker. |
| `serviceUnavailable` | 1406 | Sharing service unavailable: <name>. |
| `presentationFailed` | 1407 | Failed to share: <detail>. |
| `alreadyInProgress` | 1408 | A share operation is already in progress. |
| `unknown` | 1499 | An unknown share error occurred: <detail>. |

- サンプルでは `ShareError` を捕捉して `errorCode` / `errorMessage` を結果領域に表示する。ネイティブ `async throws` 版は型付き `ShareError` を throw するため、`catch let error as ShareError` で `errorCode`/`errorMessage` を取り出す。

### 1.4 テスト観点（正常系/異常系/境界値）

- 正常系: text / url / image / file / 複数アイテム / direct service（Mail 等）/ canPerform true
- 異常系: items 空（`noValidItems`）/ 不正 URL（`invalidURL`）/ 不在ファイル（`fileNotFound`）/ 不在画像（`imageLoadFailed`）/ 不明サービス名（`serviceUnavailable`）
- 境界値: キャンセル（`completed=false`）、picker 未選択と共有完了の区別

### 1.5 不足前提（勝手に要件追加しない範囲）

- **mouseDown 実UI検証は未完了（実装結果 v2 の未解決事項）**。サンプルアプリはボタン押下起点で picker を呼ぶことで「実ユーザークリック起点で picker を実機確認するための導線」を提供するが、`Task {}` 経由呼び出しが `mouseDown` コンテキストを保持する保証はなく、安定表示自体はサンプルでは保証しない。**実機 / 実 UI での mouseDown 検証は次工程の手動確認で扱い、本サンプル設計レビューの pass/fail には含めない**（実装レビュー v3 の切り分けに従う）。
- 直接実行（`shareViaService`）で使う `serviceName` の具体値（例: `com.apple.share.Mail.compose`）は環境・SDK 依存。サンプルでは代表値をボタンに埋め込むが、環境により `serviceUnavailable` になり得る点を手動確認観点に残す（要検証）。
- サンドボックス（`MacLibraryExample.entitlements`）でのファイル/AirDrop 共有に必要な entitlement は本計画では変更しない。既存 entitlement で不足する場合は要検証として記録する。
- サンプル画像は **既存の `test-image` アセット（`Assets.xcassets/test-image.imageset`）を再利用する**。新規アセットは追加しない（下記 4.3 / 5.3 参照）。

---

## 2. 既存サンプルコードの深掘り結果

### 2.1 相互参照ペアと主参照

- 対象OS = macOS。デスクトップペアは Windows だが、Windows 側に Share サンプルは未確認。**機能的に最も近い iOS の `ShareSampleView.swift` を UI 構成の主参照**とし、**画面規約・命名・ボタンスタイルは対象OS既存の `MacLibraryExample`（`NotificationSampleView` / `DialogSampleView` / `ContentView`）を優先**する。

### 2.2 既存 UI パターン（踏襲対象）

- `ContentView`: `NavigationStack` + `ScrollView` + `menuCard(title:subtitle:)` によるメインメニュー。`NavigationLink` で各サンプル画面へ遷移。
- 各サンプル画面: 先頭にタイトル（`.title`/`.bold`）+ 結果表示領域（`resultText`、灰背景角丸）+ `ScrollView` 内に `sectionView(title:)` で機能カテゴリ別ボタン群。
- ボタン: `FullWidthPressableButtonStyle`（青背景・全幅・押下アニメ）。`NotificationSampleView` / iOS `ShareSampleView` と共通。
- 結果表示: `updateResult(isSuccess:result:)` が `DispatchQueue.main.async` で `✅`/`❌` プレフィックス付き文言を反映。
- ログ: 各操作先頭で `Log.d(TAG, ...)`、結果で `Log.d`/`Log.e`。

### 2.3 iOS ShareSampleView からの流用方針

- セクション構成（Text / URL / Image / File / Combination / Error）をベースに、macOS 向けに再編する。
- サンプルデータ生成ヘルパー（`prepareSampleFileURL` 等）は macOS でも `FileManager.temporaryDirectory` ベースでほぼそのまま流用可能。ただし画像は iOS のように bundle の PNG リソースを直接参照するのではなく、**既存の `test-image` アセットを `NSImage(named:)` で読み → temp ファイル（PNG）へ書き出して `.imageFile(path:)` に渡す**（後述 5.3）。
- `runShare(label:content:)` の async/await + do-catch パターンを踏襲。ただし macOS は `ShareError` を型付きで受けられるため、`catch let error as ShareError` で `errorCode`/`errorMessage` を表示（iOS は `error.localizedDescription` のみだったのを macOS では強化）。

### 2.4 macOS 固有で iOS と変える点（拡張）

- iOS の `previewTitle` / `excludedActivityTypes` は macOS に無い。代わりに:
  - `excludedServiceTitles`（picker のサービス表示名 best-effort 除外）
  - direct モード（`shareViaService` + `recipients`/`subject`）を追加セクションとして見せる
  - `canPerform` 照会ボタンを追加
- iOS は `UIActivityViewController` で単一 API だが、macOS は **picker と direct の 2 モード**があるためセクションで明示的に分ける。

### 2.5 再利用 / 追加 / 変更

- **再利用する既存コンポーネント**:
  - `ContentView.menuCard` 導線パターン、`sectionView`、`FullWidthPressableButtonStyle`、`updateResult`、サンプルデータ生成ヘルパー（iOS 版を移植）
- **追加するコンポーネント**:
  - `ShareSampleView.swift`（新規、`MacLibraryExample` 配下）
  - `ContentView` に Share Example への `NavigationLink` + `menuCard` を 1 つ追加
- **変更するファイルと理由**:
  - `ContentView.swift`: Share サンプルへの導線追加（メニューカード 1 枚）
- **画像アセット**: 新規追加なし。既存 `test-image`（`Assets.xcassets/test-image.imageset`）を再利用する。

---

## 3. 画面要件

### 3.1 機能一覧（セクション構成）

1. **Picker - Basic**: ShareText / ShareURL / ShareImage / ShareFile
2. **Picker - Multiple**: ShareMultipleImages / ShareMultipleFiles / ShareTextAndURL
3. **Picker - Filter**: ShareExcludingServices（`excludedServiceTitles` best-effort）
4. **Direct Service**: ShareViaMail（`recipients`/`subject` 設定 + `.composeEmail`）/ CanPerformMail（`canPerform` 照会）
5. **Error**: ShareEmpty / ShareInvalidURL / ShareMissingFile / ShareMissingImage / ShareUnknownService

### 3.2 操作導線（入力 → 実行 → 結果表示）

- メインメニュー（`ContentView`）→ "Share Example" カード → `ShareSampleView`
- 各ボタン押下 → `Task { await runShare(...) }` or `Task { await runDirect(...) }` → 結果を `updateResult` で `✅`/`❌` 表示
- picker 表示は **実ユーザークリック起点で picker を実機確認するための導線を提供する**目的で、ボタン押下から呼ぶ。ただし `Task { await ... }` 経由の呼び出しは `NSSharingServicePicker.show(...)` の `mouseDown` コンテキスト保持を保証しない（実装結果 v2 の未解決事項）。安定表示の可否は次工程の実機手動確認で判断する
- picker 系ボタン = 「実 UI 手動検証用」、direct service / `canPerform` 系 = 「コードレビュー範囲でも比較的安定して確認できる経路」として役割を分ける

### 3.3 エラー表示（errorCode / errorMessage）

- `ShareError` 捕捉時: `[<label>] errorCode=<code>, errorMessage=<message>` を `❌` 付きで表示
- picker キャンセル時: `[<label>] completed=false (cancelled)` を `✅` で表示（キャンセルはエラーではない）
- picker 完了時: `[<label>] completed=true, service=<serviceName>`

### 3.4 ログ表示

- 画面上のログ領域は設けず、既存踏襲で `Log.d`/`Log.e`（Console.app 経由）に出力。各操作先頭と結果でログを残す。

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `mac/MacLibraryExample/MacLibraryExample/ShareSampleView.swift`

### 4.2 既存変更

- `mac/MacLibraryExample/MacLibraryExample/ContentView.swift`: "Share Example" メニューカード + `NavigationLink` を追加

### 4.3 画像アセット（新規追加なし・既存再利用）

- 既存の `test-image` アセット（`mac/MacLibraryExample/MacLibraryExample/Assets.xcassets/test-image.imageset`、`test.png` / `test 1.png` / `test 2.png`）を再利用する。新規アセットは追加しない。
- `.imageFile(path:)` はファイルパスを要求するため、asset catalog の imageset を直接パス参照できない。**実装では `NSImage(named: "test-image")` で読み込み、`FileManager.temporaryDirectory` に PNG として書き出し、その temp path を `.imageFile(path:)` に渡す**（既存アセット利用 と API 入力形式の橋渡し）。

### 4.4 非変更

- `MacShareManager` 等ライブラリ本体（`mac/MacLibrary/`）: サンプルからは公開 API 呼び出しのみ。変更しない。
- `MacLibraryExampleApp.swift`: Share は起動時セットアップ不要（Notification と異なり delegate 常駐登録なし）。変更しない。
- `MacLibraryExample.entitlements`: 現状維持（不足時は要検証として記録、本計画では変更しない）。

---

## 5. 実装方針

### 5.1 共通実装パターン（維持）

- メインメニュー → サンプル画面導線（`ContentView` の `menuCard` + `NavigationLink`）を維持
- サンプル画面先頭のタイトル + 結果表示領域を維持
- `sectionView(title:)` による機能カテゴリ別ボタン群を維持
- `FullWidthPressableButtonStyle`（青・全幅・押下アニメ）を維持
- `updateResult(isSuccess:result:)` の `✅`/`❌` + `DispatchQueue.main.async` を維持
- 操作先頭・結果でのログ出力を維持

### 5.2 拡張点

- 2 モード（picker / direct）をセクションで明示分離（iOS の単一モードからの拡張）
- エラー表示を `ShareError` の型付き `errorCode`/`errorMessage` に強化（iOS は文字列のみ）
- `canPerform` 照会ボタン追加（macOS 固有 API）
- `excludedServiceTitles` を使ったサービス除外ボタン追加

### 5.3 呼び出し境界

- サンプルは `MacShareManager.shared` の **`async throws` 版**を `Task { await ... }` から呼ぶ
- 戻り値 `ShareResult(completed:serviceName:)` を結果表示に変換
- 例外は `catch let error as ShareError`（型付き）→ その他は `catch`（`localizedDescription`）でフォールバック
- **注**: `Task { await ... }` 経由の呼び出しは `NSSharingServicePicker.show(...)` の `mouseDown` コンテキスト保持を保証しない（実装結果 v2）。picker 系ボタンは実 UI 手動検証用の導線であり、安定表示の可否判断は次工程の手動確認で行う。direct service / `canPerform` は picker UI に依存しないため相対的に安定して確認できる
- 画像共有は既存 `test-image` アセットを `NSImage(named:)` → temp PNG 書き出し → `.imageFile(path:)` の順で橋渡しする（4.3）

---

## 6. 実装詳細（implement-sample-app ステップ3 で行う内容）

### 6.1 追加する UI 要素（ボタン・入力欄・結果表示）

- 結果表示: `@State private var resultText`（既存踏襲、入力欄は設けずボタン群で固定コンテンツを共有）
- ボタン（label → 呼び出し）:
  - ShareText → `share(content: ShareContent(items: [.text("Shared from MacLibraryExample")]))`
  - ShareURL → `.url("https://www.apple.com")`
  - ShareImage → `.imageFile(path:)`（既存 `test-image` アセット → temp PNG。4.3 参照）
  - ShareFile → `.file(path:)`（temp テキスト生成）
  - ShareMultipleImages / ShareMultipleFiles → 複数 items（画像は `test-image` を複数 temp path にコピー）
  - ShareTextAndURL → `[.text(...), .url(...)]`
  - ShareExcludingServices → `excludedServiceTitles: ["Add to Reading List"]` 等（best-effort）
  - ShareViaMail → `shareViaService(content: ShareContent(items:[.text("Body")], recipients:["test@example.com"], subject:"Sample Subject"), serviceName: "com.apple.share.Mail.compose")`
  - CanPerformMail → `canPerform(content:serviceName:"com.apple.share.Mail.compose")` の Bool を表示
  - ShareEmpty / ShareInvalidURL / ShareMissingFile / ShareMissingImage / ShareUnknownService（`serviceName:"invalid.service"`）
- 入力欄: 本計画では設けない（固定サンプルコンテンツ。iOS 版と同方針）

### 6.2 各 API の呼び出し方針とコールバック処理

- picker 系: `runShare(label:content:)`（async）
  ```
  do {
      let result = try await MacShareManager.shared.share(content: content)
      updateResult(isSuccess: true,
          result: result.completed
              ? "[\(label)] completed=true, service=\(result.serviceName ?? "nil")"
              : "[\(label)] completed=false (cancelled)")
  } catch let error as ShareError {
      updateResult(isSuccess: false, result: "[\(label)] errorCode=\(error.errorCode), errorMessage=\(error.errorMessage)")
  } catch {
      updateResult(isSuccess: false, result: "[\(label)] error=\(error.localizedDescription)")
  }
  ```
- direct 系: `runDirect(label:content:serviceName:)`（同型、`shareViaService` を呼ぶ）
- canPerform: `runCanPerform(label:content:serviceName:)` → Bool を `✅` で表示、throw 時は error 表示
- サンプルデータヘルパー:
  - `prepareSampleImagePath()` / `prepareSampleImagePaths(count:)`: `NSImage(named: "test-image")` → `tiffRepresentation`/`NSBitmapImageRep` で PNG 化 → `FileManager.temporaryDirectory` に書き出し → path を返す
  - `prepareSampleFileURL()` / `prepareSampleFileURLs(count:)`: temp テキストファイルを生成（iOS 版流用）

### 6.3 入力バリデーション方針

- サンプル側では明示バリデーションを行わず、ライブラリの `ShareError`（`noValidItems`/`invalidURL`/`fileNotFound`/`imageLoadFailed`/`serviceUnavailable`）を意図的に発火させて表示する（異常系ボタンの目的）。

---

## 7. 手動確認観点

### 7.1 正常系

- [ ] メインメニューに "Share Example" カードが表示され、タップで `ShareSampleView` に遷移する
- [ ] ShareText / ShareURL でボタン押下 → ピッカーが表示され、共有先を選ぶと `completed=true, service=...` が表示される
- [ ] ShareImage / ShareFile / 複数アイテムで内容が共有先に正しく渡る
- [ ] ShareViaMail で Mail 作成画面に `recipients` / `subject` が反映される（direct モード）
- [ ] CanPerformMail が `true`/`false` を返す
- [ ] ピッカーを未選択で閉じると `completed=false (cancelled)` が `✅` で表示される（エラーではない）

### 7.2 異常系（errorCode / errorMessage）

- [ ] ShareEmpty → errorCode=1401 / "No shareable items were provided."
- [ ] ShareInvalidURL → errorCode=1402 / "Invalid URL: ..."
- [ ] ShareMissingFile → errorCode=1404 / "File not found at path: ..."
- [ ] ShareMissingImage → errorCode=1403 / "Failed to load image at path: ..."
- [ ] ShareUnknownService → errorCode=1406 / "Sharing service unavailable: ..."

### 7.3 macOS 固有・要検証

- 注: 実機 / 実 UI での mouseDown 検証は次工程の手動確認で扱い、**本サンプル設計レビューの pass/fail には含めない**（実装レビュー v3 の切り分けに従う）。
- [ ] **mouseDown 制約**: ボタン押下（実ユーザークリック）起点でピッカーが安定表示されること（実装結果 v2 の未解決事項。`Task {}` 経由がコンテキストを保証しないため実機で目視確認）
- [ ] `excludedServiceTitles` 指定でサービスが非表示になるか（ローカライズ環境では表示名不一致で効かない場合がある点を確認）
- [ ] direct モードの `serviceName`（`com.apple.share.Mail.compose` 等）が対象環境で有効か（無効なら `serviceUnavailable` になる）
- [ ] サンドボックス App でのファイル/画像共有・AirDrop に entitlement 追加が必要か
- [ ] 多重起動（連打）時に 2 回目が `alreadyInProgress`（errorCode=1408）で拒否されること

---

## 8. 出力メモ（設計/実装結果由来 vs 計画時追加判断の分離）

- 設計書・実装結果由来: 公開 API 一覧、エラー契約（errorCode/message）、2 モード構成、mouseDown 未検証・`alreadyInProgress` 追加などの制約
- 計画時の追加判断:
  - iOS `ShareSampleView` のセクション構成を macOS 2 モードに再編（Picker 系 / Direct Service / Error）
  - エラー表示を型付き `ShareError` の errorCode/message に強化
  - `canPerform` / `excludedServiceTitles` / direct `recipients`+`subject` を可視化するボタンを追加
  - サンプル画像は既存 `test-image` アセットを再利用し、`NSImage(named:)` → temp PNG → `.imageFile(path:)` で橋渡し（新規アセット追加なし）
  - picker 系ボタンは実 UI 手動検証用の導線と位置づけ、`Task {}` 経由が mouseDown コンテキストを保証しない点を明記（実装レビュー v3 の切り分けに従い、実機検証は次工程の手動確認で扱う）
