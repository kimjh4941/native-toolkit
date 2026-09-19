# レビュー結果

- 日付: 2026-07-28
- 対象ファイル: `artifact/plans/clipboard/2026-07-27-windows-clipboard-research-v2.md`
- 機能名: clipboard
- 対象 OS: Windows
- レビュー範囲: 同期 / 非同期方針と公開 Bridge 契約

---

## 強み

- WinRT Clipboard 履歴 API を UI スレッドで開始し、`co_await` で非ブロッキングに待機して callback で完了通知する方針は、`common.md` / `windows.md` の「同期性 × スレッドアフィニティ」に一致している。
- 同期 WinRT helper は UI スレッド上の内部同期処理として維持し、任意スレッド公開の Bridge だけを `PostMessage` + callback にする区別が明確である。
- Clipboard では MTA ワーカー + `wait_for` を不採用とし、スレッドアフィニティ要件のない WinRT 非同期 API にだけ同方式を許容する説明が共通ルールと整合している。
- D-31 / D-33 / D-35 に、UI 配送、非同期例外変換、callback の exactly-once 契約が反映されている。

## 改善点

### 高優先度

- なし。

### 中優先度

- 対象: 「非 UI スレッドからの呼び出しをどう扱うか」および「受付（acceptance）を境界とする」
  - 問題: 199 行ではフォアグラウンド要件を満たさない場合にエラー返却または保留を要判断としている。一方、1840〜1848 行と D-33 は、pending 登録と UI キュー投入後の全終端状態を callback ちょうど 1 回と規定している。非 UI スレッドからの要求ではフォーカス判定が UI 受信後になるため、受付後の失敗を同期戻り値では返せない。
  - 提案: UI 受信後のフォーカス不成立は callback で Domain エラーを返すと確定する。受付定義も「pending 登録 + UI キュー投入、または UI スレッド上での直接開始の成立」とし、直接開始経路を含める。

### 低優先度

- 対象: Win32 / WinRT 比較表
  - 問題: 139 行の WinRT の「非同期」欄が `IAsyncOperation` のみとなっており、`SetContent` / `ClearHistory` などの同期 WinRT API が存在することを表現できていない。後段の実装方針は正しいため、方針上の矛盾ではなく概要表の精度の問題である。
  - 提案: 「同期 API と `IAsyncOperation` が混在。STA で非同期 API をブロッキング待機しない」へ修正する。

## 不足項目

- 同期 / 非同期方針についての不足項目はない。

## 総合評価

同期 / 非同期の採用方針は、現在の `common.md` / `windows.md` と整合しており、MTA ワーカー待機を Clipboard に適用しない判断も正しい。ただし、UI キュー投入後のフォーカス不成立時の通知方法と、UI スレッドから直接開始する場合の受付成立点が exactly-once 契約に完全には統合されていない。ここを確定すれば公開 Bridge 契約まで一貫する。
