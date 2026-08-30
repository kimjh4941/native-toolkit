# 実装結果レポート v3

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **T-03 〜 T-17 の全タスク**（v1 / v2 の T-01 / T-02 / T-11a / T-11b に続く）+ 実装レビュー指摘 7 件の修正
- 前版: `2026-08-29-macos-clipboard-implementation-feature-result-v2.md`

> v1 / v2 は T-01 / T-02 / T-11a / T-11b のみを扱う。本版はそれ以外の全タスクと、
> Codex による実装レビュー v1 の指摘反映までを記録する。

---

## 1. 実装サマリー

### 1.1 設計書由来の実装

| タスク | 内容 | 主なファイル |
|---|---|---|
| T-03 | UTI 検証 / resolver / mapper | `PasteboardResolver` / `ClipboardMappers` / `ClipboardTypeIdentifierValidator` |
| T-04 | Repository の C / R / Q / X | `ClipboardRepositoryImpl` |
| T-05 | Repository の P + 標準ペーストボード保護 | 同上 |
| T-06a | Port Mock 4 種 + Validator / Tracker + 同期 UseCase 8 本 | `Application/UseCase/` |
| T-06b | 残り UseCase 9 本 + 集約 | 同上 |
| T-07 | 全 system delegate の唯一の所有者 | `ClipboardSystemCoordinator` |
| T-08 | Manager 骨格（DI 順序 / callback + native） | `MacClipboardManager` |
| T-09 | 検出 API + DDMatch 写像 | `ClipboardDetectionMapper` |
| T-10 | 変更監視 + アクティブ連動 | `ClipboardChangeMonitor` |
| T-11c | File Promise 提供側の統合 | `FilePromiseDelegate` / `PromiseObjectLookup` |
| T-12a | 受領側の受信と正常終端 | `FilePromiseReceiptSession` |
| T-12b | 受領側の cancel と silent rollback | 同上 |
| T-13 | OP-18 の stream / 集約 async | `ReceiptCompletionGate` |
| T-14 | 貼り付け UI | `ClipboardPasteLoader` / `PasteButtonFactory` / `ClipboardPasteContainerView` |
| T-15 | 遅延データ提供 | `LazyDataProvider` |
| T-16a | Unity Bridge Swift facade + JSON 20 型 | `UnityMacClipboardManager` / `UnityMacClipboardJsonParser` |
| T-16b | Unity Bridge C 層 19 endpoint | `UnityMacClipboardManagerBridge.h` / `.m` |
| T-16c | `BridgeError` の DocC 修正 + HeaderDoc 整備 | `BridgeError.swift` |
| T-17 | DocC 整備 + 「保証しないこと」の明記 | `MacClipboardManager` ほか |

T-18（サンプルアプリ）は `design-sample-app` で別途設計するため未着手。

### 1.2 実装時の追加判断

| # | 内容 | 理由 |
|---|---|---|
| A-1 | `isValid` の判定を `UTType` 解決から `setData` の構文規則へ変更 | `UTType` はアプリ独自の未宣言 UTI を拒否するが、ペーストボードは受理する（T-03 実測） |
| A-2 | Port に `isValidFileType(_:)` を追加 | `filePromiseTypeInvalid` は Application 層で判定する契約だが、Port に手段がなかった |
| A-3 | `FilePromiseReceiptSink` を新設 | Repository が `receivePromisedFiles` を呼びつつ session を所有しないための継ぎ目 |
| A-4 | `ReceiptCompletionGate` を「attach 前の claim」を保持する状態機械に | `withTaskCancellationHandler` はキャンセル済みタスクで onCancel を即時実行するため |
| A-5 | 検出 API を `nonisolated` の入口経由に | `nonisolated async` な SDK API へ非 Sendable を渡す境界越えを、断言ではなく消去で解決 |
| A-6 | Bridge の JSON coder を呼び出しごとに生成 | 共有 `JSONEncoder` は任意スレッドからの並行使用で競合する（iOS が既に採った修正） |
| A-7 | 遅延提供を単一アイテムに限定 | `setDataProvider` は item 単位。複数アイテムは効果未測定で複雑さに見合わない |
| A-8 | `Timer` を `Task` ループへ置換（coordinator / monitor） | `@MainActor` の `deinit` は nonisolated で、非 Sendable な `Timer` に触れない |

---

## 2. 実装レビュー v1 の指摘反映

レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v1.md`
実施者: Codex（gpt-5.6-sol）。総合評価 **要修正（重大）**、high 4 件 / medium 3 件。

**7 件すべてを実コードで再現確認したうえで修正した。** 指摘はいずれも妥当であり、
反論として保留したものはない。

| ID | 指摘 | 対応 |
|---|---|---|
| H-1 | deadline が無応答 provider を打ち切れず `onPaste` が永久に返らない | `withTaskGroup` を廃止し非構造化 task + 到着順収集へ。`Progress` を保持して cancel。continuation は gate で exactly-once |
| H-2 | 静穏タイマが購読開始時に起動し、最初の到達が遅い provider の全結果を捨てる | 最初の `received` / `failed` で初めて起動。0 件到達は `.overallTimeout` |
| H-3 | ObjC Bridge がクリップボード内容を平文ログ出力 | C 層に `NTLen` / `NTScope` を新設。Swift 側にも `ClipboardLog.json` / `.scopeJson` を追加 |
| H-4 | 同じ PasteButton の 2 回目以降の押下が無反応 | exactly-once を loader 単位から押下単位（世代）へ |
| M-1 | 解放後も `<handleId>/` の空ディレクトリが残る | `discard` に staging root を渡すよう全経路で統一 |
| M-2 | Manager が Repository を直接呼び `common.md` に違反 | `GetChangeCountUseCase` を新設し、monitor / stale query の両方を経由させた |
| M-3 | 不正な `optionsJson` が既定値として受理される | 非空で decode 不能なら 1301。`localOnly: false` が黙って `true` になる経路を塞いだ |

### 2.1 テストが通っていた理由

H-1 / H-2 / H-4 の 3 件は**テストが実経路を踏んでいなかった**。

- H-1: fake source が `Task.sleep` で待つためキャンセルに応答してしまい、「callback を返さない provider」を再現していなかった
- H-2: 「開始 → 到達 → 静穏」しか試さず「開始 → 静穏 → 到達」を試していなかった
- H-4: 1 回押下しかテストしていなかった

**テストが実装と同じ思い込みを共有していた**ケースであり、別モデルによるレビューの価値が出た箇所である。
修正は再現テストを先に追加し、修正前に失敗することを確認してから行った。

### 2.2 副次的に判明した事項

H-3 の調査中、**Swift 側にも同じ漏えい**があった（`parseScope` などが scope JSON を平文出力し、
名前付きペーストボード名が漏れる）。レビューの主眼は ObjC 層だったが、同じ契約違反のため両方修正した。

---

## 3. ビルド結果

| コマンド | 結果 |
|---|---|
| `xcodebuild test -scheme MacLibrary -destination 'platform=macOS'` | **TEST SUCCEEDED** |
| `xcodebuild test -scheme UnityMacPlugin -destination 'platform=macOS'` | **TEST SUCCEEDED** |
| `xcodebuild -scheme UnityMacPlugin SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule clean build` | **BUILD SUCCEEDED** |
| `./scripts/build_xcode26_library_xcframework.sh -c release -m MacLibrary -v 1.2.0 --minimum-macos 15.0` | **ARCHIVE SUCCEEDED** |

---

## 4. テスト結果

| 対象 | 件数 | 失敗 |
|---|---|---|
| MacLibrary | 413 | 0 |
| UnityMacPlugin | 73 | 0 |

タイマ・並行系を含むため MacLibrary は 2 回連続実行で確認した。

### 4.1 strict concurrency 診断

`MIGRATION.md` §4.3 の条件（whole-module / clean / 最下流 scheme）で計測。

```
unique 173 件 / Clipboard 由来 0 件
```

本機能は `develop` に存在しない新規差分のため、`Clipboard/` 配下の診断はすべて本タスクが
追加したものになる。0 件は `MIGRATION.md` §3.3 の機能タスク DoD を満たす。

**この計測は baseline ではない**。feature branch 上の確認目的であり、`artifact/baselines/` へは保存していない。

### 4.2 whole-module でのみ検出された診断

実装中、`swiftc -typecheck` では出ず whole-module の strict build でのみ現れた診断が **4 回**あった。

| 箇所 | 診断 |
|---|---|
| `ClipboardSystemCoordinator` | `Timer?` を nonisolated deinit から参照 |
| `FilePromiseReceiptSession` | `[weak self]` 下での implicit self capture |
| `ClipboardRepositoryImpl` | 検出 API への `sending` 違反 6 件 |
| `UnityMacClipboardManager` | `static let shared` の非 Sendable、`sending 'body'` |

`MIGRATION.md` §4.3 が whole-module を必須条件にしている理由の実例である。

### 4.3 未実施

- MT-01〜MT-07（手動確認）: 実機未実施
- MT-08（Mac + iPhone の Universal Clipboard）: 実機未実施
- MT-09: 判定保留（RK-22。アラートがどの構成でも再現しなかった）

---

## 5. 設計書への還元

実装で判明した差分をすべて v7 へ反映済み。機械照合は **22 検査すべて通過**。

| 項目 | 反映先 |
|---|---|
| RK-24: read は write の上位集合になり得る | §7.6 / リスク表 / IT-50 / DoD |
| RK-25: `detectMetadata` はテキストのみで失敗する | §7.10 / リスク表 |
| `isValid` の判定基準（実測した `setData` の規則） | §8.2 |
| Port の `isValidFileType` | §8.2 |
| `FilePromiseReceiptSink` | §6.5.1 |
| gate の「attach 前 claim」保持 | §7.12 |
| 検出 API の隔離 | §7.10 |
| parser の並行安全性 | §8.4.6 |
| **R-H1 / R-H2 / R-H3 / R-H4 / R-M1 / R-M2 / R-M3**（レビュー指摘） | §4.2 / §6.5.1 / §7.11 / §7.12 / §8.4.4 / §8.4.5 |
| UseCase 本数 17 → 18（`GetChangeCountUseCase` 追加） | 冒頭「用語」/ ファイルツリー |
| 新規テスト PT-09〜13 / IT-51〜53 / BT-24〜25 | §12 |

---

## 6. Definition of Done 達成状況

| 項目 | 状態 |
|---|---|
| 設計 v7 の T-01〜T-17 実装 | ○ |
| 単体・統合・Bridge・並行性テスト全通過 | ○ |
| 差分が strict concurrency 診断を増やさない | ○（Clipboard 由来 0 件） |
| `public` シンボルすべてに英語 DocC | ○ |
| 「保証しないこと」の DocC 明記 | ○（テストで固定） |
| 全メソッド先頭の `Log.d` と §4.2 の秘匿 | ○（C 層まで含め修正済み） |
| Unity Bridge に Delegate 実装が存在しない | ○ |
| `MacLibraryExample` から全公開 OP を実行 | **未**（T-18） |
| MT-01〜MT-09 の手動確認 | **未** |

---

## 7. 残作業

1. **再レビュー**: 本版と修正を対象に実装レビュー v2 を実施する
2. **T-18**: `design-sample-app` でサンプルアプリを設計し、実装する
3. **手動確認**: MT-01〜MT-08 を実機で実施する
4. `MIGRATION.md` の `swift6-migration` は別トピック。本タスクの範囲外

---

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答: 未回答（再レビューを先に実施する方針）
