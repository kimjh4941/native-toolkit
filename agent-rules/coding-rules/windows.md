# Windows コーディングルール

## 適用対象

このルールは以下に適用する。

- VC++ 実装（`windows/WindowsLibrary/` 配下）
- Bridge 層 C API（`.h` / `.cpp`）

ただし「UI 自動テスト（サンプルアプリ）」の節だけは、C# で書く UI テストプロジェクトにも適用する。それ以外の節（アーキテクチャ、ログ、コメント、文字列・API 取り扱い、同期 / 非同期）は VC++ 実装と Bridge C API のみが対象で、UI テストプロジェクトには適用しない。

---

## アーキテクチャ（VC++ 版 Clean Architecture）

`common.md` の Clean Architecture は Swift（iOS/macOS）イディオム前提で書かれている。Windows（VC++ / MFC + `extern "C"` C Bridge）では、その原則を以下のように対応づけて適用する。

### 基本構造（既定）

既定は **Manager + C Bridge のフラット構造**とする（既存 `WindowsDialogManager` パターンに合わせる）。

```
Unity C# (P/Invoke)
    │
    ▼
extern "C" C Bridge API   ← 薄いファサード（ロジックを持たない）
    │
    ▼
XxxManager (singleton)    ← 公開 API・システム Delegate 所有・ロジック集約
    │
    ▼
Windows / WinRT API
```

UseCase / Repository を**最初から作らない**。後述のトリガーが出た箇所にのみ層を足す。

### Bridge の配置

- Windows の `extern "C"` C Bridge は **`windows/WindowsLibrary` に実装し、`WindowsLibrary.dll` からエクスポートする**。
- Unity C# は `WindowsLibrary.dll` の C API を直接 P/Invoke する。中継用の別 DLL やラッパープロジェクトを追加しない。
- `windows/UnityWindowsPlugin` は現在使用していないため、新機能の Bridge、Manager、Delegate、依存関係を追加しない。既存ファイル、project、solution 登録は削除・変更せず、そのまま残す。
- `windows/WindowsLibraryExample` の新機能実装は `WindowsLibrary` のみを利用する。既存の project / solution 構成は変更しない。

### Solution Explorer 上のファイル整理

- `windows/WindowsLibrary` に新機能のファイルを追加したら、`WindowsLibrary.vcxproj.filters` に既存の `Notification` / `Dialog` / `Bootstrap` と同様の **Filter** を機能名で追加し、`.vcxproj` に登録した全ての `ClCompile` / `ClInclude` に対応する `<Filter>` を設定する。
- Filter の `UniqueIdentifier` は既存エントリと重複しない GUID を新規生成する。
- `.vcxproj` の Include 一覧と `.vcxproj.filters` の Filter 割り当ては 1 対 1 で一致させる（漏れ・余剰がないか diff で確認する）。
- `WindowsLibraryTest` はファイル数が少なくフォルダ分けしていないため、`.vcxproj.filters` は追加しない（既存方針を踏襲）。

### 層の VC++ 対応

| common.md の層 | VC++ での実現 |
|---|---|
| Domain（モデル・エラー型） | エラー定数（`XXX_ERROR_*`）・純粋 struct。WinRT / MFC 型を持ち込まない |
| Application（Port） | **抽象基底クラス**（純粋仮想関数のインターフェース） |
| Application（UseCase） | 1 操作 1 クラス。ただし**非自明なロジックを持つ操作のみ**作る |
| Data（Repository） | **WinRT 呼び出しを隔離する実装クラス**。ABI/Domain 型 ↔ WinRT 型の変換を集約 |
| Manager | 公開 API・システム Delegate（コールバック）所有・（あれば）UseCase 集約 |
| Bridge | `extern "C"` C API。Manager 呼び出し専用（薄く保つ） |

### 段階適用のトリガー（ROI 順）

層は「機能数」ではなく「次の痛み」が出た箇所に足す。

1. **純ロジックの抽出（必須・常時）** — バリデーション・JSON マッピング・ドメイン規則は **WinRT 非依存の関数/クラス**に切り出し、単体テストを書く。（例: `WindowsNotificationManager::ValidatePayload`）
2. **Manager の機能単位ファイル分割** — `Manager.cpp` が肥大化したら機能ごとに分割する。
3. **Repository 境界（抽象基底クラス）の導入** — 「Manager のロジックを WinRT 抜きでテストしたい」または「実装を差し替えたい」場合のみ。
4. **UseCase の導入** — その操作が非自明なロジック（状態機械・調整・リトライ等）を持つ場合のみ。**素通し（pass-through）の操作には作らない。**

### 原則（フラット／層化を問わず共通）

- **C Bridge は薄く保つ**（ビジネスロジックを持たず Manager に委譲。複雑なデータは JSON 文字列で渡す）。
- システム Delegate / コールバック（例: `NotificationInvoked`）は **Manager の 1 クラスのみが所有**する。
- WinRT / MFC 固有型を Domain 相当（エラー型・純粋モデル）に持ち込まない。
- WinRT 例外・`HRESULT` は Domain エラー定数へ正規化してから Bridge の out 引数（`DWORD* pError` 等）で返す。
- 純ロジックは WinRT ランタイム未登録でもテストできる形に保つ（活性化が必要な型の生成より前に検証を済ませる）。

---

## ログ（DLog / DFLog / DFLLog）

全メソッドの先頭1行目に、全パラメータを含むログを必ず入れる。

- 通常ログ: `DLog`
- フォーマットログ: `DFLog`
- 大きいバッファ指定ログ: `DFLLog`

### VC++ フォーマット

```cpp
static const wchar_t* TAG = L"FullClassName";

void Sample(const wchar_t* param1, int param2)
{
    DFLog(TAG, L"[Sample] param1: %ls, param2: %d", param1 ? param1 : L"null", param2);
    // existing logic...
}
```

### エラーログ例

```cpp
DFLog(TAG, L"[ShowDialog] failed. hr=0x%08lx", hr);
```

### 対象

- `extern "C"` の公開関数（Bridge C API 含む）
- クラスの公開メソッド
- クラスの内部メソッド（通知機能コード内のローカル関数を含む）

### 除外

- data model / enum / struct / class 宣言
- ヘッダの前方宣言
- 純粋 UI ユーティリティ
- 既にログがある箇所（重複追加しない）

---

## コメント（Doxygen / HeaderDoc）

公開ヘッダと公開 API には Doxygen/HeaderDoc 形式のコメントを付ける。

**対象（必須）:**

- `.h` の公開関数宣言
- `extern "C"` 公開 API
- 非自明な公開定数
- 公開クラスのメソッド（必要に応じて `@brief`, `@param`, `@return`）

**推奨:**

- 実装ファイルの公開 API 実装にも要約コメントを付ける
- `@copydetails` を使い、ヘッダコメントと重複を減らす

**除外:**

- `static` な内部ヘルパー関数
- 自明な getter / setter 相当の軽量処理

---

## コメントと言語ポリシー

- コメント本文（Doxygen、HeaderDoc、行コメント、ブロックコメント）は英語で記述する
- ユーザー向けメッセージ文言（UI テキスト、statusText、Toast、Dialog 文言）は英語で記述する

---

## 文字列・API 取り扱い方針

- 文字列は `wchar_t*` / `std::wstring` を優先して扱う
- 公開 API は `extern "C"` + `__declspec(dllexport/dllimport)` で公開する
- バッファを受け取る API では `buffer_size` を必須にし、境界チェックを行う
- エラー情報は `DWORD* pError` など out 引数で返す

### 参考実装

- ログ関数: `DLog`, `DFLog`, `DFLLog`
- 文字列変換: `ToWString`
- 文字列連結: `ConcatWStrings`

---

## 同期 / 非同期の方針

方針は `common.md`「Manager の公開 API 方式」を参照。iOS / macOS の `async throws`、Android の `suspend fun` に対応する VC++ 側の判断基準を以下に定める。

### 原則: システム API に準拠する

**システム API が同期なら同期、非同期なら非同期に準拠する。** 同期的に完結する処理を、性能上の理由なく非同期でラップしない（他 OS のルールと同じ）。ただし、同期 API に UI スレッド / フォアグラウンド要件があり、Bridge を任意スレッドから呼び出せる契約にする場合は、UI スレッドへの配送境界が必要になる。この配送をコールバック方式にすることは、同期処理そのものの不要な非同期化とは区別する。

- 同期のまま扱うもの: Win32 API（`OpenClipboard` / `SetClipboardData` / `GetClipboardData` / `EmptyClipboard` 等）、ローカルのファイル I/O、純ロジック（バリデーション・JSON マッピング・構造検証）
- 非同期として扱うもの: WinRT の `IAsyncAction` / `IAsyncOperation<T>` を返す API

### 公開 API 方式は同期性とスレッドアフィニティで決める

WinRT の非同期 API は ABI 上は必ず非同期だが、**公開 API まで非同期にするかは対象 API のスレッドアフィニティ要件で決まる**。同期 API でも UI スレッド / フォアグラウンド要件がある場合は、公開 API が UI スレッド限定か任意スレッド対応かを先に決める。実装前に公式ドキュメントで要件を確認する。

| システム API の性質 | 内部実装 | 公開 API |
|---|---|---|
| 同期・呼び出しスレッドのアフィニティ要件なし（Win32 等） | 同期 | **同期** |
| 同期・UI スレッド / フォアグラウンド要件あり | UI スレッド上で同期 | UI スレッド限定なら **同期**。任意スレッド対応なら `PostMessage` で UI へ配送し **コールバックで完了通知** |
| 非同期・スレッドアフィニティ要件なし | 非同期 | **同期を維持する（既定）**。非 STA ワーカースレッドで待機すれば `DWORD* pError` の同期 Bridge のままにできる |
| 非同期・UI スレッド / フォアグラウンド要件あり | 非同期 | **非同期（コールバック）にする**。UI スレッドで開始が必須、かつ UI スレッドをブロックできないため |

後半 2 行の例: `Windows.ApplicationModel.DataTransfer.Clipboard` は公式 Remarks に「呼び出し元アプリが UI スレッドでフォーカスを持つ時のみアクセス可能」と明記されている。`SetContent` / `ClearHistory` のような同期 API は UI スレッド上で同期実行し、`GetHistoryItemsAsync` のような非同期 API は UI スレッドで開始して非同期に待つ。いずれも、Bridge を任意スレッド対応にする場合は UI スレッドへ配送する必要があり、「バックグラウンドスレッドで待機する」だけでは要件を満たせない。

表の 1 行目は API 呼び出し自体のスレッドアフィニティを示す。Win32 Clipboard は同期 API だが、書き込みでは有効な owner `HWND` を使う（`OpenClipboard(NULL)` 後の `EmptyClipboard` は所有者を `NULL` にするため、以降の `SetClipboardData` が失敗する）。また、遅延レンダリングの `WM_RENDERFORMAT` / `WM_RENDERALLFORMATS` と変更監視の `WM_CLIPBOARDUPDATE` は対象 `HWND` を所有するスレッドへ届くため、そのスレッドでメッセージポンプを継続して回す。

### 待機の実装ルール

- **UI スレッド（STA）で `IAsyncXxx::get()` を呼ばない。** cppwinrt が `!is_sta_thread()` で assert する
- 非 STA ワーカーで待つ場合は `get()`（無期限ブロック）ではなく **`wait_for(タイムアウト)`** を使う。`get()` と `wait_for()` は排他で、WinRT の非同期オブジェクトは**待機者を 1 つしか許容しない**。タイムアウトした（`AsyncStatus::Started`）オブジェクトは再待機せず破棄する
- UI スレッド要件がある API は **UI スレッドで開始し `co_await` で待つ**（UI スレッドを塞がない）。C++/WinRT は `IAsyncXxx` を `co_await` した場合に呼び出し元のアパートメントへ復帰することを保証する。コルーチンを使うため **`/std:c++20`** が必要
- 既存プロジェクトが C++17 の場合、`co_await` を使う `.cpp` にだけファイル単位で `/std:c++20` を設定し、公開ヘッダー・Win32 コア・既存機能は C++17 互換を維持する。プロジェクト全体の C++20 移行は機能追加と同時に行わず、影響範囲と回帰テストを確認できる別タスクとして段階的に実施する
- **アパートメントは自前で作成したワーカースレッドでのみ** `winrt::init_apartment()` / `winrt::uninit_apartment()` を対で呼ぶ。`DllMain` / `CWinApp::InitInstance` では初期化しない（ホストが後から `init_apartment(single_threaded)` を呼ぶと `RPC_E_CHANGED_MODE` でクラッシュする。`WindowsLibrary.cpp` の既存コメント参照）
- WinRT 例外は Bridge 境界で捕捉して Domain エラーへ正規化する。**`co_await` 後に発生した例外は同期の try/catch では捕捉できない**ため、例外は発生し得る非同期処理と同じコルーチン内で捕捉する。`E_OUTOFMEMORY` は `std::bad_alloc` として送出されるため別途捕捉する

### UI 配送または非同期 Bridge を採る場合の契約

同期 Bridge を維持できない場合（任意スレッド対応の同期 UI-affine API、または UI スレッド要件がある非同期 API）は、次を公開 API の契約として定義する。

- **受付（pending 登録 + UI スレッドへの投入）の成立を境界とする。** 受付前の失敗は Bridge の同期戻り値のみで通知しコールバックを呼ばない（0 回）。受付成立後の全終端状態（成功・失敗・キャンセル・`Uninit` による失効）はコールバックをちょうど 1 回呼ぶ
- 非 UI スレッドからの呼び出しは所有ウィンドウへ `PostMessage` で配送する（`SendMessage` は呼び出し元をブロックしデッドロックし得るため使わない）
- コールバックは C ABI 境界なので例外を投げてはならない。呼び出し側も `try/catch` で囲む
- `Uninit` は pending をドレインしてからコールバックを破棄する

### サンプルアプリ（VC++ / MFC）での非同期処理

- ボタンハンドラ等の UI スレッドで待機処理を書かない（メッセージポンプが止まる）
- 結果を UI へ反映する場合は `PostMessage` で UI スレッドへ戻す（Android の `scope.launch(Dispatchers.IO)` + `withContext(Main)`、iOS の `Task { await ... }` + `DispatchQueue.main.async` に相当）
- Bridge が同期 API なら、サンプル側でワーカースレッドに逃がす

---

## UI 自動テスト（サンプルアプリ）

`windows/WindowsLibraryExample` の E2E 確認に使う。`WindowsLibraryTest`（Bridge を直接リンクする単体テスト）とは目的も構成も別物として扱う。

### フレームワーク

**FlaUI + C# MSTest を使う。**

| 項目 | 方針 |
|---|---|
| ライブラリ | `FlaUI.UIA3`（`FlaUI.Core` は推移的依存のため明示不要） |
| テスト基盤 | MSTest のテスト SDK / アダプター |
| ターゲット | `net10.0-windows`（下記のとおり必須。`-windows` を落とすと FlaUI が壊れる） |
| 実行 | `dotnet test` |
| 常駐サーバ | 不要 |

**`net10.0-windows` は推奨ではなく必須**。FlaUI 5.0.0 は `.NET` 向けアセットを `net6.0-windows7.0` / `net8.0-windows7.0` にしか持たないため、TFM を `net10.0`（`-windows` なし）にすると対象外になり、`net48`（.NET Framework 版）へフォールバックして `NU1701` が出る。サポート期限（.NET 9 は 2026-11-10 終了、.NET 10 は 2028-11 まで LTS）とは別の、動作上の要件である。

**選定理由**: UI Automation は COM API で言語非依存だが、C++ にはテスト用途で定着した高水準ラッパーがほぼない。C# 側はエコシステムが厚く、生の UIA（`Interop.UIAutomationClient`）から FlaUI まで抽象度を後から選び直せる。FlaUI と生の UIA の差は**能力ではなく、要素検索・待機・再試行・Control Pattern 操作・COM 解放・MSIX 起動といった配管を自作するかどうか**である。

**採用しない選択肢**

| 選択肢 | 判断 |
|---|---|
| Appium + Windows Driver | Microsoft が WinUI 3 の UI テスト手段として現在案内している公式経路だが、実処理は長期間更新されていない WinAppDriver に依存し、Appium 側も Microsoft 提供部分が 2022 年以降未保守と警告している。将来 WebDriver 互換性や共通 CI 基盤が必要になった時点で再評価する |
| WinAppDriver 直接 | 上と同じ本体を直接使うだけで、新規採用の合理性がほぼない |
| 生の UI Automation API を直接利用（C++ / C# いずれも可） | 「C# 禁止」が明確な場合のみ。C++ を選ぶ場合は配管の自作が事実上必須になる |

### C# の適用範囲

**C# は UI テストプロジェクト内に限定する。製品コードへ持ち込まない。**

本ファイルの他の節（アーキテクチャ、ログ、コメント、文字列・API 取り扱い、同期 / 非同期）は VC++ 実装と Bridge C API に対する規約であり、UI テストプロジェクトには適用しない。

### プロジェクト配置

- UI テストプロジェクトは**独立した `.sln` を持つか、`.sln` を持たず `dotnet test` で実行する**。既存の `.sln` へ追加しない
  - 理由: C# プロジェクトは既定が `Any CPU` のため、既存 `.sln` の `x64` / `ARM64` / `x86` 構成マトリクスへのマッピングを手で維持することになる。UI テストは x64 のみで足りる
- 既存プロジェクトへの `ProjectReference` を持たない
- `.gitignore` には**新規プロジェクトのパスに限定して**追記する。既存リポジトリへの影響を最小化するため、グローバルな `bin/` / `obj/` は使わない

```gitignore
/windows/<UITestProject>/bin/
/windows/<UITestProject>/obj/
```

### 依存の性質

**製品プロジェクトへのビルド依存は持たず、配置済みアプリに対する実行時依存だけを持つ。**

| 種別 | 依存先 |
|---|---|
| ビルド時 | MSTest のテスト SDK / アダプター、`FlaUI.UIA3` |
| 実行時 | 配置済み MSIX、AUMID、対話セッション、起動中のアプリ |
| 手順上 | 対象アプリのビルドと配置の完了 |

`ProjectReference` を持たないため既存 C++ プロジェクトのビルドグラフは変わらないが、「依存が無い」わけではない。

**通常の MSBuild ビルドだけでは MSIX の登録までは保証されない。** `dotnet test` の前段として配置コマンドまたは Visual Studio の Deploy が必要になる。テスト起動時にも AUMID の存在を確認し、未配置なら原因が分かるエラーで停止させる。

### テストコードの構造

- テストコードは**独自 Adapter を介して FlaUI へアクセスする**。将来 生の UIA へ変更する場合も、テストシナリオとページオブジェクトへの影響を抑える
- 操作対象は表示文字列ではなく **`AutomationProperties.AutomationId`** で特定する
- サンプルアプリ側には、**操作要素だけでなく検証対象の表示要素にも** `AutomationId` を付与する。結果表示に `AutomationId` が無いと、検証が表示文字列や `x:Name` への依存になる
- `x:Name` だけでは明示的な `AutomationId` にならない点に注意する

**検証対象は「最新結果」と「ログ」を使い分ける。**

| 表示 | 性質 | 使いどころ |
|---|---|---|
| 最新結果の 1 行 | 上書きされる | 単発の操作の検証 |
| ログ領域 | 追記型 | 順序や経過を伴う検証 |

最新結果だけを見ていると、後続のコールバックが到着した時点で上書きされ、検証したかった値をポーリングで取り逃す。たとえば「リクエスト受付の直後に uninit を呼ぶ」操作では、uninit の戻り値が表示された直後に、drain が配送したキャンセル済みコールバックの結果へ置き換わる。順序を含む検証はログ側から読む。

このため、サンプルアプリ側は**順序検証に必要な値をログにも残す**。単発の操作は結果表示だけでよいが、後続の処理に上書きされ得る値（受付と完了が分かれる操作、shutdown の途中経過など）を結果表示だけに出すと、自動テストから安定して読めない。

テスト側も、どの操作がログを書くかは一様でない前提で書く。ログにエントリがあることを前提にする検証は、確実にログを残す操作で状態を作る。

### 実行条件

- 固定時間の `Sleep` ではなく、要素・結果表示を**タイムアウト付きで待つ**
- UI テストは**直列実行**する（クリップボードのようなマシン共有リソースを奪い合うため）。運用ルールとして書くだけでなく、**テスト基盤側でも強制する**
  - `dotnet new mstest` は `MSTestSettings.cs` に `[assembly: Parallelize(Scope = ExecutionScope.MethodLevel)]` を生成する。**テンプレート任せにすると並列実行が既定で有効になる**ので、必ず置き換える

```csharp
// Properties/AssemblyInfo.cs
[assembly: DoNotParallelize]
```

  各テストクラスへ `[DoNotParallelize]` を付ける形でもよい。

- 単体テストと UI テストは**別系統で実行する**
- **ロック画面や非対話セッションでは実行しない**（UI Automation は対話的デスクトップセッションを要求する）
- **実行中はデスクトップを操作しない。** ウィンドウの最小化・フォーカス移動・他アプリでのコピーはいずれも結果を不安定にする。特にクリップボードはマシン全体で共有される単一リソースなので、実行中に他アプリでコピーすると内容が壊れる
  - 要素の操作は Invoke パターン（プログラム的な呼び出し）を優先する。物理的なマウス移動を伴う Click へフォールバックすると、ウィンドウ位置や最小化の影響を受ける
- 元に戻せない操作（クリップボード履歴の消去など）を伴うテストは、通常の自動テストから分離する
- MSIX パッケージ済みアプリが対象の場合、**起動方法（AUMID = `<PackageFamilyName>!<ApplicationId>`）を最初に小規模検証**してから本実装に入る

### 着手前の前提確認

- **.NET 10 SDK を導入してからプロジェクトを作成する。** 未導入のまま実装を開始しない

```
dotnet --list-sdks
```

### MSIX の配置（UI テストの前段）

**MSBuild にサンプルアプリを配置する手段は無い。** `WindowsLibraryExample.vcxproj` には `Deploy` / `PrepareForDeploy` / `_CopyFilesToAppxLayout` / `BuildAppxUploadPackageForUap` のいずれも存在しない（`_GenerateAppxPackageRecipe` のみ存在）。

**ビルドしても AppX レイアウトは更新されない。** ビルドが更新するのは出力ルートの成果物・`AppxManifest.xml`・`*.build.appxrecipe` までで、`$(OutDir)AppX\` へのコピーは行われない。古いレイアウトが残ったまま「ビルドは成功したのに配置内容が古い」状態になるので、レイアウト内のタイムスタンプで確認する。

配置手段は次の 2 つ。

| 手段 | 内容 |
|---|---|
| Visual Studio の「配置」 | 確実。プロジェクト右クリック → 配置。構成は x64 を選ぶ（ARM64 / Win32 構成は include パスが未設定で機能しない） |
| `*.build.appxrecipe` を使ったスクリプト | ビルドが生成する recipe が `LayoutDir` と全ペイロードを `Include`（コピー元の絶対パス）+ `PackagePath`（レイアウト内の配置先）で列挙している。これを読んでコピーし `Add-AppxPackage -Register` すれば VS の配置と同じ処理を再現できる。推測でファイルを選ぶ必要はない |

配置が必要になるのは**サンプルアプリを変更したときだけ**で、テストコードだけの変更なら不要。

インストール場所を変えたくない場合は、**現在登録されている構成と同じ構成を配置する**。構成を変える（Release → Debug など）とインストール場所が変わり、マニフェストが宣言する COM ExeServer の実行ファイルパスも変わるため、通知アクティベーションの登録に影響し得る。

---

## 実装の落とし穴（WinUI 3 / MSIX / 通知）

ビルドが通っても実行時に初めて顕在化する Windows 固有の罠。実装・レビュー時に必ず確認する。

- **文字コード**: 非 ASCII（絵文字・日本語）を含む `.cpp`/`.h` は、UTF-8 BOM 付与または `/utf-8` コンパイルオプションを使う。無いと CP932 解釈で実行時に文字化けし、`warning C4819` が出る。絵文字は `\uXXXX` / `\UXXXXXXXX` のユニバーサル文字名でも安全に書ける。
- **WinRT、STA、UI 配送**: UI スレッド（WinUI は STA）で `IAsyncXxx::get()` をブロッキング待機しない。cppwinrt が `!is_sta_thread()` で assert する。ただし「非 STA スレッドで待つ」だけで済むのはスレッドアフィニティ要件のない API に限る。`Clipboard` のように UI スレッド + フォアグラウンドを要求する API では、非同期 API の公開 Bridge を非同期にする。同期 API は UI 上で同期実行するが、Bridge を任意スレッド対応にする場合は `PostMessage` + コールバックで UI へ配送する。判断基準は「同期 / 非同期の方針」を参照。
- **パッケージ済み通知のアクティベーション登録**: `AppNotificationManager::Register()` を使うパッケージ済み（MSIX）アプリは、`Package.appxmanifest` に `windows.comServer`（ExeServer + Class Id）と `windows.toastNotificationActivation`（`ToastActivatorCLSID`）の登録が必須。無いと初期化が `No COM servers are registered for this app`（0x80004005）で失敗する。
- **プロセス単位登録の冪等性**: `Register()` はプロセスで一度だけ。Manager の `Init` は既初期化時に再購読・再 `Register()` しないようガードする（二重 `Register()` は `0x80070490`「Must register event handlers before calling Register()」になる）。`Uninit` で状態を戻して再 `Init` できる形にする。
- **進捗バーの更新**: `UpdateAsync` で進捗を更新するには、表示時の進捗バーを**データバインド**（`BindValue`/`BindStatus` 等）にし、初期値を `AppNotification.Progress(AppNotificationProgressData)` で与える。リテラル値で組んだ進捗バーは更新できない（API は成功を返すが見た目が変わらない）。更新の sequence number は表示時より大きくする。
- **フォーマットログのバッファ**: `DFLog` 等は出力長に足りるバッファを確保する（`vswprintf_s` は溢れで `"Buffer too small"` assert）。長い JSON ペイロード等は `_vscwprintf` で必要長を算出して動的確保するか `DFLLog` を使う。
- **ビルド ≠ 表示確認**: トースト表示・コールバック・スケジュール・バッジは MSIX 実機実行（Visual Studio から配置→F5）でのみ確認できる。CLI ビルド成功だけで機能完了と判断しない。`Package.appxmanifest` を変更したらクリーン配置する。アプリ実行中は成果物がロックされ再リンクが `LNK1201` 等で失敗するため、再ビルド前に停止する。
