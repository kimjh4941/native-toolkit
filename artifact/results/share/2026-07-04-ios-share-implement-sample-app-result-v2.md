# サンプルアプリ実装結果: Share（IosLibraryExample）v2

- 対象アプリ: `ios/IosLibraryExample`
- 対象OS: iOS 18 以降
- 参照計画: `artifact/designs/share/2026-07-04-ios-share-sample-app-design-v1.md`
- 参照実装結果（ライブラリ）: `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v3.md`
- 作成日: 2026-07-04
- 版: v2（`artifact/reviews/share/2026-07-04-ios-share-implement-sample-app-review-v1.md` の軽微指摘を反映）

---

## 1. 変更ファイル

### 1.1 新規作成

- `ios/IosLibraryExample/IosLibraryExample/ShareSampleView.swift`
  - 計画書どおり、Text / URL / Image / File / Combination / Error の 5 セクション・12 ボタンを実装
  - `sectionView` グルーピング、`FullWidthPressableButtonStyle`、`updateResult`（✅/❌）は `NotificationSampleView` のパターンを踏襲（同名 private ヘルパーを複製する形。計画書 3.1 節記載どおり）
  - （v2）レビュー指摘（軽微）反映: `private extension View { func buttonStyle() -> some View { ... } }` を削除。`sectionView` は `FullWidthPressableButtonStyle` を直接適用しており当該 helper は未使用だったため（`NotificationSampleView.swift` にも同一の未使用定義が存在するが、レビュー対象は本ファイルのみのためそちらは変更していない）

### 1.2 既存変更

- `ios/IosLibraryExample/IosLibraryExample/ContentView.swift`
  - Main Menu に "Share Example"（`menuCard(title: "Share Example", subtitle: "Test system share sheet features")`）への `NavigationLink` を1ブロック追加

### 1.3 非変更（計画上対象だが未変更）

- `IosLibraryExampleApp.swift`: 計画どおり変更不要（共有機能に起動時セットアップは不要）
- `DialogSampleView.swift` / `NotificationSampleView.swift`: 参照のみ、変更なし
- `IosLibrary` / `UnityIosPlugin`: 変更なし
- `IosLibraryExample.xcodeproj`: `PBXFileSystemSynchronizedRootGroup` を使用しているため、新規ファイル追加に伴う pbxproj への手動編集は不要と確認済み（計画書の要検証事項を解消）

---

## 2. 実装したサンプル機能（計画書由来 / 追加判断の分離）

### 2.1 計画書由来の実装

計画書（`2026-07-04-ios-share-sample-app-design-v1.md`）第4章の実装詳細をそのまま反映:

| セクション | ボタン | 内容 |
| --- | --- | --- |
| Text | ShareText | `.text("Shared from IosLibraryExample")` |
| URL | ShareURL | `.url("https://www.apple.com")` |
| URL | ShareURLWithPreview | `.url(...)`, `previewTitle: "Apple"` |
| Image | ShareImage | `.imageFile(path:)`（バンドル `app-icon-attachment.png` を再利用） |
| File | ShareFile | `.file(path:)`（一時 `share-sample.txt` を都度生成） |
| Combination | ShareMultiple | `.text` + `.url` |
| Combination | ShareWithSubject | `.text`, `subject: "Sample Subject"` |
| Combination | ShareExcludingActivities | `.url`, `excludedActivityTypes: [CopyToPasteboard, PostToFacebook]`（レビュー反映済みの順序・主確認は CopyToPasteboard） |
| Error | ShareEmpty | `items: []` → `noValidItems` |
| Error | ShareInvalidURL | `.url("not a valid url")` → `invalidURL` |
| Error | ShareMissingFile | 存在しないパス → `fileNotFound` |
| Error | ShareMissingImage | 存在しないパス → `imageLoadFailed` |

共通ヘルパー `runShare(label:content:)` は計画書 4.1 節のコード例をそのまま実装。`IosShareManager.shared.share(content:completion:)` の呼び出しと、`isSuccess`/`completed`/`activityType`/`errorMessage` を結果文言へマッピングするロジックを 1 箇所に集約。

### 2.2 実装時の追加判断

- 計画書に記載のとおり、`FullWidthPressableButtonStyle` と `sectionView` は `NotificationSampleView` に private 定義されているため import では共有できず、`ShareSampleView.swift` 内に同一実装を複製した（計画書が明示的に許容している判断であり、新規の逸脱ではない）。
- `bundledImagePath()` / `prepareSampleFileURL()` は計画書のコード例をそのまま実装。追加のエラーハンドリングや構造変更は行っていない。

---

## 3. ビルド結果

- 実行コマンド: `xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryExample -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- 結果: **SUCCESS**（`** BUILD SUCCEEDED **`、v1・v2（未使用 helper 削除後の再ビルド）とも）
- 補足: `IosLibraryExample.xcodeproj` は `IosLibraryExample` を単体でビルドすると `IosLibrary.framework` 依存が解決できないため、`IosWorkspace.xcworkspace` 経由でビルドする必要がある（`IosLibrary`/`UnityIosPlugin` と同じ制約。前工程の実装結果でも同様の記載あり）。
- 新規ファイル（`ShareSampleView.swift`）はビルドログ上で `SwiftCompile` 対象として認識されており、`PBXFileSystemSynchronizedRootGroup` による自動認識が機能していることを確認した。

**重要な区別**: 以下は「ビルド確認済み」であり、「実機/シミュレータでの機能動作確認済み」ではない。

---

## 4. 実行確認（シミュレータ）

- 実行環境: iOS Simulator（iPhone 17, iOS 18 シリーズ、`xcrun simctl` で起動）
- 実施内容: アプリをインストール・起動し、Main Menu 画面のスクリーンショットを取得
- 結果: Main Menu に "Share Example"（サブタイトル "Test system share sheet features"）カードが "Dialog Example" / "Notification Example" と並んで正しく表示されていることを確認した（スクリーンショットで目視確認）

以降のボタン操作・画面遷移・共有シート表示・エラー文言表示については、**ユーザー自身が手動で確認する**旨の申し出があったため、本セッションでは実施していない。第5章の手動確認観点はユーザー側で実施される想定。

---

## 5. 手動確認観点 / 未実施項目

計画書第5章の観点をそのまま転記する。

| # | 観点 | 操作 | 期待結果 | 本セッションでの実施状況 |
| --- | --- | --- | --- | --- |
| 1 | 導線 | Main Menu で "Share Example" をタップ | `ShareSampleView` へ遷移 | 確認済み（カード表示のみ。タップ後の遷移はユーザー確認待ち） |
| 2 | テキスト共有 | ShareText | 共有シート表示、完了/キャンセルの文言分岐 | 未実施（ユーザー確認） |
| 3 | URL 共有 | ShareURL | 共有シートに URL が渡る | 未実施（ユーザー確認） |
| 4 | プレビュー | ShareURLWithPreview | ヘッダに previewTitle が即時表示 | 未実施（ユーザー確認） |
| 5 | 画像共有 | ShareImage | 画像が共有先に渡る | 未実施（ユーザー確認） |
| 6 | ファイル共有 | ShareFile | テキストファイルが共有先に渡る | 未実施（ユーザー確認） |
| 7 | 複数共有 | ShareMultiple | テキストと URL の両方が渡る | 未実施（ユーザー確認） |
| 8 | 件名 | ShareWithSubject | Mail 選択時に件名が入る | 未実施（ユーザー確認） |
| 9 | 除外 | ShareExcludingActivities | コピーが非表示（主確認）。Facebook は環境依存の補足 | 未実施（ユーザー確認） |
| 10 | 空 | ShareEmpty | `❌ errorMessage=No shareable items were provided.` | 未実施（ユーザー確認） |
| 11 | 不正URL | ShareInvalidURL | `❌ errorMessage=Invalid URL: not a valid url.` | 未実施（ユーザー確認） |
| 12 | ファイル不在 | ShareMissingFile | `❌ errorMessage=File not found at path: /nonexistent/share-missing.txt.` | 未実施（ユーザー確認） |
| 13 | 画像不在 | ShareMissingImage | `❌ errorMessage=Failed to load image at path: /nonexistent/share-missing.png.` | 未実施（ユーザー確認） |
| 14 | iPad | 任意の共有ボタン（iPad） | popover 表示、クラッシュしない | 未実施（ユーザー確認、iPad 実機/シミュレータ要） |
| 15 | キャンセル区別 | 共有シートを閉じる | `completed=false`、`errorMessage` なし | 未実施（ユーザー確認） |

未実施の理由: ユーザーから「手動確認は自分でやるので大丈夫」との申し出があり、本セッションでは #1（Main Menu 表示）のスクリーンショット確認までに留めた。#2〜#15 はユーザーが引き続き手動で実施する。

---

## 6. Android/iOS 共通実装パターンの維持・拡張

- 維持: `NavigationStack` + `NavigationLink` による Main Menu 導線、`sectionView` グルーピング、`FullWidthPressableButtonStyle`、`updateResult` の ✅/❌ 表示、公開 API 呼び出し前後の `Log.d`
- 拡張: 共有特有の `activityType` / `completed`（キャンセル区別）を結果文言に含めた点、Error セクションでドメインエラー文言を可視化した点（計画書 3.2 節の拡張方針どおり）
- Android（v4）との対応: Android は Custom Chooser Actions 等 Android 固有 API を多くデモしているが、iOS ライブラリの公開 API スコープ（`UIActivityViewController` ベースの送信のみ）に合わせ、iOS は自 OS の API サーフェスに対応するボタン群のみを実装した（計画書 3.3 節どおり）

---

## 7. 要検証

- iPad での popover 表示・非クラッシュはユーザーの手動確認待ち
- 各共有先（Mail / Messages / Files / AirDrop / 写真）への実共有は、環境（サインイン状態等）により一部確認できない可能性がある旨、計画書に明記済み
