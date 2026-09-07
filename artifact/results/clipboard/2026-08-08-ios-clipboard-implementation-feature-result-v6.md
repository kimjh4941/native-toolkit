# 実装結果レポート v6（実装レビュー v5 反映）

> **Errata（2026-08-08）**
> - 「Bridge callback が main thread で exactly-once」「H-01 解消」は、**strict 診断の解消については
>   正しいが、実行時契約については誤り**。parse / validation 失敗の早期 return 経路が handler を
>   呼出元スレッドで同期実行していた。**v7 で修正済み**。
> - 「コンパイラが全呼び出し側で検証」は **Objective-C caller には成立しない**。`@Sendable` は
>   Swift 側の型検査にのみ有効で、実行 executor を main actor に固定するものでもない。v7 §1.2 で訂正。
> - §1.3(b) の「修正前 126 件」は「**局所 3 件修正後（案 C 適用前）126 件**」が正確。
>
> 訂正: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v7.md`

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v5.md`
- 前版: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md`
- 追加参照: `artifact/MIGRATION.md`
- ブランチ: feature/NTKIT-14

---

## 1. 実装サマリー

### 1.1 H-01: Bridge callback の actor 境界（受け入れブロッカー）

`UnityIosClipboardManager` に残っていた 16 件の `sending 'handler'` 診断を **0 件**にした。

`artifact/MIGRATION.md` §6 の先行設計として 3 案を比較し、**案 C** を採用した。

| 案 | 内容 | 評価 |
|---|---|---|
| A | ObjC Bridge 側で main queue へ dispatch し、Swift facade 全体を `@MainActor` にする | 境界は明快だが、C 文字列と block の寿命、全 Bridge API への影響、Unity 側の呼び出し規約まで再検証が必要。影響範囲が大きい |
| B | callback を main actor へ転送する共通 `@unchecked Sendable` wrapper | 差分は小さいが、要求を実装内部の unchecked な断言として隠す |
| **C（採用）** | **handler パラメータの型に `@Sendable` を付与し、要求を API 境界で表明する** | unchecked な抜け道なし。実行時の変更ゼロ。コンパイラが全呼び出し側で検証。ObjC からは通常の block のままで互換 |

```swift
// before
public func copy(requestJson: String?, handler: ((Bool, String?, String?) -> Void)?)
// after
public func copy(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?)
```

**採用理由**

- Bridge の `.m` が渡す block は **C 関数ポインタしかキャプチャしていない**（`clipboardCopy` 等）。
  どのスレッドから呼んでも安全であり、`@Sendable` の表明は事実に即している
- 既存の DocC が既に「callback は常に main thread で呼ばれる」と規定しており、
  `@Sendable` はその契約を型で表現したにすぎない
- 案 B のように `@unchecked Sendable` で断言を隠すより、要求を API 境界に出すほうが検証可能

適用箇所: `UnityIosClipboardManager` の 15 endpoint すべて（handler / changeHandler / startHandler
および `deliverInvalidRequest` の内部ヘルパーを含む 19 箇所）。

**Objective-C 互換性**: `.m` は無変更でビルド成功。`@Sendable` は block 表現に影響しない。

**追加テスト**: `UnityIosClipboardManagerCallbackContractTests`（5 ケース）

- バックグラウンドスレッドからの呼び出しでも handler が **main thread で 1 回だけ**届く
- malformed request でも handler が 1 回だけ届く
- `nil` handler を渡しても trap しない（3 endpoint で確認）
- 監視の start → stop 境界で handler が交差せず、それぞれ 1 回ずつ main thread で届く
- malformed な observe 要求で startHandler が 1 回届き、changeHandler は 0 回

### 1.2 M-01: ISO 8601 シリアライズ側の回帰テスト

formatter 置換は `serializeDetectedValues` の `calendarEvents.startDate` / `endDate` 出力も
変更していたが、テストは入力 parse しか固定していなかった。

`calendarEventDatesSerializeAsRoundTrippableISO8601` を追加し、次を固定した。

- 出力が小数秒を含むこと（`.` を含む）
- UTC 表現であること（`Z` で終わる）
- `nil` の日時が JSON `null` になること（空文字列やキー欠落ではない）
- 出力値を自前の parser で再 parse でき、**元の `Date` と一致**すること（往復）

### 1.3 M-02: 診断比較の母集団と集計単位

**(a) 母集団**

result v5 は iOS の Swift 5 strict 129 件と、iOS 13 + macOS 8 = 21 件を直接比較していた。
対象 scheme もプラットフォームも異なるため、この差分を「未診断数」とは評価できない。訂正する。

| 比較 | Swift 5 + strict | Swift 6 mode |
|---|---|---|
| iOS（`IosLibrary` scheme） | — | 13 |
| iOS（`UnityIosPlugin` scheme・下流含む） | 129 | 計測不能（依存先が先に失敗） |
| macOS（`MacLibrary` scheme） | 未計測 | 8 |

Apple 全体同士の比較には macOS の Swift 5 readiness 取得が必要であり、未実施である。
早期停止による未診断の存在は事実だが、**その規模を 129 − 21 = 108 と数値化することはできない**。

**(b) 集計単位**

v5 / MIGRATION.md の「`sending` 34 / `static property` 8」は、Clipboard パスのみを対象に
`sort -u` を掛けずに raw 出現を数えたものだった。レビューの「`sending` 39 / `static property` 14」
とは**正規化単位も対象範囲も異なる**。

正規コマンドを `artifact/MIGRATION.md` §4.3 に明記し、以後はこれで統一する。

```bash
grep -oE "/[^ ]*\.swift:[0-9]+:[0-9]+: (warning|error): .*" "$LOG" \
  | sed 's|.*/ios/||' | sort -u
```

単位は「**フルソース位置 + 診断文の unique 行**」であり、出現回数ではない。
この単位で数え直すと、修正前 126 件の内訳は `sending 'X'` 32 +
`sending value of non-Sendable type 'X'` 7 = 39、`static property` 14 となり、
レビューの計測値と一致する。

### 1.4 L-01: `isolated deinit` の評価は撤回しない

result v4 の Errata を修正し、撤回対象を「Clipboard 全体 0 件」の評価に限定した。
`isolated deinit` 起因の診断は Swift 5 strict の再計測でも存在せず、個別主張は現在も成立する。
当時の計測方法では、それを Clipboard 全体 0 件の根拠にできなかった、という限定に改めた。

### 1.5 L-02: build number の記録

| モジュール | v4 時点 | v5（xcframework 再生成後） | **v6（現在）** |
|---|---|---|---|
| IosLibrary | 11 | 12 | **13** |
| UnityIosPlugin | 10 | 11 | **12** |

由来は `scripts/build_ios_library_xcframework.sh` の自動インクリメント仕様。

---

## 2. 変更ファイル

### 2.1 変更（実装）

- `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift` — H-01（`@Sendable` 付与 19 箇所）

### 2.2 変更（テスト）

- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerCallbackContractTests.swift` — 新規（5 ケース）
- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift` — M-01（+1 ケース）

### 2.3 変更（ドキュメント）

- `artifact/MIGRATION.md` — 案 C の決定記録、集計の正規化単位、母集団を揃えた比較、着手順の更新
- `artifact/results/clipboard/..._result-v4.md` — L-01 の Errata 限定化

### 2.4 変更なし

- Objective-C Bridge（`.h` / `.m`）
- 既存 Notification / Dialog / Share のソース

---

## 3. 検証結果

### 3.1 Swift 5 + strict concurrency complete（whole-module / clean）

`UnityIosPlugin` scheme。集計は §1.3(b) の正規コマンドによる unique 行数。

| 段階 | ビルド | error | unique warning | うち Clipboard |
|---|---|---|---|---|
| v4 時点 | 成功 | 0 | 129 | 19 |
| 局所 3 件修正後（v5） | 成功 | 0 | 126 | 16 |
| **案 C 適用後（v6）** | **成功** | **0** | **110** | **0** |

**Clipboard 由来の診断は 0 件。** 残る 110 件はすべて既存 Dialog / Notification / Share 由来で、
移行タスク本体の対象である。

### 3.2 ビルドとテスト

| 対象 | 結果 |
|---|---|
| IosLibrary 通常ビルド | BUILD SUCCEEDED |
| UnityIosPlugin 通常ビルド | BUILD SUCCEEDED（ObjC Bridge 無変更で成功） |
| IosLibrary tests | **186 passed / 0 failed** |
| UnityIosPlugin tests | **79 passed / 0 failed**（v5: 73） |
| xcframework | 両モジュール ARCHIVE SUCCEEDED（IosLibrary build 13 / UnityIosPlugin build 12） |

---

## 4. Definition of Done（再評価）

### レビュー v5 項目
- ○ H-01 Bridge callback actor 境界（Clipboard 診断 0 件）
- ○ M-01 ISO 8601 シリアライズの回帰テスト
- ○ M-02 診断比較の母集団と集計単位の訂正
- ○ L-01 `isolated deinit` の評価を撤回対象から除外
- ○ L-02 build number の記録

### 実装
- ○ **Clipboard 差分が Swift 6 strict 診断を新規追加しない**（0 件）
- ○ Clipboard 差分が通常ビルド warning を新規追加しない
- ○ Bridge callback が main thread で exactly-once、`nil` 許容、start/stop 境界を保つ
- ○ Objective-C Bridge が無変更でコンパイル成功
- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ 公開エラーメッセージ・ログが機微情報を含まない
- ○ 非同期の timeout / cancel / exactly-once が P-11 と P-16 で同一実装を共有
- ○ 全 kind にサイズ上限。検証不能を成功にしない
- ○ 一時 file が失敗 / キャンセル / タイムアウト / loader 解放で削除される
- ○ D-16 の `isolated deinit` を 4 型すべてに実装
- ○ 既存 Notification / Dialog / Share のファイルに変更がない
- × I-10（target 全体の strict green）— 別タスクへ分離する方針で合意済み。設計 v5 未作成

### テスト
- △ 単体テスト（186 + 79 = 265 件 green）。設計 U-01〜U-148 の全件網羅ではない
- × I-08（Bridge 15 endpoint end-to-end）
- × I-09（`ClipboardRedaction` 独立モジュール境界）
- × 手動確認 M-01〜M-16（実機必須）

---

## 5. 残件

| # | 内容 | 前提 |
|---|---|---|
| 1 | 設計 v5 での I-10 分離 | 移行タスクのチケット ID 採番 |
| 2 | I-08 / I-09 | - |
| 3 | T-00 / T-12 / T-13（実機・サンプルアプリ） | - |
| 4 | Notification / Dialog / Share への案 C 一括適用 | 移行タスク本体 |
| 5 | macOS の Swift 5 readiness 計測 | 移行タスク本体 |

移行管理全体の着手順は `artifact/MIGRATION.md` §8 を参照。

**受け入れブロッカーだった H-01 は解消した。** 残るのは設計正本の更新（1）と、
当初から実機・別ワークフロー待ちの項目（2〜3）である。

---

## 6. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
