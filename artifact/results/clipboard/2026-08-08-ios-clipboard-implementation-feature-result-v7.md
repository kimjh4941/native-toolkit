# 実装結果レポート v7（実装レビュー v6 反映）

> **Errata（2026-08-08）**
> - 「早期失敗10経路」は、正確には **実装callsite 10箇所／公開早期失敗分岐14経路**。
> - 公開分岐は、`deliverInvalidRequest`を共有する5経路（`copy` / `append` parse失敗 / `clear` /
>   `removePasteboard` / `startObserving`）、`append` options拒否1経路、JSON callback 8経路である。
> - 下表のoperation parse失敗から`append`が欠落していた。実装には含まれており、文書だけの誤り。
>
> 訂正: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v6.md`
- 前版: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md`
- 追加参照: `artifact/MIGRATION.md`
- ブランチ: feature/NTKIT-14

---

## 1. 実装サマリー

### 1.1 H-01: 早期失敗経路の callback が呼出元スレッドで実行されていた

**指摘は正しく、実バグだった。** `@Sendable` は closure を isolation 間で安全に「運べる」ことを
表すだけで、**実行 executor を main actor に固定しない**。正常系は `Task { @MainActor in }` に
入るが、parse / validation 失敗はその手前で return しており、handler を呼出元スレッドで
同期実行していた。

Unity の C entry point は main thread 拘束ではないため、**background thread から不正 request を
渡すと callback も background thread で実行される**。これは façade の DocC、Bridge header、
設計書が規定する「全経路 main thread」に違反する。

v6 で「Bridge callback が main thread で exactly-once」「H-01 解消」と記載したが、
**診断解消については正しく、実行時契約については誤りだった**。

#### 修正

main actor 経由の共通 delivery helper を 2 つ設け、**すべての早期失敗経路を通した**。

```swift
/// `@Sendable` on the handler makes it *safe to transfer* between isolation domains — it does
/// not by itself pin execution to the main actor. That is this helper's job.
private func deliverOnMain(
    _ handler: (@Sendable (Bool, String?, String?) -> Void)?,
    isSuccess: Bool, errorCode: String?, errorMessage: String?
) {
    Task { @MainActor in handler?(isSuccess, errorCode, errorMessage) }
}

private func deliverOnMain(_ handler: (@Sendable (String) -> Void)?, json: String) {
    Task { @MainActor in handler?(json) }
}
```

適用箇所:

| 種別 | 経路 | 対応 |
|---|---|---|
| operation callback | `copy` / `clear` / `removePasteboard` / `startObserving` の parse 失敗 | `deliverInvalidRequest` の内部を helper 経由に変更 |
| operation callback | `append` の options 拒否（独立した 2 つめの guard） | 直接呼出しを helper に置換 |
| JSON callback | `read` / `readData` / `getSnapshot` / `createPasteboard` / `detectPatterns` / `detectValues` / `loadItem` / `checkForegroundChange` の parse 失敗 8 箇所 | `handler?(invalidRequestJSON())` を helper 経由に置換 |

JSON はヘルパー呼び出し前にシリアライズし、isolation 境界を越えるのは `String` だけにしている。
**直接 handler を呼ぶ早期 return は 1 箇所も残っていない。**

#### 追加テスト（4 ケース）

レビュー指摘どおり、**background queue + malformed request** の組み合わせを分類ごとに追加した。
いずれも「回数 1」と「main thread」を同時に assert する。

| テスト | 対象 |
|---|---|
| `malformedOperationRequestFromBackgroundIsDeliveredOnTheMainThread` | operation callback（`copy`） |
| `rejectedAppendOptionsFromBackgroundAreDeliveredOnTheMainThread` | `append` の options 拒否（別 guard） |
| `malformedJSONCallbackRequestFromBackgroundIsDeliveredOnTheMainThread` | JSON callback（`getSnapshot`） |
| `malformedObserveRequestFromBackgroundDeliversStartHandlerOnTheMainThread` | observe 開始失敗（startHandler 1 回 main thread / changeHandler 0 回） |

既存の `malformedRequestStillDeliversExactlyOnce` にも main thread の assert を追加した。

いずれも修正前の実装では **`allOnMainThread` が false になって失敗する**回帰テストである。

### 1.2 M-01: `@Sendable` の検証範囲の記述を訂正

v6 の「コンパイラが全呼び出し側で検証」は Objective-C caller には成立しない。
`@Sendable` は Swift 側の型検査にのみ有効であり、ObjC block の capture を
Swift concurrency checker が全件検証するわけではない。

result / MIGRATION.md を次のように区別して記載し直した。

| 呼び出し側 | 担保手段 |
|---|---|
| Swift caller | `@Sendable` によりコンパイラが型検査する |
| **Objective-C caller** | **コンパイラ検証は及ばない。** block の capture 監査（C 関数ポインタのみ）と Bridge 契約テストで担保する |

あわせて「`@Sendable` は実行 executor を main actor に固定しない」ことを MIGRATION.md §6 に明記した。

### 1.3 M-02 / L-01: 観測段階の表記

MIGRATION.md §4.2 で、領域別表（初期観測 129 件）とカテゴリ別表（126 件）が同じ段階として
並んでいた。カテゴリ表を **「局所 3 件修正後（案 C 適用前）・計 126」** と明記し、
領域別表とは観測段階が異なることを注記した。

result v6 §1.3(b) の「修正前 126 件」も同様に段階が曖昧だったため、同じ表記に統一する。

---

## 2. 変更ファイル

### 2.1 変更（実装）

- `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift` — H-01（delivery helper 2 種の追加と早期失敗 10 経路の置換）

### 2.2 変更（テスト）

- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerCallbackContractTests.swift` — H-01（+4 ケース、既存 1 ケースに main thread assert 追加）

### 2.3 変更（ドキュメント）

- `artifact/MIGRATION.md` — M-01（担保範囲の区別、`@Sendable` の意味の明確化）、M-02（観測段階の明記）、確認事項に早期失敗経路を追加

### 2.4 変更なし

- Objective-C Bridge（`.h` / `.m`）
- `IosLibrary` のソース（本ラウンドの変更は `UnityIosPlugin` のみ）
- 既存 Notification / Dialog / Share のソース

---

## 3. 検証結果

### 3.1 Swift 5 + strict concurrency complete（whole-module / clean）

`UnityIosPlugin` scheme。集計は MIGRATION.md §4.3 の正規コマンドによる unique 行数。

| 段階 | ビルド | error | unique warning | うち Clipboard |
|---|---|---|---|---|
| v4 時点 | 成功 | 0 | 129 | 19 |
| 局所 3 件修正後（案 C 適用前） | 成功 | 0 | 126 | 16 |
| 案 C 適用後（v6） | 成功 | 0 | 110 | 0 |
| **本修正後（v7）** | **成功** | **0** | **110** | **0** |

delivery helper の追加による診断の増減はない。

### 3.2 ビルドとテスト

| 対象 | 結果 |
|---|---|
| UnityIosPlugin 通常ビルド | BUILD SUCCEEDED（ObjC Bridge 無変更で成功） |
| UnityIosPlugin tests | **83 passed / 0 failed**（v6: 79） |
| IosLibrary tests | 186 passed / 0 failed（v6 で確認済み。**本ラウンドで `IosLibrary` に変更はないため再実行していない**） |
| xcframework | 両モジュール ARCHIVE SUCCEEDED（IosLibrary build 14 / UnityIosPlugin build 13） |

---

## 4. Definition of Done（再評価）

### レビュー v6 項目
- ○ H-01 全経路 main thread の実行時契約（早期失敗経路を含む）
- ○ M-01 `@Sendable` の検証範囲の記述訂正
- ○ M-02 MIGRATION.md の観測段階の分離
- ○ L-01 result の段階名の明確化

### 実装
- ○ Clipboard 差分が Swift 6 strict 診断を新規追加しない（0 件）
- ○ Clipboard 差分が通常ビルド warning を新規追加しない
- ○ **Bridge callback が正常・不正の全経路で main thread から exactly-once**
- ○ `nil` callback 許容、start/stop 境界の非交差
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
- △ 単体テスト（186 + 83 = 269 件 green）。設計 U-01〜U-148 の全件網羅ではない
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
| 4 | Notification / Dialog / Share への案 C 一括適用と、同 3 機能の早期失敗経路の同種監査 | 移行タスク本体 |
| 5 | macOS の Swift 5 readiness 計測 | 移行タスク本体 |

> 4 について: 今回の欠陥は Bridge 共通の構造に由来する可能性が高い。案 C を他機能へ適用する際は、
> **`@Sendable` 付与だけで済ませず、早期失敗経路の delivery も同時に監査する**こと。

移行管理全体の着手順は `artifact/MIGRATION.md` §8 を参照。

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
