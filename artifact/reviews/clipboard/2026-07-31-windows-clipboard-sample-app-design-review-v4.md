# レビュー結果

- 日付: 2026-07-31
- 対象ファイル: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v4.md`
- 文書種別: サンプルアプリ設計
- 機能名: clipboard
- 対象 OS: Windows
- 前回レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review-v3.md`

---

## 強み

- v3 レビューの H1〜H3、M1〜M4、L1〜L2について、対応表、実装コードによる検証、採用方式が明記され、追跡性が高い。
- worker busy 中は `CanDestroy` 以外の UI 操作も拒否するため、worker の self-write transaction と UI thread の Reserve / Recover が同じ mutex で競合して UI を止める経路が解消されている。
- `Request + Immediate Uninitialize` を同一 handler にまとめ、queued request の drain を決定的に発生させる設計は、shutdown gate の手動確認として適切である。
- Threading ボタンを `ReadyRequired`、Force Initialize を `ShuttingDownRequired` としたことで、期待エラーの前提状態が明確になった。
- `Delayed Worker Check` により、ページ再生成をまたぐ busy、UI 応答性、busy 中の操作拒否を人間の操作速度に依存せず確認できる。
- Uninitialize の結果と非同期 temp cleanup の結果を分け、Manager の成否と sample 後処理の成否を混同しない表示になっている。
- Manager の3状態、Bridge error、sample-side failure、二相バッファ、DIB 検証、callback payload 寿命など、公開 API 契約の反映は十分である。
- 変更ファイル分類、Unity plugin 非依存、既存 Windows sample の UI パターン、実機相互運用項目も一貫している。

## 改善点

### 高優先度

#### H1. anonymous namespace の型を `.xaml.h` の member 宣言で使用する構成は成立しない

対象:

- 181、186、189 行: `WorkerResult` と `WorkerPrecondition` を無名 namespace に配置
- 350〜356 行: `.xaml.h` で `WorkerResult` を public/private member の型に使用
- 184〜186 行: `CompleteWorkerOperation` / `RunOnWorker` / `CheckPrecondition` を `.xaml.h` に宣言

`WorkerResult` を `.cpp` の anonymous namespace に定義すると、`ClipboardPage.xaml.h` からその型を参照できない。同様に `CheckPrecondition(WorkerPrecondition)` を page member として宣言するには、`WorkerPrecondition` も header から見える必要がある。

現在の配置表と header 疑似コードをそのまま実装すると、型未定義でコンパイルできない。

修正案:

- `WorkerResult` と `WorkerPrecondition` を `ClipboardPage` implementation class の nested type として `.xaml.h` に定義する。
- または `winrt::WindowsLibraryExample::implementation::detail` などの named namespace に置き、専用 header へ定義する。ただし本サンプル規模では nested type が最小である。
- nested type にする場合、`RunOnWorker` と `CompleteWorkerOperation` の宣言・定義で `ClipboardPage::WorkerResult` を一貫して使う。
- 配置表の「無名 namespace」を修正する。

#### H2. `get_weak()` の戻り値を projected 型の `weak_ref` とする記載が誤っている

対象:

- 363 行: `winrt::weak_ref<WindowsLibraryExample::ClipboardPage> weakPage = get_weak();`
- 386〜389 行: `weakPage.get()` 後に `get_self`
- 403 行、775 行: `get_weak()` は projected 型を返すと説明

`winrt::implements<D>::get_weak()` の公開シグネチャは `winrt::weak_ref<D> get_weak() noexcept` であり、`D` は implementation type である。`ClipboardPage` implementation member から呼ぶ `get_weak()` は implementation object の weak referenceを返す。Microsoft の C++/WinRT 公式例も `auto weak_this{ get_weak() }` とし、`weak_this.get()` で得た strong implementation referenceから memberへ直接アクセスしている。

参考:

- Microsoft Learn: `implements::get_weak` は `winrt::weak_ref<D>` を返す  
  https://learn.microsoft.com/en-us/uwp/cpp-ref-for-winrt/implements
- Microsoft Learn: Strong and weak references in C++/WinRT  
  https://learn.microsoft.com/en-us/windows/uwp/cpp-and-winrt-apis/weak-references

修正案:

```cpp
auto weakPage = get_weak(); // weak_ref<implementation::ClipboardPage>

dq.TryEnqueue([weakPage, result, busyToken]()
{
    if (auto page = weakPage.get())
    {
        page->CompleteWorkerOperation(result);
    }
});
```

- implementation strong referenceが得られるため `winrt::get_self` は不要である。
- lambda は `RunOnWorker` member の lexical scope にあるので、`CompleteWorkerOperation` は private のままでも呼べる。public にする方針を維持してもよいが、アクセスのためには不要である。
- 「projected 型の weak_ref を返す」という説明と要検証済み扱いを修正する。

#### H3. null pointer を管理する busy token に `operator bool` を使うと生成済みでも false になる

対象:

- 297〜307 行: `std::shared_ptr<void>(nullptr, deleter)` と `if (!busyToken)`
- 318〜319 行: token 生成前後の判定
- 405 行: token 生成失敗時だけ手動解除すると説明
- 631〜647 行: button handler の同じ疑似コード

`std::shared_ptr<void>(nullptr, custom_deleter)` は control block を持ち、最後の破棄時に deleter を呼ぶが、格納 pointer は null なので `operator bool()` は false になる。したがって `if (!busyToken)` は token 生成成功後も true である。

`RunOnWorker` が token 生成後に例外を投げた場合、catch は「token 生成前」と誤判定して `g_workerBusy.store(false)` を実行する。通常は後続 token 破棄との二重 store だけで済むが、worker の schedule 成立後に例外となる経路があれば、worker 実行中に busy を早期解除する。

修正案:

- `bool tokenCreated = false` を別に持ち、shared_ptr 構築完了直後に true にする。
- または `busyToken.use_count() == 0` で control block の有無を判定する。
- より単純には、non-null の sentinel pointerを管理し、deleter は pointer を解放せず busy だけを解除する。ただし pointer 所有の意味が分かりにくいため、明示的な `BusyToken` class / guard を推奨する。
- `operator bool` で token 生成成否を判定しないことを契約に明記する。

### 中優先度

#### M1. OOM catch 内の `std::wstring` 代入は allocation 非依存ではない

対象:

- 369〜378 行: 失敗結果の事前構築と catch 内の `result.detail = L"..."`
- 406 行、780 行: 文字列リテラル代入なので再 allocation しないと説明

`std::wstring` への代入は、文字列リテラルからであっても capacity が不足すれば allocation を行う。特に `Out of memory in sample code` のような長い文字列は small-string buffer に収まる保証がない。`std::bad_alloc` catch 内で再度 `bad_alloc` が起きれば UI completion は失われる。

busy token の破棄により busy 自体は解除できるため致命的ではないが、「OOM を含む全経路で sample failure を表示できる」という説明は正しくない。

修正案:

- `WorkerResult` に allocation 不要の error kind enum を持たせ、UI thread 側で表示文字列を選ぶ。
- または OOM 時は UI 結果を保証せず、busy 解除だけを保証すると明記する。
- 失敗用 `WorkerResult` の初期構築自体も allocation で失敗し得るため、busy 解除と結果表示の保証を分ける。

#### M2. InitializeManager の guard により Bridge の二重初期化を確認できなくなっている

対象:

- 513 行: InitializeManager は `Uninitialized` のみ通過
- 850 行: 2 回目は API を呼ばず案内表示
- F-17: Init の冪等契約

2 回目の InitializeManager で API を呼ばないため、「二重初期化」という手動項目が Bridge の冪等性を検証していない。`ShuttingDown` で Init を拒否する必要はあるが、`Ready` で同じ owner UI thread から再 Init することは公開契約上の正常系である。

修正案:

- InitializeManager は `Uninitialized` と `Ready` で API を呼び、`ShuttingDown` のみ拒否する。
- `Uninitialized + NONE` は `Ready` へ遷移し、`Ready + NONE` は `Ready` を維持する。
- 手動確認では2回目も Bridge が `NONE` を返すことを確認する。

#### M3. 「全面直列化」は pending の履歴非同期処理までは覆っていない

対象:

- 230 行: クリップボード操作の全面直列化
- 326〜332 行: `g_workerBusy` による開始時 guard
- 580〜592 行: 履歴非同期 API

`g_workerBusy` は同期 worker の寿命だけを表す。履歴 request は受付直後に busy を保持しないため、RestoreHistoryItem などが pending の間に Copy / Paste workerを開始できる。逆方向は busy guard で防げても、すでに受付済みの WinRT 操作と worker 操作の重複は防げない。

これは Bridge が許容する concurrency なら安全性問題ではないが、「全 Clipboard 操作を直列化する」という説明と、Restore 完了前の Paste が古い内容を読む可能性がある点は整理が必要である。

修正案:

- 文言を「同期 worker と UI 直呼び API の開始を相互排他する」に限定する。
- 手動確認の依存操作は request callback の成功を待ってから次へ進むことを明記する。
- 本当に全面直列化するなら、page/process-lifetime の pending request count も guard に含める。ただし Cancel と shutdown drain は例外として許可する必要があるため、サンプルとしては前者の説明修正が簡潔である。

### 低優先度

#### L1. busy 中の CanDestroy の具体的な期待値を記載すると明確

対象:

- 868 行: Delayed Worker Check 中に CanDestroy を実行し、結果表示だけを期待

Manager が `Ready` の間は lifecycle gate が open なので `CanDestroy` は `FALSE + NONE` になる。単に「実行される」だけでなく、この期待値まで記載すると誤判定を防げる。

#### L2. `CompleteWorkerOperation` を public にする理由を簡略化できる

H2 の修正どおり implementation weak referenceから直接呼び、member lambda の access privilegeを使うなら、`CompleteWorkerOperation` は private のままでよい。public にしても外部 projected APIにはならないため問題はないが、「private runner + private completion」のほうが実装意図は明確である。

## 不足項目

- `.xaml.h` から参照できる `WorkerResult` / `WorkerPrecondition` の配置。
- `implements<D>::get_weak()` の実際の戻り型に沿った completion コード。
- null-managed `shared_ptr` の control block 有無を正しく判定する busy token 実装。
- Bridge の二重 Init を実際に呼び出す手動確認。
- pending history request と同期 worker の順序契約。

## 前回指摘の反映状況

- H1 private access: 方針は反映済み。ただし weak reference 型と helper type の配置にコンパイル問題あり。
- H2 busy 解除: shared token 方式で大半の経路を反映済み。ただし null-managed shared_ptr の判定を要修正。
- H3 busy 中の UI-affine API: 反映済み。
- M1 deterministic drain: 反映済み。
- M2 Threading precondition: 反映済み。
- M3 Force Initialize precondition: 反映済み。
- M4 deterministic busy test: 反映済み。
- L1〜L2: 反映済み。

## 総合評価

v4 は shutdown、worker/UI 相互排他、再現可能な手動テストについて大きく改善され、公開 API と実機確認の設計はほぼ整っている。

一方、`WorkerResult` / `WorkerPrecondition` の配置、`get_weak()` の型、null-managed `shared_ptr` の判定は、いずれも疑似コードをそのまま実装するとコンパイル失敗または busy の早期解除につながる具体的な問題である。これらは実装 agent に判断を委ねず、設計書で確定させる必要がある。

総合評価: **要修正**。H1〜H3を反映後、M1〜M2を整えれば実装 agent へ渡せる水準になる。
