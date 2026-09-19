# レビュー結果

- 日付: 2026-07-31
- 対象ファイル: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v3.md`
- 文書種別: サンプルアプリ設計
- 機能名: clipboard
- 対象 OS: Windows
- 前回レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review-v2.md`

---

## 強み

- v2 レビューの全指摘について、対応表、実装コードによる検証、採用案の理由が整理され、変更の追跡性が高い。
- Manager 状態を `Uninitialized` / `Ready` / `ShuttingDown` に分け、owner UI thread の Uninit と worker thread の `WRONG_THREAD` で遷移を分けたため、閉じた lifecycle gate へ通常操作を通す問題が解消されている。
- worker busy を process-lifetime state に移し、ページ再生成をまたいで直列化する方針は、ページ寿命と作業寿命を適切に分離している。
- worker は raw `this` や strong page reference を保持せず、weak page 経由で UI completion を行うため、ページ離脱時に worker が残ってもページを延命しない。
- Bridge error と sample-side failure を `WorkerResult` で分離し、サンプル側の例外を Clipboard Domain error として表示しない方針は正確である。
- `ReadyRequired` / `AnyState` / `NoStateGuard` により、通常操作、ファイル cleanup、意図的なエラー確認を区別した点は実装時の判断を減らしている。
- ページ離脱中の callback を UI では破棄し、Bridge callback 自体の安全性は static thunk で維持するという契約が明示された。
- 公開 API、エラー期待値、変更ファイル分類、既存 Windows sample の UI パターン、実機相互運用観点は引き続き網羅されている。

## 改善点

### 高優先度

#### H1. anonymous namespace の runner から private な `CompleteWorkerOperation` は呼べない

対象:

- 177〜178 行: `CompleteWorkerOperation` はページメソッド、`RunOnWorker` は無名 namespace
- 315〜321 行: `get_self<implementation::ClipboardPage>(page)->CompleteWorkerOperation(result)`
- 789 行: `get_self` の friend 関係で private メソッドを呼べるという見立て

`winrt::get_self` は projected object から implementation object を取得する手段であり、C++ の private access を無効化しない。anonymous namespace の free function / lambda は `ClipboardPage` の member または friend ではないため、`CompleteWorkerOperation` が private なら呼び出せない。生成コードの friend 関係は arbitrary caller に private access を与えるものではない。

また、implementation class の `get_weak()` が返す weak reference の型と、疑似コードにある projected `weak_ref<WindowsLibraryExample::ClipboardPage>` の扱いも実装時に確定する必要がある。

修正案:

- `CompleteWorkerOperation` を implementation class の public メソッドにする。IDL へ公開する必要はなく、C++ implementation 上だけ public でよい。
- または `RunOnWorker` を `ClipboardPage` の member にし、member scope で作る completion lambda から private メソッドを呼ぶ。
- あるいは page member 内で `std::function<void(WorkerResult)>` completion を構築し、runner はそれを UI queue へ配送するだけにする。
- 「実装時にコンパイルで確認」へ残さず、採用方式と weak reference の具体型を設計段階で確定する。

#### H2. busy 解除の「単一出口」が `RunAsync` 起動失敗と completion 配送例外を覆っていない

対象:

- 293〜329 行: worker delegate の疑似コード
- 334〜339 行: 全経路で busy を解除すると説明
- 555〜566 行: `g_workerBusy = true` の後に `RunOnWorker`
- 676〜679 行: 例外と単一出口のまとめ

現在の try/catch が覆うのは `work()` だけである。次の経路では `g_workerBusy` が true のまま残り得る。

- UI thread で busy を true にした後、delegate/capture の構築または `ThreadPool::RunAsync` が例外を投げる
- `work()` 後、completion lambda へ `WorkerResult` をコピーする際に例外が出る
- `DispatcherQueue::TryEnqueue` 自体が HRESULT 例外を投げる
- `std::bad_alloc` の catch 内で `MakeSampleFailure` の文字列構築が再度 allocation failure になる

`TryEnqueue == false` だけを処理しても、例外経路は閉じない。

修正案:

- busy を取得した直後から解除責務を持つ RAII guard を導入し、`RunAsync` の起動失敗時には UI thread 側で必ず解除する。
- worker delegate 側も scope guard を持ち、completion が正常に queue へ所有権移譲された場合だけ解除責務を UI lambda へ移す。
- `TryEnqueue` と completion capture 構築を含めて try/catch し、queue へ渡せなければ worker 側で解除する。
- OOM catch 内で再 allocation を前提にしない最小 fallback、または少なくとも busy 解除だけは allocation 非依存で保証する。
- 「成功・Bridge error・sample error・queue false」だけでなく、「worker launch exception・completion enqueue exception」を契約表へ追加する。

#### H3. worker busy 中も UI-affine clipboard 操作を許可するため、UI ブロックと操作競合が残る

対象:

- 269〜276 行: busy guard は worker API だけとする
- 274〜275 行: pending 中 Uninitialize の確認のため UI API を許可すると説明
- 673 行: UI 直呼び APIは busy 中でも実行可能

pending 中 Uninitialize の確認対象は history request であり、`g_workerBusy` を使う同期 worker 操作ではない。そのため、この確認のために全 UI 直呼び APIを worker と並行可能にする必要はない。

特に `reserveDeferredFormats` / `recoverDeferredState` は UI thread 上で `ClipboardWatcher::BeginSelfWrite` を使う。worker の copy が同じ self-write mutex を保持している最中に押すと、UI thread が mutex 待ちになり、worker 化で避けた UI ブロックを再導入する。また、history restore と worker copy を重ねると、最終的な clipboard 内容と結果表示が操作順に依存する。

Uninitialize も、worker がまだ lifecycle lease を取得する前に UI 側が teardown を完了すると、予約済み worker が後から `NOT_INITIALIZED` になる。さらに Uninitialize 後の自動 temp cleanup は、既存 worker が busy の場合に開始できない可能性がある。

修正案:

- worker busy 中は、通常の UI 直呼び APIも原則拒否する。
- 例外として許可する操作を `CanDestroy`、必要なら lifecycle 競合確認専用の Uninitialize に限定する。
- pending request -> Uninitialize の検証は worker busy と無関係なので、その手順は維持できる。
- Reserve / Recover / History request / Initialize / SetHistoryCallbacks は worker busy 中に実行しない。
- Uninitialize を worker busy 中に許可するなら、後続 worker が `NOT_INITIALIZED` になることと、自動 cleanup の延期・再試行方法を明記する。

### 中優先度

#### M1. pending 中 Uninitialize の 2 ボタン手順は `FALSE + CANCELED` を安定再現できない

対象:

- 751〜755 行: GetClipboardHistory を押した直後に Uninitialize を押す

`GetClipboardHistory` と Uninitialize が別々の UI 操作の場合、2 回目のクリックまでに message pump が request start と非同期完了を処理できる。履歴取得が速く完了すると、Uninitialize は最初から `TRUE` になり、期待する drain 経路を踏めない。

修正案:

- `Request + Immediate Uninitialize` の専用ボタンを追加し、同じ UI event handler 内で request ID の受付直後に `uninitClipboardManager` を呼ぶ。request start message が処理される前に CloseAndDrain へ進むため、queued request の drain を安定して確認できる。
- 専用ボタンを追加しない場合、期待値を「request が残っていれば `FALSE + CANCELED`、先に完了していれば `TRUE`」に変更し、drain 経路が未確認になり得ることを記録する。
- H2/Lifecycle の中心的確認なので、専用ボタンによる決定的な手順を推奨する。

#### M2. Threading 検証ボタンは `NoStateGuard` では期待エラーが一定しない

対象:

- 263〜267 行: precondition 定義
- 528〜529 行: worker 版 Reserve / Uninitialize を `NoStateGuard`

`reserveDeferredFormats` は未初期化なら owner thread 判定より先に `NOT_INITIALIZED` を返す。`uninitClipboardManager` は未初期化なら thread 判定より先に `TRUE + NONE` を返す。そのため、`NoStateGuard` のままでは表にある `WRONG_THREAD(14)` を保証できない。

修正案:

- Threading の2ボタンは `ReadyRequired` とし、manager が Ready の状態で worker から呼ぶことだけを意図的な契約違反にする。
- `NoStateGuard` は `CopyPlainText (after Uninitialize)` と `Force Initialize while shutting down` など、manager state 自体のエラーを確認するケースに限定する。

#### M3. Force Initialize テストには `ShuttingDownRequired` が必要

対象:

- 261〜267 行: precondition は3種類
- 544 行: `Force Initialize while shutting down` を `NoStateGuard`

このボタンを `Ready` または `Uninitialized` で押すと、期待する「冪等成功だが gate は閉じたまま」にならない。Ready では通常の二重 Init、Uninitialized では新規 Init となり、後続 Copy は成功する。

修正案:

- `ShuttingDownRequired` を追加し、状態が異なる場合は API を呼ばず、先に deterministic な shutdown-pending 手順を実行するよう案内する。
- M1 の専用 `Request + Immediate Uninitialize` ボタンと組み合わせて、Force Initialize の前提状態を安定して作る。

#### M4. busy のページ横断テストは現在の操作時間では再現が不安定

対象:

- 764〜765 行: 時間のかかる Copy 中に Back -> 再入場

通常の copy/paste は clipboard retry を含めても約 100ms 程度であり、その間に Back と再入場を完了するのは困難である。一時ファイル生成も固定の小さな2ファイルなので、busy が残っている状態を安定して作れない。

修正案:

- task runner 自体の確認用に、worker で一定時間待ってから安全な read-only operation を行う `Delayed Worker Check` を用意する。
- または外部 helper で clipboard を一定時間保持する具体的な再現手順を記載する。
- 人間の操作速度に依存する現在の手順は「要検証」に留め、必須の合否判定にしない。

### 低優先度

#### L1. Uninitialize 成功後の非同期 cleanup と主結果の統合方法が曖昧

対象:

- 452〜453 行: Uninitialize 主結果と cleanup 結果を連結表示
- 645 行: cleanup は worker 実行

Uninitialize は UI thread で完了し、cleanup は後続 worker で非同期に完了する。最初の表示後に cleanup completion が来るため、1つの同期的な文言として扱うことはできない。

修正案:

- まず `Uninitialize succeeded; temp cleanup pending` を表示し、cleanup completion で `Temp cleanup succeeded/failed` をログへ追加する。
- 最新結果を更新する場合も、Manager の結果と sample cleanup の結果を別フィールドまたは別行として表示する。

#### L2. `NOT_INITIALIZED` の補足文言は ShuttingDown の専用テストでは不適切

対象:

- 112 行: `NOT_INITIALIZED` は Initialize を先に押すよう促す
- 544 行: ShuttingDown 中の Copy が `NOT_INITIALIZED`

Force Initialize の後に得る `NOT_INITIALIZED` は、Initialize を押せば解決する状態ではない。method と `g_managerState` を見て、ShuttingDown の場合は Uninitialize 再試行を案内する必要がある。

## 不足項目

- C++ access control と `get_weak()` の実型まで確定した、コンパイル可能な weak-page completion。
- worker launch / completion enqueue の例外を含む busy ownership と解除手順。
- worker busy 中に許可する UI API の限定ルール。
- pending drain を決定的に発生させる単一 UI 操作。
- Threading / Force Initialize 検証ボタン固有の state precondition。

## 前回指摘の反映状況

- H1 manager の3状態化: 反映済み。
- H2 weak-page completion: 方針は反映済み。ただし private access と weak reference 型を未確定。
- M1 process-lifetime busy: 反映済み。ただし UI APIとの並行許可を要修正。
- M2 worker exception: `work()` 内は反映済み。worker 起動と completion enqueue の例外経路が残る。
- M3 precondition: 反映済み。Threading / Force Initialize 用の条件を追加する必要あり。
- M4 離脱中 callback: 反映済み。
- L1〜L2: おおむね反映済み。

## 総合評価

Manager の状態遷移、ページ寿命、worker result のモデルは v2 より明確になり、前回の中心的な設計矛盾は解消方向にある。

一方、現行の weak-page completion は private access のためそのままではコンパイルできず、busy 解除も `work()` 以外の例外を覆っていない。また、UI-affine clipboard APIを worker と並行可能にしたことで UI ブロックを再導入する経路がある。pending drain の主要テストも操作速度に依存している。

総合評価: **要修正**。H1〜H3 と M1〜M3を反映し、task runner と lifecycle test を決定的な形にしてから実装 agent へ渡すことを推奨する。
