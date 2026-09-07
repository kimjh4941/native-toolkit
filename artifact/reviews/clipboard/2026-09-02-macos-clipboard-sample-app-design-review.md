# レビュー結果

- 日付: 2026-09-02
- 対象ファイル: `artifact/designs/clipboard/2026-08-30-macos-clipboard-sample-app-design-v1.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- 参照設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 参照実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md`

---

## 強み

- OP-01〜OP-20 と 12 セクションの対応が明示され、通常操作、異常系、File Promise、Paste Control まで画面要件を広く網羅している。
- `MacClipboardManager` の native API を `MacLibrary` だけから使い、`UnityMacPlugin` や AppKit API による機能の再実装へ逃げない依存方針は正しい。
- `ClipboardContent` が UTI と `Data` の辞書であること、append が ownership を必要とすること、File Promise の終了がヒューリスティックであることなど、主要な公開契約を正しく反映している。
- named / unique pasteboard、`localOnly`、監視中状態、promise / receipt handle の保持件数を画面で観察可能にする方針は、API の寿命と状態を理解しやすい。
- Application Support を既定受領先とし、Powerbox 経由の選択先を別途検証するサンドボックス方針は妥当である。
- drag harness の未解決点を隠さず、ライブラリの promise 実装を通らないサンプル側の代替を禁止した判断自体は正しい。
- MT-01〜MT-09 と MS-01〜MS-09 により、機能設計由来の手動確認とサンプル固有の確認を分けている。

## 改善点

### 高優先度

#### 1. 現行 public API では drag harness を開始できず、T-18 の必須条件が実装不能

- 対象: §4.3、§5.4、§6.2、§8（209、242〜250、376〜401、450〜459 行）
- 計画は OP-16 で `.drag` pasteboard に promise を書いた後、`beginDraggingSession` を開始する案を「要検証」としている。
- しかし `NSView.beginDraggingSession(with:event:source:)` は `[NSDraggingItem]` を必須とし、`NSDraggingItem` の designated initializer は `NSPasteboardWriting` を実装する writer を要求する。既存の drag pasteboard 自体を渡す入口はない。
- 現行 `provideFilePromise` が返すのは不透明な `FilePromiseHandle` だけであり、coordinator が所有する `NSFilePromiseProvider` は public API から取得できない。したがって第 1 案は「セッション開始時に promise が失われる可能性」があるのではなく、その前段の `NSDraggingItem` を構築できない。
- この状態では「`MacLibrary` を変更しない」と「MT-05 用 drag harness を含める」を両立できず、design-sample-app workflow の依存方向確認を「問題なし」と判定した §5.4 も成立しない。
- 実装着手前に機能設計へ戻し、provider/delegate の所有権を coordinator に残したまま handle からドラッグを開始できる native API を設計すること。例えば Manager / Presentation 層に `beginFilePromiseDragging(...)` 相当を置き、provider 自体は公開しない形が考えられる。
- API を追加しない場合は、T-18 / MT-05 の完了条件を正式に変更する必要がある。「通常セクションを先に実装し、drag は最後に試す」は implementation-ready な解決にならない。

### 中優先度

#### 1. OP-18 の公開形態が曖昧で、1 overload を数え落としている

- 対象: §1.1、§6.1「File Promise - Receive」（36、342〜353 行）
- 計画は callback / stream / async の 3 形態としているが、実装には次の 4 overload がある。
  1. native event closure を受け、同期 `throws` で handle を返す形
  2. event closure と completion callback を受ける Unity bridge 向け public 形
  3. `FilePromiseEventSubscription` を返す stream factory
  4. `FilePromiseReceipt` を返す aggregate async 形
- `ReceiveCallback` が 1 と 2 のどちらを指すかを明記し、もう一方をサンプル対象外にするなら「全公開 OP」は operation ID 単位であり、全 public overload の実演を意味しないと定義すること。全 public overload を対象とするなら 4 操作へ分けること。

#### 2. Observe、stream、aggregate async の画面寿命と cleanup が不足している

- 対象: §6.1「Observe」「File Promise - Receive」、§6.4、MS-05 / MS-06（321〜353、409〜415、442〜443 行）
- `onDisappear` の本文は OP-17 / OP-20 による handle 解放しか定義しておらず、MS-05 が要求する `stopObserving()` を含んでいない。
- aggregate async 版は receipt handle を外部へ返さないため OP-20 では止められず、呼び出し `Task` を保持して `cancel()` する必要がある。stream の `for await` consumer Task も画面破棄時に明示的に止める必要がある。
- callback / stream の handle は terminal event 後に配列から除去しないと、実セッションが終わっても保持件数表示が 0 にならない。
- `observationActive`、promise handles、receipt handles、stream / aggregate Tasks をまとめた lifecycle 表を追加し、通常終端、明示 cancel、画面破棄の各 cleanup 順を定義すること。

#### 3. `(expect error)` の成功条件が共通 runner と一致しない

- 対象: §2.2、§5.1、§6.1、MS-02（93〜95、215〜222、256〜374、439 行）
- 共通 `run` は `ClipboardError` を失敗として赤表示する一方、期待エラーボタンは指定 errorCode が返ればテストとして成功である。
- `runExpectingError(expectedCode:)` を別に定義し、「指定コードを throw = 成功」「成功してしまう = 失敗」「別コード = 失敗」を結果へ表示すること。これがないと MS-01 の成功/失敗表示と MS-02 の契約確認が衝突する。

#### 4. File Promise の必須 `source` と再現可能な fixture が未定義

- 対象: §6.1「File Promise - Provide」（332〜340 行）
- `FilePromiseRequest` は `fileTypeIdentifier` / `fileName` に加えて `source` が必須だが、`.writer` と `.snapshot` のどちらを使い、何を書き出すかがない。
- 正常系では固定バイト列を書く `.writer`、または app-owned fixture を使う `.snapshot` を明記し、可能なら両 source case を別操作で実演すること。
- invalid type は実装テストと同じ `public.item` などへ固定すること。現在の「`public.url` 以外の非 `public.data` 型」は曖昧で、再現入力になっていない。

#### 5. Detection の入力と pattern set が未定義で、結果を再現できない

- 対象: §6.1「Detect」、要検証 3（310〜319、469 行）
- `DetectPatterns` / `DetectValues` に渡す pattern set と事前 clipboard fixture がなく、現在の pasteboard 内容によって結果が変わる。
- pattern 検出用の固定 text、単一値確認用 fixture、metadata failure 用 plain text、metadata success 用 file reference を定義し、各ボタンが arrange → detect を一続きで行うようにすること。
- 値を出さずに field ごとの件数と optional の有無だけを表示する formatter も明記すること。

#### 6. Active scope が「すべての操作」に作用するという説明は OP-19 と整合しない

- 対象: §3.2、MS-03（155〜164、440 行）
- `makePasteButton` には scope 引数がなく、Paste Control は general pasteboard を使う。Active scope は OP-19 へ反映できない。
- 画面に Paste Control は general 固定と注記し、MS-03 を「scope 引数を持つ全操作」へ限定すること。

#### 7. `PasteButtonHost` で throwing factory を扱う契約がない

- 対象: §2.4、§6.1「Paste Control」（123〜125、355〜364 行）
- `NSViewRepresentable.makeNSView` は throw できないが、OP-19 は `throws -> NSView` である。
- Host の initializer で valid view を生成して保持する、または fallback `NSView` と error callback を持つなど、生成失敗を Result へ渡す方式を確定すること。invalid-type 操作は Host を作らず Manager を直接呼ぶ形に分けられる。
- `dismantleNSView` / View 破棄によって進行中 paste load が確実にキャンセルされる確認も追加すること。

#### 8. 自動テスト、accessibility contract、再現コマンドがない

- 対象: §4、§7（186〜210、418〜446 行）
- 既存プロジェクトには unit / UI test target があり、今回の 12 セクションは操作数と非同期状態が多いが、計画は手動確認だけである。
- 少なくとも fixture の UTI / byte count、期待 errorCode と action marker、結果 formatter を unit test 対象にし、Main Menu → Clipboard 画面の smoke UI test を追加すること。
- section、button、result、observe status、handle count に一意な accessibility identifier を定義し、pasteboard を共有する UI test の直列化方針を明記すること。
- `xcodebuild clean test` を含む再現コマンドと、警告 0、`git diff --check`、`UnityMacPlugin` import 0 件の合格条件を追加すること。

#### 9. 秘匿方針が `updateResult` と `ClipboardLog` の実挙動に一致しない

- 対象: §2.2〜§3.4、MS-08（88〜95、111〜119、166〜182、445 行）
- 既存 `ShareSampleView.updateResult` は result 全文をログへ出すため、そのまま踏襲すると画面用 errorMessage や formatter の内容までログへ複製する。
- `ClipboardError.errorMessage` の一部は入力値や system reason を含む。画面表示契約を維持しても、ログは marker、成功/失敗、errorCode だけに限定する必要がある。
- `ClipboardLog.path` は last path component、file URL は basename、非 file URL は scheme / host を出すため、MS-08 の「パス・URLが出ない」とも一致しない。
- sample 用 `updateResult` は payload をログに出さず、要件は「payload、完全パス、query、pasteboard 名を出さない」へ正確に直すこと。ファイル名や host も禁止するなら、既存 `ClipboardLog.path/url` ではなく長さ・種別だけの sample formatter が必要である。

### 低優先度

#### 1. `project.pbxproj` は新規 Swift ファイル登録のためには変更不要

- 対象: §4.2（197〜203 行）
- 対象 project は `PBXFileSystemSynchronizedRootGroup` を使用しており、対象フォルダに追加した Swift ファイルは自動で target に含まれる。
- test plan、scheme、build setting など別の設定変更がなければ `project.pbxproj` を非変更へ移すこと。

#### 2. 既定受領ディレクトリの作成と受領ファイルの cleanup がない

- 対象: §5.3（233〜240 行）
- `Application Support/ClipboardReceive/` は通常は最初から存在せず、OP-18 は存在しない directory を 1520 で拒否する。
- `createDirectory(..., withIntermediateDirectories: true)` を行う時点、受領ファイルを表示後に残すか削除するか、次回起動時の cleanup 方針を明記すること。

#### 3. T-18 の参照節が誤っている

- 対象: 基本情報（14 行）
- T-18 は設計書 §17 ではなく、現行 v7 のタスク表にある §13 を参照している。正しい節または安定した T-18 ID だけの参照へ直すこと。

## 不足項目

- MT-05 を成立させる native drag API の機能設計側の確定判断
- OP-18 の 4 overload とサンプル対象範囲の対応表
- Observe、callback / stream / aggregate receive、handle、Task の lifecycle 表
- 期待エラー専用 runner
- `.writer` / `.snapshot` の具体的 File Promise fixture
- deterministic な Detection fixture と formatter
- Paste Control が general scope 固定である旨
- `PasteButtonHost` の throwing factory 変換契約
- Application Support directory の作成と受領ファイル cleanup
- accessibility identifier、自動テスト、直列化、検証コマンド
- 画面 payload をログへ複製しない sample 固有の秘匿契約

## 総合評価

20 OP の整理、既存サンプルとの整合、サンドボックス、秘匿、resource lifetime への意識は高く、通常の clipboard 操作に関する骨格は良好である。

ただし T-18 の必須条件である drag harness は、現行 public API では `NSDraggingItem` に必要な writer を取得できないため構築できない。これは実装中の要検証事項ではなく、機能設計と公開 API の不足である。**現状のままサンプル実装へ進むべきではない。**

まず高優先度 1 件を機能設計側で解決し、その後に OP-18 の overload / task cleanup、期待エラー、deterministic fixture、PasteButtonHost、自動テストと秘匿契約を具体化すれば、実装着手可能な計画になる。
