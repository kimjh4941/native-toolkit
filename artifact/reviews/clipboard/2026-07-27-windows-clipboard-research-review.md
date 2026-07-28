# レビュー結果

- 日付: 2026-07-27
- 対象ファイル: `artifact/plans/clipboard/2026-07-27-windows-clipboard-research.md`
- 機能名: clipboard
- 対象 OS: Windows 11 以降
- 判定: **要修正**
- 別モデルによる独立レビュー: 実施済み

---

## 強み

- 前回指摘した C++17 / C++20 の区分と必須 include が明記された。
- `InvokeWinRtAsync` と履歴 helper の結果型は `ClipboardStatus` へ統一されている。
- CF_HTML は Version、実ヘッダ終端、`StartSelection` / `EndSelection` の値・ペア・範囲を検証する。
- `PastePlainText` の文字幅整合と、`PasteDib` からの `ValidateDib` 呼び出しが追加された。
- callback は「受付成立前は同期戻り値のみ、受付成立後は callback ちょうど1回」と明確に分けられた。
- `event_revoker::revoke()` の制約を正しく認識し、`event_token` による明示解除へ方針変更された。
- in-flight callback、未固定履歴の消去、DoD の逆引きも本文へ反映され、企画書全体の網羅性は高い。

## 改善点

### 高優先度

#### 1. オーバーロードされたイベント関数のアドレスを渡しており、`TryRevoke` がコンパイルできない

- 対象: 2042〜2044 行、2060〜2062 行、2077〜2084 行
- `Clipboard::HistoryChanged`、`HistoryEnabledChanged`、`RoamingEnabledChanged` には登録・token 解除・auto revoke のオーバーロードがある。
- `TryRevoke(&Clipboard::HistoryChanged, ...)` では、関数テンプレート `Remover` を推論する段階で対象オーバーロードを決定できない。
- このため D-29 の「掲載サンプルコードがコンパイル確認済み」を満たせない。

改善案:

```cpp
TryRevoke(
    [](winrt::event_token const& token) { Clipboard::HistoryChanged(token); },
    history_,
    L"HistoryChanged");
```

- 他の2イベントも同様に解除専用 lambda またはイベント別の解除関数へする。
- 検証用翻訳単位で、この呼び出しを含む `HistoryWatcher` 全体をコンパイルする。

根拠: [Clipboard.HistoryChanged の登録・解除オーバーロード](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard.historychanged)

#### 2. `Start()` の登録途中 rollback が失敗すると、解除できなかった token を失う

- 対象: 2025〜2045 行
- 3イベントの token はローカル変数に保持され、登録例外時に `TryRevoke` で rollback する。
- rollback の明示解除まで失敗すると `TryRevoke` は token を残して false を返すが、呼び出し側は結果を確認せず `Start()` から戻る。
- ローカル token はそこで失われるため、生存 handler を以後解除できない。`revokePending_` も立たないので次回 `Start()` が多重登録する。

改善案:

- 登録成功の都度 token をメンバーへ保存する。
- 登録途中で失敗した場合は、メンバー token を対象に全 rollback を試す。
- 一件でも解除できなければ `revokePending_ = true` とし、token を保持して `Start()` を拒否する。
- 全 rollback 成功時だけ token をクリアし、未開始状態へ戻す。
- 「登録途中の失敗 + rollback 解除失敗」を組み合わせた失敗注入テストを D-21 / D-34 に追加する。

#### 3. `LifecycleGuard` が未定義かつ handler に接続されておらず、in-flight callback を保護しない

- 対象: 2028〜2036 行、2066 行、2099 行、2103〜2109 行
- `LifecycleGuard` の具体的な定義が文書内にない。値メンバーとして保持するには完全型が必要なので、前方宣言だけではコンパイルできない。
- 登録 lambda は guard、weak pointer、generation のいずれも捕捉・確認していない。
- したがって `generation_.Invalidate()` を呼んでも、実際の handler の実行を止められない。
- `Stop()` 後に再度 `Start()` した場合、新しい世代を発行・有効化する処理もない。

改善案:

- `shared_ptr` で所有する具体的な lifecycle state と、世代番号を発行・無効化する API を定義する。
- 各 handler は `weak_ptr` と登録時 generation を値で捕捉し、lock と世代一致に成功した場合だけ副作用を実行する。
- `Start()` ごとに新世代を発行し、`Stop()` ではその世代を無効化する。
- 「旧世代の in-flight callback は no-op、新しい Start の callback は動作する」テストを加える。

根拠: [C++/WinRT のイベント解除と in-flight callback](https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/handle-events)

### 中優先度

#### 4. デストラクタが `Stop()` の失敗を無視し、token を保持したまま破棄できる

- 対象: 2072 行
- `~HistoryWatcher() { Stop(); }` は解除失敗を観測しても戻り値を捨てる。
- shutdown gate を経ずに破棄された場合、静的 Clipboard イベントの購読が残り、token は失われる。
- lifecycle guard が callback の副作用を防いでも、解除不能な登録自体は残る。

改善案:

- 所有 Manager の shutdown gate が成功しない限り `HistoryWatcher` を破棄しない状態契約を設計する。
- デストラクタ到達時に token が残っていれば必ずログ・assert 等で契約違反を検出する。
- 通常終了、初期化途中失敗、強制終了それぞれの所有関係を明記する。

### 低優先度

- 新たな低優先度指摘はない。

## 不足項目

- 登録途中 rollback の解除失敗時にも token を保持し、`Start` 拒否と `Stop` 再試行を確認する失敗注入テスト
- overload ambiguity を避けた、コンパイル可能な明示解除 helper
- weak state と世代番号を handler に接続した `LifecycleGuard` の完全例
- `Stop` 後の再 `Start` で新世代だけが有効になるテスト
- shutdown gate を迂回した破棄を検出する所有・寿命契約

## 総合評価

前回までの主要指摘は適切に反映され、Win32 / WinRT API 調査、CF_HTML、境界検証、非同期 callback、DoD は実装へ移せる水準に近づいた。

ただし、新しい `event_token` 版 `HistoryWatcher` には、オーバーロード解決によるコンパイル阻害、登録途中の解除失敗で token を失う状態遷移、機能していない lifecycle guard という3件の重大問題がある。

これらはイベントのリークや多重登録、破棄後 callback につながるため、3件の高優先度問題を修正してから実装へ進むべきである。
