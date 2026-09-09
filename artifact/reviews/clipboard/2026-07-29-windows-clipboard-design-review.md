# 再レビュー結果

- 日付: 2026-07-29
- 対象ファイル: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design.md`
- 機能名: clipboard
- 対象 OS: Windows 11 以降
- 対象版: v5（リクエスト状態機械と層境界版）
- 判定: **要修正**
- 別モデルによる独立レビュー: 実施済み

---

## 強み

- `Queued → Running → Finished` を導入し、受付から coroutine 終了までの入力値と lease の所有者が示された。
- shutdown 時に completion right を一括 take し、drain work を `CanDestroy` に含める方針になった。
- Data coroutine と Manager の責務分離、coroutine frame 確保失敗、coordinator 導入が設計へ追加された。
- STA の公開契約、エラー定数の数え方、callback snapshot、self-write ring、具象 coroutine 方針が文書全体へ概ね反映された。
- テスト、タスク、リスク、DoD に並行性の確認項目が具体的に追加されている。

## 改善点

### 高優先度

1. **Port と Data 実装の戻り型が一致せず、override できない**
   - 該当: 729〜733、789行。
   - Port は `virtual void GetItemsAsync(...)`、Data 実装例は `winrt::fire_and_forget ClipboardHistoryWinRt::GetItemsAsync(...)` であり、C++では戻り型だけ異なる override はできない。
   - 公開 override は `void GetItemsAsync(...)` の非 coroutine wrapper とし、内部の private `fire_and_forget RunGetItemsAsync(...)` を呼ぶ。wrapper 呼び出し側で frame 確保例外を捕捉できる構造にする。

2. **coordinator 導入後も Manager が pending と backend を直接操作している**
   - 該当: 82〜93、153〜199、816〜830、990行。
   - 方針は `Manager → ClipboardHistoryCoordinator → Port` だが、コード例は `ClipboardManager::StartQueuedRequest` が pending、backend、完了 helper を直接扱っている。構成表にも pending が Manager 所有として残る。
   - request の開始・完了・cancel・drain・pending は coordinator へ移す。WndProc は coordinator へ ID を委譲し、coordinator だけが Port を呼ぶ形へ統一する。履歴イベント登録の backend 呼び出し位置も整理する。

3. **request 受付と shutdown の close/drain が原子的でない**
   - 該当: 311〜365、443〜465、862〜866、1364行。
   - 受付は `TryEnter → pending 登録`、shutdown は `pending lock → CloseAndReserveDrainWork` の順である。lease 取得後・pending 登録前に close されると drain snapshot から漏れ、close 後に pending が追加される。
   - 両 mutex を同時に取るなら通常経路とshutdown経路の順序も逆になり、deadlockし得る。本文の「同時に保持しない」とリスク表の例外も矛盾している。
   - coordinator の単一 mutex で admission gate と request table を管理するか、受付 commit と close + drain take を同じ lock order・同一クリティカルセクションで相互排他にする。

4. **drain 用 `PostMessage` 失敗時に shutdown が永久に完了しない**
   - 該当: 364〜379、463〜469行。
   - pending は既に空で `drainWork` は予約済みのため、投稿失敗した項目を失うと callbackを届けられず、`CanDestroy()` が永遠に false になる。
   - drain queue を Manager / coordinator が保持し、単一の `WM_APP_DRAIN` で queue 全体を処理するか、`drainMessagePosted_` を持って再試行可能にする。投稿失敗分を保持し、配送済み callbackだけ `ReleaseDrainWork()` する契約とテストを追加する。

5. **Running request の WinRT operation を cancel 側から取得できない**
   - 該当: 339、407〜411、789〜830行。
   - operation は Data coroutine 内で生成され、現在の `void` Port から coordinator へ公開されない。一方、状態表は pending が operation handle を持ち、cancel が `Cancel()` するとしている。
   - logical cancelだけに確定して `Cancel()` 記述を削るか、platform非依存の request control / cancel tokenをPortへ追加する。controlを completion right とは別の execution registry に置き、coroutine終了まで保持する。

6. **非UI callerでは「公開 API 復帰後のcallback」を保証できない**
   - 該当: 287、482、866行。
   - `PostMessage` は inline再入を防げるが、別threadのUIが直ちにmessageを処理すると、caller threadのBridge関数が復帰する前にcallbackが実行され得る。
   - 契約を「同一 call stack では呼ばない／inline・reentrantには呼ばない／UI queueへ非同期配送」に変更する。厳密な復帰後を維持するなら caller acknowledgment のような追加protocolが必要。

### 中優先度

1. **非同期処理の配置に旧記述が残っている**
   - 該当: 752、1317、1359、1400行。
   - v5は具象 coroutine を Data に置くが、リスク表には「`co_await` を Manager 内に閉じ込める」、DoDには「全 WinRT 境界が共通ラッパ経由」が残る。
   - 同期は `InvokeWinRt`、非同期は Data の具象 coroutine + `ClassifyWinRtException` + `Complete*` helper という正本へ統一する。

2. **Data が `done` の例外を考慮していない**
   - 該当: 710〜713、789〜815行。
   - `HistoryItemsCallback` は `std::function` で、型として `noexcept` を保証しない。実装例は `done(...)` を `try` の外で呼び、例外が `fire_and_forget` へ漏れる可能性がある。
   - Port の callback はthrow禁止と契約化し、Data側も `done` 呼び出しを `try/catch` で囲んで coroutine 境界から例外を出さない。

3. **self-write ring の overflow と重複message処理が弱い**
   - 該当: 578〜596、1361行。
   - UI処理前に9件以上書き込むと古い自書き込みが外部変更として通知される。変更callbackが再書き込みする利用形ではloop要因になり得る。
   - 動的deque / set、UI threadでの書き込み直列化、またはoverflow時の明示的な縮退契約を採る。複数の `WM_CLIPBOARDUPDATE` が同じ最新sequenceを観測した場合に備え、`lastProcessedSeq_` で重複messageを無視する手順も定義する。

4. **provider契約表が2種類のthreadを混同している**
   - 該当: 678行。
   - 「呼び出しスレッド」が公開 `reserveDeferredFormats` の呼び出しと、`ClipboardRenderCallback` の実行を区別していない。
   - 「登録APIの呼び出しthread = owner UI」「providerの実行thread = owner UIの `WM_RENDER*` 処理中」の2行に分ける。

5. **request callback関数ポインタの寿命が未記載**
   - 該当: 899〜911、1067〜1106行。
   - async requestの callbackをいつまで呼び出し側が有効に保つかが明記されていない。特にP/Invoke delegateはGCから保護する必要がある。
   - callbackが発火するか、受付後cancel / shutdown drainで終端するまで有効に保つ契約をDoxygenへ追加する。

6. **`ReleaseDrainWork` の例外安全性が明示されていない**
   - 該当: 315〜335、463〜469行。
   - callbackが例外を投げても closing-work を必ず減らさないと shutdownできない。
   - drain handlerでRAII scope guardを使い、callbackの成否にかかわらず1回だけ `ReleaseDrainWork()` する。

### 低優先度

1. `pending request の所有権` 表（476行付近）は `Queued` 状態で入力値とleaseもpendingが保持するv5の状態表に合わせて更新する。
2. `ClipboardManagerTest.cpp` に加え、coordinatorの状態機械を直接検証する `ClipboardHistoryCoordinatorTest.cpp` の分離を検討する。

## 前回指摘の反映状況

| 前回指摘 | 状態 |
|---|---|
| queued execution state | 反映 |
| Data / Manager の依存分離 | **部分反映**。コード例と戻り型が残る |
| coroutine frame allocation failure | 反映 |
| shutdown completion right の一括 take | 反映 |
| closing-work count | 反映 |
| エラー数・STA・callback表 | 解消 |
| UseCase / coordinator | **部分反映**。詳細設計への伝播が残る |

## 不足項目

- Portを満たす非coroutine wrapperとprivate coroutine runner
- admission commitとclose/drainの単一原子操作
- 投稿失敗から回復できるdrain queue
- logical cancelまたはplatform非依存request controlの確定
- cross-thread時に保証可能なcallback順序契約
- coordinatorを唯一のrequest状態所有者とする構成

## 総合評価

v5で前回の所有権・shutdown・層分離への対応は大きく進んだ。しかし、Portの戻り型は現状コンパイル不能であり、受付とcloseの競合、drain投稿失敗、cancel control、callback順序には実装上の穴が残る。高優先度6件を確定すれば、実装着手可能な水準に近づく。
