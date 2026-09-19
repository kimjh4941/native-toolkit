# レビュー結果

- 日付: 2026-08-01
- 対象ファイル: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v3.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- レビュー方法: 本モデルによる全文確認、別モデルによる独立レビュー、Apple 公式文書と Xcode 26.3 SDK による照合

---

## 前回指摘の反映状況

- キャンセル時の completion 契約と provider 不在 callback の管理: **概ね解消済み**。`cancelAll()` が `.cancelled` を 1 回配信し、request を発行時点で登録する形に統一された。ただし loader 解放時の例外が残る。
- 外部由来 `suggestedName` の安全性: **解消済み**。UUID 名、拡張子 allowlist、標準化パスの containment 検査が追加された。
- UUID 一時ディレクトリの cleanup: **概ね解消済み**。失敗、キャンセル後の遅延結果、loader 解放後の provider callback でディレクトリ単位に削除される。強制終了時の残留は要検証として妥当に残されている。
- `ClipboardWatcher` の `changeCount` 同期: **解消済み**。`start()` と通知受信時に基準値を更新し、foreground 比較との二重報告を防ぐ設計になった。
- `itemProviders` と `UIPasteControl` のプライバシー表現: **解消済み**。getter とロードを分離し、許可プロンプトとアクセス通知も別列で扱っている。
- `localOnly` の正の対照、ケース番号、要検証事項の重複: **解消済み**。

## 強み

- 前回指摘が契約、サンプル、リスク、要検証事項、DoD、反映履歴へ横断的に反映されており、変更理由を追跡しやすい。
- `NSItemProvider` の provider error、nil URL、コピー失敗、キャンセル後の遅延結果を分離し、ファイルの所有権移譲と cleanup 責務も明文化できている。
- プライバシー行列は許可プロンプトとアクセス通知を分け、`itemProviders` getter、provider load、`UIPasteControl` 経路を個別観測する構成で、原因を切り分けやすい。
- 名前付きペーストボードと App Group shared container の寿命・責務境界が明確である。
- 画像ファイル読み取り部分は、Xcode 26.3 / iPhoneSimulator 26.2 SDK、deployment target iOS 18.0 で型チェックに成功した。文書記載どおり、`NSItemProvider` の Sendable 捕捉警告も再現した。

## 改善点

### 高優先度

- 対象: `NSItemProvider` の設計契約 / `ItemProviderLoader.deinit`（535–540、606–610、667 行）
  - 問題点: 契約は「成功・失敗・provider 不在・キャンセルを含む全経路で completion を 1 回返す」としているが、loader 解放時の `deinit` は `Progress.cancel()` だけを実行し、保持中の `Request.deliver` へ `.cancelled` を返さない。後から provider callback が来ても `self == nil` の分岐は cleanup だけで終了する。provider 不在の main-queue callback も `[weak self]` のため、解放されれば通知されない。
  - 影響: `ItemProviderLoader().loadFirstImageFile { ... }` のように呼び出し側が loader を保持しなかった場合など、completion が 0 回になり exactly-once 契約が破れる。
  - 改善提案: loader を全 request 完了まで保持することを明示的な事前条件にするか、解放を cancellation と定義して pending completion に `.cancelled` を 1 回返せる所有モデルへ変更する。後者を採用する場合は Swift 6 の actor-isolated `deinit` 制約も型チェックとテストで確定する。

- 対象: `NSItemProvider` サンプル（542–706 行）
  - 問題点: 542 行と 546 行に ` ```swift ` が重複して Markdown のコードフェンスが破損している。また `loadFirstText` は未定義の `registerTextRequest`、`finishText`、`attachProgress` を呼び、管理表の型設計も「設計時に確定」のままである。
  - 検証結果: 画像部分のみは型チェックできたが、テキスト extension を含めると上記 3 helper の未定義でコンパイルに失敗した。
  - 影響: 「簡単なサンプルコード集」と `NSItemProvider` のテキスト読み取りを、そのまま実行・検証できない。DoD の「サンプルアプリで全サブ機能が確認できる」とも整合しない。
  - 改善提案: コードフェンスを修正し、型消去した共通 request state または URL/String 別の完全な state のどちらかに設計を確定する。未定義 helper を含まない単一の型チェック済み例に置き換える。

### 中優先度

- 対象: 通知・アラート非対象 API の説明 / テスト行列 / DoD（267、389、1014 行）
  - 問題点: Apple の `UIPasteboard` 概説が通知・アラート回避 API として明示する一覧から、文書は `types(forItemSet:)` と `canLoadObject(ofClass:)` を落としている。そのため「公式が明示列挙している API」の説明と DoD が完全ではない。
  - 改善提案: 公式一覧に両 API を追加する。`canLoadObject` は `itemProviders` getter の取得契機とは分け、取得済み provider に対する型判定自体の保証と getter の実機観測を混同しないよう記述する。

- 対象: 変更監視の scope / `ClipboardWatcher` / DoD（28、283–285、792–833、1024–1028 行）
  - 問題点: In scope と API 表には `removedNotification` および `changedTypesRemovedUserInfoKey` があるが、Watcher は `changedNotification` の added types しか扱わず、DoD にも removed types と名前付きペーストボード破棄通知の検証がない。
  - 改善提案: added/removed types と pasteboard removal を表現するイベントを設計し、両通知の登録・解除・再開・破棄を DoD に追加する。実装対象外なら In scope と「全サブ機能」の表現を縮小する。

- 対象: プライバシー行列と DoD（383、1013、1042–1043 行）
  - 問題点: 行列は全 15 ケースを iOS 18 と iOS 26 の双方で観測すると規定する一方、DoD は iOS 18 だけを必須としている。iOS 26 回帰の未観測でも完了扱いになり得る。
  - 改善提案: DoD を両 OS の 15 ケースに揃えるか、iOS 26 は限定した回帰ケースだけとするなら対象ケースを明示する。

### 低優先度

- 対象: `ClipboardWatcher`（787–825 行）
  - 問題点: observer callback は main queue だが、`start` / `checkOnForeground` / `stop` の呼び出しスレッドは固定されていない。別スレッドから呼ばれると `token` と `lastChangeCount` が競合し得る。
  - 改善提案: `ClipboardWatcher` を `@MainActor` にするか、全操作を main thread に限定する公開契約とテストを追加する。

## 不足項目

- loader 解放時を含めて completion が exactly once になる所有・キャンセル契約
- 未定義 helper のない、Markdown と Swift の双方で成立する `loadFirstText` サンプル
- 公式の通知・アラート回避 API 一覧における `types(forItemSet:)` と `canLoadObject(ofClass:)`
- `changedTypesRemovedUserInfoKey` と `removedNotification` の実装例・DoD
- iOS 18 / iOS 26 のプライバシー行列と完了条件の統一

## 総合評価

v3 は前回の安全性・キャンセル・cleanup・プライバシー指摘をほぼ解消しており、調査資料として完成度は高い。残る主な阻害要因は、loader 解放時に exactly-once 契約が破れることと、`loadFirstText` を含むサンプルが実行可能な形で閉じていないことである。これらを修正し、通知監視の scope と DoD を揃えれば、実装設計へ進める資料として十分である。

## 確認に使用した公式情報・SDK

- Apple Developer Documentation: https://developer.apple.com/documentation/uikit/uipasteboard
- Apple Developer Documentation: https://developer.apple.com/documentation/uikit/uipastecontrol
- Apple Developer Documentation: https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(forTypeIdentifier:completionHandler:)
- Apple Developer Documentation: https://developer.apple.com/documentation/foundation/progress/cancel()
- Xcode 26.3 / iPhoneSimulator 26.2 SDK（deployment target iOS 18.0）
- Swift 5 通常設定および Swift 6 strict concurrency 診断
