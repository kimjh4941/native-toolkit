# レビュー結果

- 日付: 2026-08-29
- 対象ファイル: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降

---

## 強み

- Apple 公式文書に加えて Xcode 26.3 SDK の AppKit ヘッダと Swift interface を一次ソースとして用い、availability、Swift refined API、actor isolation まで確認している。
- `NSPasteboard` の基本操作だけでなく、複数アイテム、遅延提供、検出 API、Universal Clipboard 抑止、File Promise、レガシー API まで機能マップと API 表で広く整理している。
- 同期・非同期分類表に完了方式、thread / actor、キャンセル、リソース寿命の列があり、設計工程で必要な判断材料を追跡しやすい。
- プライバシー、非 Sendable、所有権変更、標準ペーストボードの誤解放など、実装事故につながるリスクを具体的な対策へ落とし込んでいる。
- Markdown 内の全 Swift コードブロックを結合し、`swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` で再確認した結果、型チェックは成功した。

## 改善点

### 高優先度

- **F. ファイル約束 / 7. 同期・非同期 API 分類表 / サンプルコード**
  - 問題: `NSFilePromiseProvider.delegate` は SDK ヘッダ上 `weak` だが、delegate の保持責務が API 表、分類表、リスク表にない。`copyFilePromise(delegate: PromiseDelegate())` のような呼び出しでは、遅延書き出し前に delegate が解放される可能性がある。
  - 改善: provider と delegate を所有するセッション型を設け、約束の完了またはペーストボード所有権喪失まで両方を強参照する契約を追加する。completion handler を必ず 1 回呼ぶ責務と解放条件も分類表・リスク・サンプルへ反映する。

- **8. 実装リスク RK-01 / RK-02 と 10. V-1**
  - 問題: `canReadItem` / `canReadObject` がアクセスアラートを発生させないかは V-1 で要検証なのに、RK-01 / RK-02 では macOS 15.0–15.3 の必須事前判定・フォールバックとして確定的に採用している。未検証 API をプライバシー緩和策として扱うため、設計が「通知なし判定」を誤って保証しうる。
  - 改善: 15.0–15.3 ではこれらを型判定の最適化に限定し、アラート非発生を保証しないと明記する。通知回避が契約上必要な操作は、ユーザー起点かつ paste-related な UI 経路へ限定する。V-1 の結果が出るまで RK-01 / RK-02 の採用判断を条件付きにする。

### 中優先度

- **6.U ユーザー起点の貼り付け UI**
  - 問題: `PasteButton(payloadType:onPaste:)` の最小 OS が macOS 10.15 とされているが、Xcode 26.3 の `SwiftUI.swiftinterface` ではこの initializer は macOS 13.0 以降である。`PasteButton` 型自体の導入時期と initializer の導入時期が混同されている。
  - 改善: `payloadType:onPaste:` を macOS 13.0、`supportedContentTypes:payloadAction:` を macOS 11.0、型自体を macOS 10.15 と分けて記載する。

- **3. 公式文書一覧 / 5.U / 6.U の `NSResponder.paste(_:)`**
  - 問題: AppKit の `paste(_:)` は Apple 公式 API 上 `NSText` の action method として定義され、`NSResponder` 自体には同名メソッドが宣言されていない。カスタム `NSView` が `@objc paste(_:)` を実装して responder chain の action を受けるサンプルは成立するが、`NSResponder.paste(_:)` という API 名は不正確である。
  - 改善: 「responder chain の `paste:` action（`NSText.paste(_:)`、カスタム responder では `@objc paste(_:)` を実装）」へ表記を変更し、`NSText.paste(_:)` と `NSResponder` の responder-chain 文書を一次ソースへ追加する。

- **1. 目的 / 11. Definition of Done**
  - 問題: 目的では既存 `IosClipboardManager` との API パリティ確保を掲げる一方、実際の公開 API 対応表は設計工程へ先送りされている。`expirationDate` と `localOnly` 以外の copy / append / read / snapshot / detection / observation / cancellation / scope 操作について、対応・代替・非対応が確認できない。
  - 改善: 調査書に iOS 公開 API → macOS system API / 代替 / 非対応理由のパリティ表を追加し、設計工程では公開シグネチャの確定だけを行う。調査工程から先送りする場合は、目的と調査完了条件から「パリティを取る」を外して「差分候補を抽出する」へ狭める。

- **7. 同期・非同期 API 分類表 / 11. Definition of Done**
  - 問題: DoD は「全採用 API」を分類表へ収録済みとしているが、`NSPasteboardWriting` / `NSPasteboardReading` の protocol requirements、`NSFilePromiseProvider` の生成・weak delegate・filename / operation queue callbacks、`pasteboardFinishedWithDataProvider(_:)` などが独立した寿命・完了契約として追跡されていない。
  - 改善: API 全網羅表の各採用行に分類表の行 ID を付け、機械的に相互照合できる形にする。定数・値型を除く採用 API と callback requirement がすべて対応するまで DoD を未完了に戻す。

- **10. V-8 / V-9 と 11. Definition of Done**
  - 問題: `.currentHostOnly` の検証に正の対照がなく、Universal Clipboard 環境自体が動作していない場合と option の抑止効果を区別できない。
  - 改善: 同一端末・アカウント・ネットワーク条件で通常コピーの端末間転送成功を先に確認し、その後 `.currentHostOnly` の非転送を確認する。待機時間、両端 OS、Bluetooth / Wi-Fi / Handoff 条件を記録する DoD を追加する。

### 低優先度

- **10. V-8**
  - 問題: 検証方法の「`macos-clipboard は端末 B` 側」という記述がプレースホルダーのように残っており、試験者が端末の役割を判断しにくい。
  - 改善: 「Mac を送信元、同一 iCloud アカウントの iPhone を受信先」のように端末 A / B と方向を明示する。

- **9. サンプルコード集**
  - 問題: 型チェック成功は確認できるが、プライバシーアラート、遅延 callback の寿命、Universal Clipboard、サンドボックス URL 権限など実行時契約まではコンパイル検証で保証されない。
  - 改善: 冒頭の「全件を検証済み」を「コンパイル検証済み」と限定し、実行時検証は V-1〜V-10 および File Promise delegate 寿命テストへリンクする。

## 不足項目

- `NSFilePromiseProvider.delegate` の weak 所有、provider / delegate の保持主体、解放条件、completion 1 回保証。
- macOS 15.0–15.3 でアラート非発生を保証できない場合の公開 API 契約とユーザー起点 UI への誘導方針。
- `NSText.paste(_:)` および AppKit responder chain の一次ソース。
- `IosClipboardManager` の全公開操作に対する macOS 対応・代替・非対応のパリティ表。
- API 全網羅表と同期・非同期分類表の採用 API 対応関係。
- `.currentHostOnly` 実機検証の正の対照と環境記録条件。

## 総合評価

一次ソースの使い方、API の広さ、並行性・プライバシー・寿命の整理はいずれも高水準で、macOS クリップボード設計の有力な土台になっている。一方、File Promise の weak delegate は実装時に機能不全へ直結し、未検証の `canRead*` をプライバシー緩和策として確定扱いしている点は公開契約を誤らせるため、確定前の修正が必要である。`PasteButton` availability、responder action の名称、iOS パリティ表、分類表の完全性、検証の正の対照を補えば、設計工程へ安全に引き継げる。

---

## 第2回レビュー（改善版 v2）

- 対象ファイル: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research-v2.md`
- 実施日: 2026-08-29

### 追加の改善点

#### 高優先度

- **F-06 / 7. 同期・非同期 API 分類表**
  - 問題: `NSFilePromiseProviderDelegate.filePromiseProvider(_:writePromiseTo:completionHandler:)` には、Swift で `filePromiseProvider(_:writePromiseTo:) async throws` として適合できる形も存在するが、v2 初版の API 表と分類表には callback 形しかなく、「非同期 API は D-01〜D-06 のみ」という断定と矛盾していた。
  - 改善: F-06 に callback 形と `async throws` 形を併記し、どちらか一方の実装で protocol 適合できることを明記する。「アプリが呼び出す非同期 API」と「アプリが実装する非同期 requirement」を分けて分類する。対照として F-10 に async 形が生成されないことも確認する。
  - v2 対応結果: **対応済み**。Swift 6 で async 形のみを実装した protocol 適合をコンパイル確認し、API 表、分類表、ローカル検証表、断定文へ反映した。F-10 は `reader` 省略時のコンパイルエラーにより async 形がないことを確認した。

- **F. ファイル約束のサンプル / RK-21**
  - 問題: `FilePromiseDelegate` の `finished` フラグは completion を provider 全体で 1 回に制限していた。書き出し要求が複数回来た場合、2 回目以降は completion handler を呼ばずに return するため、受け手が完了を待ち続ける。
  - 改善: completion の契約を「provider 全体で 1 回」ではなく「1 回の書き出し要求につき、成否にかかわらずちょうど 1 回」とする。同期的な `do/catch` で各要求の completion を完結させ、provider 全体を制限する共有ガードは置かない。
  - v2 対応結果: **対応済み**。`finished` / `NSLock` と早期 return を削除し、要求ごとに `do/catch` から completion を 1 回呼ぶサンプルへ修正した。RK-21 も同じ契約へ訂正した。

#### 低優先度

- **変更履歴 / サンプル検証範囲の参照**
  - 問題: V-13 の追加後も、第0章とサンプル検証範囲に `V-1〜V-12` という古い参照が残っていた。
  - 改善: 実行時検証の参照を `V-1〜V-13` に統一する。変更履歴で旧表記からの訂正内容を説明する箇所は履歴として保持する。
  - v2 対応結果: **対応済み**。対象2箇所を `V-1〜V-13` へ修正し、変更履歴の旧表記は訂正内容を示すため意図的に残した。

### 第2回レビュー後の検証

- Markdown 内の Swift コードブロック 19 件を結合し、`swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` で再検証した結果、エラー・警告なし。
- API ID の機械照合結果は、第6章 90 ID = 第7章 74 ID + 7.1 の分類対象外 16 ID。
- ID の重複 0、欠落 0、孤立 0、`consistent=True`。

### 第2回レビュー総合評価

追加指摘3件はすべて v2 に反映済みであり、初回レビューおよび第2回レビューに起因する未解決の文書上のブロッカーはない。実機検証 V-1〜V-13 と設計工程への引き継ぎ事項は、意図どおり未完了の将来タスクとして区別されている。
