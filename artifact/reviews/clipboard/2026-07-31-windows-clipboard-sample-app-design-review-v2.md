# レビュー結果

- 日付: 2026-07-31
- 対象ファイル: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v2.md`
- 文書種別: サンプルアプリ設計
- 機能名: clipboard
- 対象 OS: Windows
- 前回レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review.md`

---

## 強み

- 前回レビューの H1〜H3、M1〜M5、L1〜L2を対応表と実装コードによる検証結果に落とし込み、修正理由を追跡できる。
- 任意スレッド対応の同期 Bridge と同期 I/O を worker へ移し、owner UI thread 限定 APIと履歴の受付 APIを UI スレッドに残す分類は、`windows.md` の同期・非同期方針と整合している。
- `uninitClipboardManager` の `BOOL` と `pError` を両方表示し、pending callback の配送、`CanDestroy`、2 回目の Uninitialize までを手動確認へ追加している。
- Clear 後の `FORMAT_UNAVAILABLE(5)`、unknown request ID の `INVALID_PARAMETER(1)`、現行 `PickPreferredFormat` の固定優先順が、実装コードどおり具体化されている。
- PasteImage の構造体参照前チェック、二相バッファ取得の判定、遅延 provider のサイズ一致、request JSON の callback 内コピーが明記され、安全な呼び出し境界になっている。
- `windows/UnityWindowsPlugin`、manifest、App、filters、solution を変更しない方針を維持し、サンプルの依存方向と変更範囲が明確である。
- HTML の preferred format 対象外をサンプル側で補正せず、機能側への報告事項として分離した判断は適切である。

## 改善点

### 高優先度

#### H1. `g_managerInitialized` の boolean では「利用可能」と「shutdown 中」を区別できない

対象:

- 265〜282 行: process-lifetime 初期化状態
- 350〜356 行: Uninitialize が `FALSE` の場合も true を維持
- 549 行: `EnsureInitialized()` が boolean だけを参照
- 642〜645 行: pending 中の shutdown と再初期化

最初の `uninitClipboardManager` が `FALSE` + `CANCELED` / `BUSY` を返した時点で、Manager の `initialized_` は true のままだが lifecycle gate は closed であり、新規 API を受け付けられない。現在の設計は `g_managerInitialized == true` を維持するため、`EnsureInitialized()` が Copy / Paste / History を許可し、それらは `NOT_INITIALIZED` で失敗する。また、InitializeManager を押すと Bridge は冪等成功を返すため boolean は true のままだが、gate は再開しない。

これは v2 自身が 40 行と 645 行で説明している状態であり、boolean をそのまま「操作可能」の判定に使う設計と矛盾する。

修正案:

- process-lifetime state を少なくとも次の 3 状態にする。
  - `Uninitialized`: Init 前、または Uninit が `TRUE` で完了
  - `Ready`: Init 成功後で新規操作を受け付け可能
  - `ShuttingDown`: owner UI thread の Uninit が `FALSE` となり、gate が閉じている
- 通常操作の guard は `Ready` の場合だけ通す。
- `ShuttingDown` では `CanDestroy` と Uninitialize 再試行だけを許可し、Initialize と新規 request を拒否して再試行手順を表示する。
- worker thread からの Uninitialize が `WRONG_THREAD` になった場合は gate が閉じていないため `Ready` を維持する。単に `FALSE` かどうかではなく、呼び出し経路とエラーに基づいて遷移させる。
- `OnNavigatedTo` の状態表示も Initialized / Uninitialized の二値ではなく、Ready / Shutting down / Uninitialized を表示する。

#### H2. worker 完了処理が `m_busy` とページ状態へ到達できず、記載どおり実装できない

対象:

- 258 行: ページメンバ `m_busy`
- 260〜263 行: worker にページ参照を渡さず、weak TextBlock だけで UI 反映
- 453〜470 行: `RunAsync` の疑似コード
- 473〜475 行: UI 継続で `m_busy` を解除
- 556〜558 行: ページメンバの deque を使う `AppendLog`

疑似コードの UI 継続が捕捉するのは `weakResult`、`weakLog`、`err` だけであり、ページメンバの `m_busy` を解除できない。同様に、ページメンバの `std::deque` を使う `AppendLog` や `ShowResult` にも到達できない。TextBlock を直接更新すると、200 行上限を持つログ設計と一致しない。

修正案:

- `ClipboardPage` の weak reference を task runner に渡し、UI 継続で `if (auto page = weakPage.get())` を確認して `CompleteWorkerOperation(...)` を呼ぶ設計にする。weak reference はページ寿命を延長しないため、ページ破棄時の安全性を維持できる。
- `CompleteWorkerOperation` に `m_busy` の解除、結果表示、`AppendLog` を集約する。
- 「worker へページ参照を一切渡さない」は「strong reference / raw `this` を渡さない。weak reference のみ許可」に修正する。
- または、busy token とログ配送先を page-independent な共有状態に分離する。どちらを採るかを設計で確定する。

### 中優先度

#### M1. page-local `m_busy` では、ページ再入場をまたぐ同時実行を防げない

対象:

- 258〜263 行: 同時実行を許可しない方針
- 473 行: 新しいページは新しい `m_busy` を持つ
- 567〜570 行: worker 直列化とページ破棄時の扱い

worker 実行中に Back し、すぐ ClipboardPage へ再入場すると、新しいページの `m_busy` は false なので次の worker 操作を開始できる。「同時実行は許可しない」という方針を process-lifetime manager 全体に適用するなら、この動作は矛盾する。

修正案:

- 同時実行制限を「同一ページ内だけ」と明記し、ページをまたぐ並行実行は Bridge の concurrency 契約で許容する。
- 手動確認結果を一意にしたいなら、busy state を process-lifetime の共有 task state に移し、再入場後も worker 完了まで Busy を表示する。
- owner UI thread の操作も worker 中に押せるため、どの操作を Busy guard の対象にするかを明記する。Uninitialize / CanDestroy の競合確認だけを例外にするなど、意図を分ける。

#### M2. worker 内の例外時に完了配送と busy 解除が保証されていない

対象:

- 254〜263 行: task runner
- 461〜470 行: `ThreadPool::RunAsync`
- 475 行: 戻り値を保持しない

Bridge 自体は外周で例外を Domain error に変換するが、sample 側の DIB / base64 / JSON / vector / 一時ファイル生成や、完了 payload の構築は worker delegate 内で例外を投げ得る。`RunAsync` の `IAsyncAction` を保持しないため、delegate が例外終了するとエラーを観測できず、UI 完了処理も実行されず `m_busy` が残る。

修正案:

- worker delegate 全体を `try/catch` で囲み、成功・Bridge error・sample-side exception のすべてを共通の completion payload に変換する。
- completion の enqueue と busy 解除を必ず通る単一出口にする。
- `std::bad_alloc` とその他の例外の表示方針を決める。sample-side error を Clipboard の Domain error と偽装せず、`Sample operation failed` など別区分で表示する。
- `TryEnqueue` が false の場合はページ終了中として UI 更新を破棄してよいことも明記する。

#### M3. task runner の初期化 guard には例外経路がある

対象:

- 453〜456 行: worker 実行前に常に `EnsureInitialized`
- 370、540 行: Cleanup Temp Files
- 428 行: worker thread からの Uninitialize
- 444 行: Uninitialize 後の CopyPlainText

通常 worker 操作は `Ready` guard が必要だが、Cleanup は未初期化でも実行でき、`CopyPlainText (after Uninitialize)` は guard を意図的に通さず、worker Uninitialize は thread error を確認するための専用経路である。現在の task runner 例は guard を内包しているように読めるため、これらを同じ helper で実装する際に迷いが残る。

修正案:

- `RunOnWorker` 自体は状態 guard を持たず、各 button handler が `ReadyRequired` / `AnyState` / `TestInvalidState` を選ぶ。
- または task runner に明示的な precondition enum を渡す。
- Cleanup の自動実行は Uninit 完了表示と分離し、削除結果を独立してログへ記録する。

#### M4. callback pending state はページ離脱時に失われるが、その扱いが未定義

対象:

- 235〜236 行: manager を維持して forwarding hub だけ解除
- 519〜523 行: `m_pendingRequests` と last request/history ID はページメンバ
- 648 行: ページ離脱・再入場

履歴 request の受付直後に Back すると、Bridge callback 自体は static thunk へ届くが forwarding handler は null のため画面には配送されない。再入場後のページには request table と last ID がなく、完了結果を復元できない。安全性問題ではないが、process-lifetime manager を維持する設計に対する UI 契約が不足している。

修正案:

- 「ページ離脱中の callback は UI では破棄し、再入場後に復元しない」を仕様として明記する。
- または request table と完了ログを process-lifetime state に移す。
- 前者なら、pending 中の Back -> 再入場 -> Uninitialize の手動確認を追加し、unknown request の callback でも安全にログまたは無視できることを確認する。

### 低優先度

#### L1. pending 中に誤って Initialize を押す確認手順には復旧手順が必要

対象:

- 645 行: 1 回目の Uninitialize が `FALSE` のまま再 Init すると同期 API が `NOT_INITIALIZED` になることも確認

この確認後も manager は shutdown 中である。後続テストへ影響させないため、callback 消化 -> CanDestroy -> Uninitialize `TRUE` -> Initialize の復旧手順まで同じ行に含めるとよい。H1 の tri-state guard を採用する場合は、通常 UI では再 Init を拒否し、この挙動確認だけを専用 error case として分離する。

#### L2. 自動一時ファイル削除の結果表示を分離すると明確

対象:

- 540 行: Uninitialize 成功時にも削除し、削除失敗時は成功表示のままにしない

Manager の Uninitialize 成功と sample 一時ファイル削除失敗は別の結果である。後者により Uninitialize 自体が失敗したように見えないよう、`Uninitialize succeeded; temp cleanup failed` のように主結果と後処理結果を分けて表示する方針が望ましい。

## 不足項目

- `Ready` と shutdown gate closed を区別する process-lifetime 状態遷移。
- worker 完了時に page memberへ安全に戻る weak-page completion の具体形。
- sample-side exception を含めても completion と busy 解除を保証する単一出口。
- page 再生成をまたぐ worker 直列化の適用範囲。
- ページ離脱中に完了した履歴 callback の UI 上の扱い。

## 前回指摘の反映状況

- H1 同期 Bridge の worker 実行: 反映済み。ただし task runner の completion / busy 設計に新規指摘あり。
- H2 Uninitialize 再試行: 手順は反映済み。ただし boolean 状態では shutdown 中の操作制御ができない。
- H3 ページ再生成時の状態保持: process-lifetime state は追加済み。ただし二値では不足。
- M1〜M5: 反映済み。
- L1〜L2: 反映済み。

## 総合評価

v1 の公開 API・エラー期待値・実行スレッドに関する指摘は適切に反映され、機能網羅と手動確認観点は実装へ渡せる水準に近づいている。

一方、`g_managerInitialized` が shutdown 中も true になる点と、worker 完了処理が page memberへ到達できない点は、実装時に確実に問題になる。前者は閉じた lifecycle gate へ新規操作を通し、後者は `m_busy` が解除できないため、どちらも実装前の修正が必要である。

総合評価: **要修正**。H1〜H2を反映し、M1〜M3の task runner 契約を確定してから実装 agent へ渡すことを推奨する。
