# 実装計画: Share サンプルアプリ（IosLibraryExample）v1

- 対象アプリ: `ios/IosLibraryExample`
- 対象OS: iOS 18 以降
- 参照設計書: `artifact/designs/share/2026-07-04-ios-share-design.md`
- 参照実装結果: `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v3.md`
- 作成日: 2026-07-04
- 版: v1
- 使用言語: Swift（SwiftUI）

---

## 概要

`IosShareManager`（`IosLibrary`）が公開する共有 API を、iOS サンプルアプリで手動検証できるようにする。既存の `NotificationSampleView` / `DialogSampleView` の UI パターン（メインメニュー導線・sectionView グルーピング・`updateResult` による ✅/❌ 表示）を踏襲し、新規 `ShareSampleView` を追加する。

ライブラリ（`IosLibrary` / `UnityIosPlugin`）は変更しない。本計画はサンプルアプリでの利用例整備のみを対象とする。

### ライブラリ公開 API（デモ対象）

| API | 用途 |
| --- | --- |
| `IosShareManager.shared.share(content:completion:)` | 共有シート提示。completion は `(isSuccess, completed, activityType, errorMessage)` |
| `ShareContent(items:subject:previewTitle:excludedActivityTypes:)` | 共有ペイロード |
| `ShareItem.text(String)` | テキスト共有 |
| `ShareItem.url(String)` | URL 共有（Data 層で scheme 検証） |
| `ShareItem.imageFile(path:)` | 画像ファイル共有 |
| `ShareItem.file(path:)` | 任意ファイル共有 |

---

## 1. 画面要件

### 1.1 機能一覧（sectionView 単位）

| セクション | ボタン | 呼び出す ShareContent | 目的 |
| --- | --- | --- | --- |
| Text | ShareText | `items: [.text(...)]` | テキスト共有（最小） |
| URL | ShareURL | `items: [.url("https://...")]` | URL 共有 |
| URL | ShareURLWithPreview | `items: [.url(...)], previewTitle: ...` | リッチプレビュー即時表示 |
| Image | ShareImage | `items: [.imageFile(path: <bundled png>)]` | 画像共有 |
| File | ShareFile | `items: [.file(path: <temp txt>)]` | 任意ファイル共有 |
| Combination | ShareMultiple | `items: [.text(...), .url(...)]` | 複数アイテム共有 |
| Combination | ShareWithSubject | `items: [.text(...)], subject: ...` | 件名（Mail 等）付き共有 |
| Combination | ShareExcludingActivities | `items: [.url(...)], excludedActivityTypes: [...]` | 共有先の除外 |
| Error | ShareEmpty | `items: []` | `noValidItems` 検証 |
| Error | ShareInvalidURL | `items: [.url("not a url")]` | `invalidURL` 検証 |
| Error | ShareMissingFile | `items: [.file(path: "/no/such.file")]` | `fileNotFound` 検証 |
| Error | ShareMissingImage | `items: [.imageFile(path: "/no/such.png")]` | `imageLoadFailed` 検証 |

### 1.2 操作導線（入力 → 実行 → 結果表示）

- Main Menu（`ContentView`）に "Share Example" の `menuCard` を追加 → `NavigationLink` で `ShareSampleView` へ遷移。
- `ShareSampleView` 先頭にタイトル + 結果表示領域（固定）。その下に ScrollView + sectionView 群。
- ボタン押下 → `IosShareManager.shared.share(...)` 呼び出し → 共有シート提示（成功時）またはエラー（失敗時）→ completion で結果表示を更新。
- 本計画では TextField 等の可変入力は追加せず、すべて固定サンプル値を使用する（既存 `DialogSampleView` / Android v4 サンプルと同方針）。

### 1.3 エラー表示（errorCode / errorMessage）

- 本機能に数値 `errorCode` はない（`(isSuccess, completed, activityType, errorMessage)` の文字列方式）。
- 結果表示は `updateResult(isSuccess:result:)` で ✅/❌ を先頭に付与:
  - 成功・共有完了: `✅ [shareText] completed=true, activityType=<id>`
  - 成功・キャンセル: `✅ [shareText] completed=false (cancelled)`
  - 失敗: `❌ [shareEmpty] errorMessage=<message>`
- Error セクションの各ボタンは、設計書 第9章の `errorMessage` 文言（例: `No shareable items were provided.` / `Invalid URL: <value>.` / `File not found at path: <path>.` / `Failed to load image at path: <path>.`）が表示されることを確認する。

### 1.4 ログ表示

- 各 completion で `Log.d(TAG, ...)` を残し、`isSuccess` / `completed` / `activityType` / `errorMessage` を出力する（ios.md の全メソッド先頭ログ規約に沿う）。
- 画面上の専用ログ領域は設けない（既存サンプル同様、結果表示 + Xcode コンソールで追う）。

---

## 2. 変更ファイル一覧

### 2.1 新規作成

- `ios/IosLibraryExample/IosLibraryExample/ShareSampleView.swift`

### 2.2 既存変更

- `ios/IosLibraryExample/IosLibraryExample/ContentView.swift`: Main Menu に "Share Example" の `NavigationLink` + `menuCard` を 1 つ追加

### 2.3 非変更（対象だが変更しない）

- `ios/IosLibraryExample/IosLibraryExample/IosLibraryExampleApp.swift`: 共有機能は起動時セットアップ（delegate 登録等）が不要なため変更しない
- `ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift` / `NotificationSampleView.swift`: 参照のみ、変更しない
- `IosLibrary` / `UnityIosPlugin` 配下のライブラリコード: 変更しない
- `app-icon-attachment.png`（既存バンドル資産）: 画像共有デモで再利用、変更しない
- `IosLibraryExample.xcodeproj`: 新規 Swift ファイルは `IosLibraryExample` グループ配下に置く。`PBXFileSystemSynchronizedRootGroup` を使用していれば自動認識（実装時に要確認。未使用なら pbxproj への target membership 追加が必要）

---

## 3. 実装方針

### 3.1 既存サンプルコードの深掘り結果

- **再利用する既存コンポーネント / パターン**:
  - `ContentView.menuCard(title:subtitle:)` と `NavigationLink`: Main Menu 導線
  - `NotificationSampleView` の構造: タイトル + 固定結果表示 + ScrollView + `sectionView(title:)` グルーピング
  - `FullWidthPressableButtonStyle`（青ボタン、押下アニメーション）: セクション内ボタン。※ `NotificationSampleView` 内の `private struct` のため `ShareSampleView` に同等の private スタイルを複製する（既存を共有化するリファクタは本計画のスコープ外）
  - `updateResult(isSuccess:result:)`: `DispatchQueue.main.async` + ✅/❌ 文言。`ShareSampleView` に同パターンで実装
- **追加するコンポーネント**:
  - `ShareSampleView`（新規 View）
  - `ShareSampleView` 内の private helper: `runShare(label:content:)`（共有実行 + 結果反映の共通化）、`prepareSampleFileURL()`（`.file` デモ用の一時テキストファイル生成）、`bundledImagePath()`（`app-icon-attachment.png` のパス解決）、`updateResult(isSuccess:result:)`
- **変更するファイルと理由**:
  - `ContentView.swift`: Share サンプル画面への導線追加（1 ブロック）

### 3.2 iOS 共通実装パターン（維持 / 拡張）

- 維持:
  - Main Menu → サンプル画面の `NavigationStack` + `NavigationLink` 導線
  - 画面先頭のタイトル + 結果表示領域
  - `sectionView` による機能カテゴリ別グルーピング
  - `updateResult` の ✅/❌ 文言、コールバック結果を**メインスレッド**で反映（`IosShareManager` が既に main actor で completion を呼ぶが、サンプル側も `DispatchQueue.main.async` で二重に安全化）
  - 公開 API 呼び出し前後の `Log.d`
- 拡張:
  - 共有特有の結果（`completed`（キャンセル判定）/ `activityType`）を結果文言に含める
  - Error セクションを設け、ドメインエラーの `errorMessage` を画面で確認できるようにする（`DialogSampleView` にはないが、`NotificationSampleView` の異常系表示に準じる）

### 3.3 Android（相互参照ペア）との対応

- Android v4 サンプルは送信 9 機能 + カスタムチューザーアクション / FileProvider / コールバックキャンセル等、Android 固有 API を多くデモしている。iOS の公開 API スコープはこれより狭い（`UIActivityViewController` ベースの送信のみ）ため、**iOS は自 OS の API サーフェスに対応するボタン群のみ**を用意する。
- 画面構成の骨格（メインメニュー導線・カテゴリ別ボタン群・結果表示）は Android と揃える。iOS 固有の `activityType` / `completed`（キャンセル）表示は iOS 側の拡張とする。

---

## 4. 実装詳細（implement-sample-app ステップ3で行う内容）

### 4.1 共通ヘルパー

```swift
// 共有実行の共通化。completion 結果を結果表示へ反映する。
private func runShare(label: String, content: ShareContent) {
    Log.d(TAG, "[runShare] label: \(label), items: \(content.items.count)")
    IosShareManager.shared.share(content: content) { isSuccess, completed, activityType, errorMessage in
        Log.d(TAG, "[runShare][completion] label: \(label), isSuccess: \(isSuccess), completed: \(completed), activityType: \(activityType ?? "nil"), errorMessage: \(errorMessage ?? "nil")")
        let detail: String
        if isSuccess {
            detail = completed
                ? "[\(label)] completed=true, activityType=\(activityType ?? "nil")"
                : "[\(label)] completed=false (cancelled)"
        } else {
            detail = "[\(label)] errorMessage=\(errorMessage ?? "nil")"
        }
        updateResult(isSuccess: isSuccess, result: detail)
    }
}
```

- `updateResult(isSuccess:result:)`: `NotificationSampleView` と同一実装（`DispatchQueue.main.async` + ✅/❌）。

### 4.2 各機能の UI とバリデーション方針

- 各ボタンは `runShare(label:content:)` を呼ぶだけの薄い実装にする。
- **画面側の入力バリデーションは行わない**（可変入力欄がないため）。URL 妥当性・ファイル存在・画像読込の検証はライブラリ（`ShareRepositoryImpl`）の責務に委譲し、Error セクションで**あえて不正値**を渡して `errorMessage` の表示を確認する。
- 画像共有（`ShareImage`）: `Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path` でパスを解決。解決失敗時は `updateResult(isSuccess: false, ...)` で `Sample image not found in bundle` を表示して中断（バンドル資産欠落時の防御。ライブラリの `imageLoadFailed` とは別レイヤ）。
- ファイル共有（`ShareFile`）: 一時ディレクトリに `share-sample.txt` を生成してパスを渡す。

```swift
// .file デモ用の一時ファイル生成（失敗時 nil）
private func prepareSampleFileURL() -> URL? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
    do {
        try "Shared from IosLibraryExample.".write(to: url, atomically: true, encoding: .utf8)
        return url
    } catch {
        Log.e(TAG, "[prepareSampleFileURL] failed: \(error)")
        return nil
    }
}
```

### 4.3 固定サンプル値

| ボタン | サンプル値 |
| --- | --- |
| ShareText | `.text("Shared from IosLibraryExample")` |
| ShareURL | `.url("https://www.apple.com")` |
| ShareURLWithPreview | `.url("https://www.apple.com")`, `previewTitle: "Apple"` |
| ShareImage | `.imageFile(path: <bundled png path>)` |
| ShareFile | `.file(path: <temp txt path>)` |
| ShareMultiple | `[.text("Check this out"), .url("https://www.apple.com")]` |
| ShareWithSubject | `[.text("Body text")]`, `subject: "Sample Subject"` |
| ShareExcludingActivities | `[.url("https://www.apple.com")]`, `excludedActivityTypes: ["com.apple.UIKit.activity.CopyToPasteboard", "com.apple.UIKit.activity.PostToFacebook"]`（`CopyToPasteboard` は標準で出やすく確認が安定。`PostToFacebook` は環境依存の補足） |
| ShareEmpty | `items: []` |
| ShareInvalidURL | `.url("not a valid url")` |
| ShareMissingFile | `.file(path: "/nonexistent/share-missing.txt")` |
| ShareMissingImage | `.imageFile(path: "/nonexistent/share-missing.png")` |

---

## 5. 手動確認観点

実機/シミュレータで上から順に確認する。iPad でも popover クラッシュしないことを併せて確認する。

| # | 観点 | 操作 | 期待結果 |
| --- | --- | --- | --- |
| 1 | 導線 | Main Menu で "Share Example" をタップ | `ShareSampleView` へ遷移 |
| 2 | テキスト共有 | ShareText | 共有シートが表示され、共有先にテキストが渡る。完了で `✅ completed=true, activityType=...`、キャンセルで `✅ completed=false (cancelled)` |
| 3 | URL 共有 | ShareURL | 共有シートに URL が渡る |
| 4 | プレビュー | ShareURLWithPreview | ヘッダに previewTitle（Apple）が**ネットワーク待ちなしで即時**表示される |
| 5 | 画像共有 | ShareImage | 画像が共有先に渡る（写真保存/Mail 添付等で確認） |
| 6 | ファイル共有 | ShareFile | テキストファイルが共有先（Files 保存等）に渡る |
| 7 | 複数共有 | ShareMultiple | テキストと URL の両方が渡る |
| 8 | 件名 | ShareWithSubject | Mail を選ぶと件名に "Sample Subject" が入る |
| 9 | 除外 | ShareExcludingActivities | 共有シートから **コピー（Copy）が非表示**（主確認）。Facebook が表示される環境では Facebook も非表示（補足。Facebook は環境や iOS 状態により最初から出ないことがあり、確認は任意） |
| 10 | 空 | ShareEmpty | 共有シートは出ず `❌ errorMessage=No shareable items were provided.` |
| 11 | 不正URL | ShareInvalidURL | `❌ errorMessage=Invalid URL: not a valid url.` |
| 12 | ファイル不在 | ShareMissingFile | `❌ errorMessage=File not found at path: /nonexistent/share-missing.txt.` |
| 13 | 画像不在 | ShareMissingImage | `❌ errorMessage=Failed to load image at path: /nonexistent/share-missing.png.` |
| 14 | iPad | 任意の共有ボタン（iPad） | popover として表示され、クラッシュしない |
| 15 | キャンセル区別 | 共有シートを閉じる（キャンセル） | `completed=false`、`errorMessage` は表示されない |

### 5.1 要検証・未実施になり得る項目

- 実機/シミュレータでの各共有先（Mail / Messages / Files / AirDrop / 写真）の実受領は、環境（サインイン状態・接続端末）により一部確認できない場合がある。確認できない共有先は実装結果で理由付きで明記する。
- iPad 実機/シミュレータが用意できない場合、#14 は「実機未確認」として記録する。

---

## 6. 出力・整合メモ

- 計画由来: ライブラリ公開 API（第0節の表）、エラー文言（設計書 第9章）。
- 計画作成時の追加判断: Error セクションの設置、`activityType` / `completed`（キャンセル）の結果表示、`app-icon-attachment.png` の画像デモ再利用、一時ファイル生成方式。
- 既存 UI 規約（`sectionView` / `FullWidthPressableButtonStyle` / `updateResult` / `menuCard`）を優先し、不要な構造変更は行わない。
- 不確実: `IosLibraryExample.xcodeproj` の同期グループ利用有無は実装時に確認（未使用なら target membership 追加が必要）。要検証。
