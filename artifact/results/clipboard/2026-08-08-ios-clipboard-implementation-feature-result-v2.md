# 実装結果レポート v2（実装レビュー v1 反映）

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v1.md`
- 前版: `artifact/results/clipboard/2026-08-02-ios-clipboard-implementation-feature-result-v1.md`
- ブランチ: feature/NTKIT-14

## 1. 実装サマリー

### 1.1 レビュー指摘の反映（high 7件）

| ID | 指摘 | 反映内容 | 状態 |
|---|---|---|---|
| H-01 | `UIPasteControl` 経路が `acceptedTypes` を無視し、file・timeout・実キャンセル未実装 | `ClipboardProviderLoadExecutor` を新設し、`PasteItemProviderLoader` を全面再実装。`acceptedTypes` を loader へ渡して型選択に反映（優先度 text > url > image > file）、file ロード分岐を追加、`providerLoad` timeout・`Progress` 保持・request 単位 gate・text/URL の `maxLoadByteCount` 検査を実装。`cancelAll()` は system load を実際に cancel し、未配信ファイルを削除する | 解消 |
| H-02 | 非協調的 async で attach 前キャンセルを取りこぼす | `ClipboardAsyncRaceCoordinator` に `pendingResult` ラッチを追加。continuation 未 attach 時の勝者を保持し、attach 直後に replay する | 解消 |
| H-03 | 監視開始失敗が成功として返り、stop/start 境界で旧イベントを誤配信 | `startObserving` を `throws` へ戻し `pasteboardUnavailable` を送出。Bridge は `startHandler` へ失敗を伝播。`observingGeneration` による世代 gate を導入し、closure に capture した世代と照合する | 解消 |
| H-04 | 名前付き pasteboard 名が通常ログへ漏れる | `PasteboardScope` / `PasteboardCreationRequest` に `redactedDescription`（kind + 名前長のみ）を追加し、Manager / UseCase / Repository / Resolver の全ログ 50 箇所超を置換 | 解消 |
| H-05 | size limit が全 kind に適用されない | executor に text/URL の UTF-8 byte 検査を追加。`.imageFile` copy は decode 前に resource file size を検査。file load はサイズ取得不能時に成功させず `fileCopyFailed` とする（上限をセキュリティ境界として扱う） | 解消 |
| H-06 | malformed な `scope` を `.general` として処理 | key 不在と型不正を区別。present-but-non-object の `scope` / `options` は `nil` を返し `CLIPBOARD_INVALID_REQUEST` になる | 解消 |
| H-07 | Swift 6 strict concurrency 未達 | `ClipboardRepositoryImpl` の `nonisolated init` を廃止（nil デフォルト引数方式へ変更）、observer closure を `MainActor.assumeIsolated` に変更。**Clipboard 配下の strict error / warning は 0 件**。ただし I-10 全体は未達（下記 7 章参照） | 部分解消 |

### 1.2 レビュー指摘の反映（medium 6件 / low 3件）

| ID | 反映内容 |
|---|---|
| M-01 | `ClipboardMappers.toItemData` を identifier ベースへ変更。`plainText` を明示優先し、URL も UTI 適合で決定するため辞書順序に依存しない |
| M-02 | custom UTI 検証を ASCII 英数字・`-`・`_`・dot のみに制限（`isASCIIAlphanumeric` を導入し Unicode 誤許容を排除） |
| M-03 | `IosClipboardManager.init(timeouts:limits:)` を public convenience initializer として追加。native caller が timeout / limits を差し替え可能 |
| M-04 | `ios.md` の「Manager の公開 API」へ同期 control / factory 例外を追記し、`common.md` の例外規定を明示参照。「必ず `async throws`」との衝突を解消 |
| M-05 | `UnityIosClipboardJsonParser` の internal 関数 20 個へ先頭ログを追加（値は出さず key 有無 / 件数 / 長さのみ。JSON は `ClipboardRedaction.json` 経由） |
| M-06 | project version bump の原因を特定し本レポートへ記載（7 章） |
| L-01 | Void 返却の `copy` / `append` から `@discardableResult` を削除 |
| L-02 | `UIPasteControl.Configuration` を `var` → `let` へ変更（2 箇所） |
| L-03 | `ClipboardAsyncRaceCoordinator` が決着時に timeout task を cancel するよう変更。成功操作が timeout 分の task を保持し続けない |

### 1.3 実装時の追加判断

- **`MainActor.assumeIsolated` の採用**: レビューは observer callback を `Task { @MainActor in ... }` で hop する案を提示していたが、`queue: .main` 登録により callback は必ず main thread で実行されるため `assumeIsolated` を採用した。Task hop はイベント配信を非同期化し順序性を崩す（`stopObserving` 後に queue 済み Task が走る）ため、同期配信を維持できる `assumeIsolated` の方が契約に忠実と判断した。strict concurrency は同等に満たす。
- **`ClipboardProviderLoadExecutor` の新設**: H-01 と H-05 は `loadItem`（P-11）と `UIPasteControl`（S11）の双方に同一の契約を要求する。設計が「`ClipboardTemporaryFileStore` / `ClipboardImageCoder` を S6 と共用（重複実装を作らない）」としている方針に沿い、provider ロードの中核（timeout / gate / size limit / cleanup）を共通 executor へ切り出した。両経路が同一実装を共有するため契約差分が構造的に発生しない。

## 2. 変更ファイル

### 2.1 新規作成

- `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardAsyncRaceCoordinatorTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/PasteItemProviderLoaderTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Domain/ClipboardLogRedactionTests.swift`

### 2.2 既存変更

- `agent-rules/coding-rules/ios.md`（M-04）
- `Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift`（H-02 / L-03）
- `Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift`（H-01 / H-05: executor 利用へ全面再実装）
- `Clipboard/Presentation/PasteItemProviderLoader.swift`（H-01: 全面再実装）
- `Clipboard/Presentation/ClipboardPasteReceiverView.swift`（H-01: `acceptedTypes` を loader へ伝達）
- `Clipboard/Presentation/PasteControlFactory.swift` / `ClipboardPasteControlContainerView.swift`（L-02）
- `Clipboard/Common/ClipboardLog.swift`（H-04: `redactedDescription` 追加）
- `Clipboard/IosClipboardManager.swift`（H-03 / H-04 / H-07 / M-03 / L-01）
- `Clipboard/Data/Repository/ClipboardRepositoryImpl.swift`（H-04 / H-05 / H-07）
- `Clipboard/Data/Repository/PasteboardResolver.swift`（H-04）
- `Clipboard/Data/Repository/ClipboardMappers.swift`（M-01）
- `Clipboard/Data/Repository/ClipboardTypeIdentifierValidator.swift`（M-02）
- `Clipboard/Application/UseCase/*.swift`（H-04: ログの scope/request を redacted 化）
- `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift`（H-03）
- `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift`（H-06 / M-05 / Swift 6 `@unknown default`）
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift`（新 API 追従 + 観測契約テスト追加）
- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift`（H-06 テスト追加）

### 2.3 非変更（意図的）

- `IosLibrary/Notification/**`、`IosLibrary/Dialog/**`、`IosLibrary/Share/**`: 設計 DoD の「既存 Notification / Dialog / Share のファイルに変更がない」に従い変更していない。これが I-10 未達の直接原因（7 章参照）。

## 3. エラー契約反映

- ドメインエラー 24 ケースと errorCode / errorMessage 対応表は v1 から変更なし。`ClipboardErrorTests` で全件検証済み。
- 追加された失敗経路（provider timeout、size 超過、file size 検証不能、監視開始失敗）はすべて既存の 24 ケース内へマップしており、新規エラーケースの追加はない。
- `isSuccess == true` のとき `errorCode == nil` / `errorMessage == nil` は `IosClipboardManagerTests.copyCallbackReportsSuccess` で検証済み。

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary -destination "generic/platform=iOS Simulator"`
  - `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -destination "generic/platform=iOS Simulator"`
  - `./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -v 1.2.0 -o /tmp/IosLibrary-verify2.xcframework`
  - `./scripts/build_ios_library_xcframework.sh -c release -m UnityIosPlugin -v 1.2.0 -o /tmp/UnityIosPlugin-verify2.xcframework`
- 結果: SUCCESS（4 コマンドとも）。`** ARCHIVE SUCCEEDED **` と `[done] ... Created ...xcframework` を確認
- **Clipboard 配下の warning / error は通常ビルド・strict ビルドとも 0 件**（`grep -ci clipboard` == 0）

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary -destination "platform=iOS Simulator,id=<iPhone 17 Pro / iOS 26.2>"`
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -destination "platform=iOS Simulator,id=<iPhone 17 Pro / iOS 26.2>"`
- 結果サマリー:

| モジュール | v1 | v2 | 失敗 |
|---|---:|---:|---:|
| IosLibrary | 137 | **166** | 0 |
| UnityIosPlugin | 67 | **69** | 0 |

- 追加したテスト観点（レビュー「不足している主な観点」への対応）:

| 観点 | テストファイル | 対応レビュー項目 |
|---|---|---|
| cancel-before-attach、cancel/timeout/完了の 3 者競合、timeout 即時復帰 | `ClipboardAsyncRaceCoordinatorTests`（5件） | H-02 / L-03 |
| acceptedTypes による型選択、custom file UTI、text/URL サイズ境界、cancel 1回、provider timeout | `ClipboardProviderLoadExecutorTests`（9件） | H-01 / H-05 |
| 集約契約（全成功 / 混在 / 全失敗 / 空 / accepted 不一致）、cancel 時の UI 非配信、session 上書き、timeout | `PasteItemProviderLoaderTests`（8件） | H-01 |
| ログ秘匿（text / json / path / scope / creation request / failure detail） | `ClipboardLogRedactionTests`（5件） | H-04 |
| 同一 scope stop/start の世代 gate、監視開始失敗の throw | `IosClipboardManagerTests`（+2件） | H-03 |
| malformed scope / options の INVALID_REQUEST 化 | `UnityIosClipboardJsonParserTests`（+2 parameterized） | H-06 |

- 未実施項目（v1 から継続）:
  - 15 endpoint / 9 content kind / 全 detected values / 全 loaded item の end-to-end（I-08）
  - `ClipboardRedaction` のモジュール境界を独立検証する統合テスト（I-09）。ただし `.m` から実際に呼ばれておりビルド成功で間接検証済み
  - 実機 M-01〜M-16（シミュレータのみの環境のため実施不可）

## 6. Definition of Done（レビュー指摘後の再評価）

判定基準: ○=OK / △=一部OK / ×=未達 / -=対象外

### レビュー high 項目
- ○ H-01 S11 provider load（acceptedTypes / file / timeout / token / size / cleanup）
- ○ H-02 attach 前キャンセルの取りこぼし解消
- ○ H-03 監視開始失敗の伝播と世代 gate
- ○ H-04 pasteboard 名のログ秘匿
- ○ H-05 全 kind への size limit 適用
- ○ H-06 malformed scope / options の拒否
- △ H-07 Swift 6 strict concurrency（Clipboard 側は 0 件。I-10 全体は未達）

### 実装
- ○ Clipboard 配下の strict concurrency error / warning が 0 件
- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ 公開エラーメッセージ・ログが URL / path / pasteboard name / invalid reason を含まない
- ○ 非同期処理のタイムアウト・キャンセル・exactly-once が P-11 と P-16 で同一実装を共有
- ○ copy / load / image の全 kind にサイズ上限が実装されている
- ○ Bridge が errorCode を透過し、監視開始失敗を operation callback へ返す
- ○ 既存 Notification / Dialog / Share のファイルに変更がない
- × I-10（両モジュールが strict build で警告・エラーなし）

### テスト
- △ 単体テスト（166 + 69 = 235 件 green）。設計 U-01〜U-148 の全件網羅ではないが、レビューが指摘した不足観点はすべてカバー
- × 手動確認 M-01〜M-16（実機必須のため未実施）

## 7. 設計差分・未解決事項

### 7.1 I-10 と DoD の矛盾（要判断）

設計 v4 の DoD には次の 2 項目が同時に存在し、**両立できない**。

1. 「I-10 が両モジュールで `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` により警告・エラーなし」
2. 「既存 Notification / Dialog / Share のファイルに変更がない」

現在 strict build に残るエラーは以下 5 件で、**すべて Clipboard 以前から存在する Notification モジュール**のものである。

```
Notification/Domain/Model/NotificationCategoryOptions.swift:18,20,22,24  (static property is not concurrency-safe)
Notification/Presentation/Permission/NotificationPermissionHelper.swift:15  (static property 'shared' ...)
```

本対応では条件 2 を優先し、Notification モジュールを変更していない。理由:

- Clipboard 機能のスコープ外であり、`NotificationPermissionHelper.shared` の isolation 変更は Notification 機能の挙動に影響しうる
- 当該変更は Notification 機能側のレビューを経るべきものである

**I-10 を green にするには Notification モジュールの Swift 6 対応が必要**です。別タスクとして切り出すか、本タスクで対応するかをご判断ください。

### 7.2 project version bump（M-06 への回答）

`CURRENT_PROJECT_VERSION` の更新（IosLibrary 7→8、UnityIosPlugin 6→7）は、**`scripts/build_ios_library_xcframework.sh` が意図的に自動インクリメントする仕様**によるもの（同スクリプト 184〜305 行）。手動編集ではなく、成果物生成を実行した副作用である。設計の「project.pbxproj の編集不要」はソースファイル追加に関する記述であり、パッケージング時の build number 更新とは別事象。v1 レポートに記載がなかったため本レポートで補記する。なお本 v2 での成果物再生成により、さらにインクリメントされている。

### 7.3 その他の設計差分（v1 から継続）

- `ClipboardTypeIdentifierValidator` を `internal` → `public`（default 引数の可視性制約）
- `UIColor` の表現型識別子 `"com.apple.uikit.color"` は公式ドキュメント未確認の実装時判断。**要検証**（実機での色コピー往復確認を推奨）

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
