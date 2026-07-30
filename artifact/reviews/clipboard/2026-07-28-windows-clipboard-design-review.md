# レビュー結果

- 日付: 2026-07-28
- 対象ファイル: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design.md`
- 機能名: clipboard
- 対象 OS: Windows 11 以降
- 判定: **要修正**
- 別モデルによる独立レビュー: 実施済み

---

## 強み

- 企画書 S-01〜S-20 と設計 F-01〜F-17、DoD、タスクのトレーサビリティが明確。
- Manager までを `WindowsLibrary`、Unity Bridge を委譲だけにする構成は Clean Architecture と既存構成に適合している。
- 同期性 × スレッドアフィニティの判断、Win32 RAII、境界検証、エラー正規化、pinned item の扱いは適切。
- 既存ファイルとの差分とタスク見積もりが具体的。

## 改善点

### 高優先度

1. **非同期 Port が同期シグネチャ**
   - 376〜388行の `GetItems` は `DWORD` 同期戻り値だが、実装は UI 上で `GetHistoryItemsAsync()` を `co_await` する。
   - UIをブロックせず結果を返せず、非同期BridgeやMockに接続できない。
   - Domain型callbackまたはplatform非依存async abstractionへ変更する。

2. **owner HWND とtoolkit受信ウィンドウが混同されている**
   - 142、193、208〜214、293〜327行。
   - 外部HWNDへlistener登録／`PostMessage`しても、そのWndProcはtoolkit handlerを呼ばない。
   - foreground top-level HWNDと、自前WndProcを持つ配送用HWNDを分離し、owner UI thread上での生成方法またはsubclass契約を定義する。

3. **履歴イベントの公開・寿命契約が不足**
   - 386〜398、429〜440行。
   - S-14の3イベントを外部へ届けるcallbackが公開APIにない。
   - token即時保持、登録rollback失敗、atomic gate、in-flight drain、callback内Stop禁止、`CanDestroy`が設計へ反映されていない。

4. **遅延レンダリングproviderを公開APIから渡せない**
   - 334〜360、482行。
   - `reserveDeferredFormats(formatsJson)` は形式名だけで、`WM_RENDERFORMAT`時のpayload生成方法がない。
   - C ABI provider callback + context +寿命契約、または予約時payload保持方式を定義する。

5. **終了失敗を返せない**
   - 429〜440、461〜462行。
   - `Stop`成功まで資源を保持する契約に対し、`uninitClipboardManager(void)` は解除失敗や再試行要否を通知できない。
   - `BOOL` / `pError`、または非ブロッキング停止状態APIを設ける。

6. **非同期JSONの寿命が未定義**
   - 454、490〜500行。
   - `const wchar_t* json` の所有者、有効期間、失敗時null規約がない。
   - callback中のみ有効・呼出側コピー等をDoxygenとテストへ明記する。

### 中優先度

1. 104行は同期WinRTも任意threadからUI配送とする一方、495〜501行は可用性APIをUI thread限定同期としている。どちらかへ統一する。
2. callback実行thread、foreground失敗、Cancel／`Uninit`完了threadが未定義。全完了をowner UIへmarshalするか、任意thread契約を明記する。
3. 228行の `INVALID_ARGUMENT` と516行の `INVALID_PARAMETER` を統一する。
4. Win32失敗注入seamがなく、`SetClipboardData`、`EmptyClipboard`、listener解除失敗を単体テストで再現できない。backend/function tableを注入可能にする。
5. `isSensitive` はtext/htmlだけにあり、files/image/custom/複数形式でF-11を満たせない。全書込API共通のoptionsを設計する。
6. F-07の優先format取得とF-06の汎用batch配置が公開APIにない。

### 低優先度

- T-17は表ではT-15依存、依存図ではT-16依存。T-16も明示する。

## 不足項目

- platform非依存の非同期History Port
- foreground HWNDと配送用HWNDの分離
- 履歴イベントcallbackと完全なshutdown契約
- 遅延rendererのC ABI契約
- 終了失敗／再試行API
- callback payloadの所有権・thread契約
- Win32 API失敗注入seam

## 総合評価

全体構成と規約適合は良好だが、現状は実装準備完了ではない。特に非同期Port、HWND配送、履歴イベント、遅延renderer、終了失敗の5点は実装不能または寿命事故につながるため、設計書で確定してから着手すべきである。
