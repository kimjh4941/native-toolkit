# Windows クリップボード サンプルアプリ 実装結果 v1

## 基本情報

- 日付: 2026-08-20
- 機能名: Windows Clipboard Manager
- 対象OS: Windows 11 以降
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT / MSIX）
- サンプル計画: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md`
- 機能設計: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 機能実装結果: `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
- ブランチ: `feature/NTKIT-13`
- 対応タスク: 機能設計 T-19

## 0. 状態サマリー（重要）

| 区分 | 状態 |
|---|---|
| ビルド確認済み | ○ Debug x64 リビルド成功、エラー 0、新規ファイル由来の警告 0 |
| 実機動作確認済み | **× 未実施**（理由は第 6 章） |
| 自動UIテスト | △ **Phase 1 のみ実施済み**（12 passed）。本サンプル実装とは別タスクとして着手した。当初は workflow ステップ4 からの逸脱として未実施（経緯は §5.1 / §5.2）、フレームワーク選定は §5.4、Phase 1 の結果は §5.8 |

ビルド成功は機能動作の確認ではない。v5 §8 の手動確認 54 項目はいずれも未実施である。

---

## 1. 変更ファイル

### 1.1 新規作成

- `windows/WindowsLibraryExample/ClipboardPage.xaml`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.h`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp`
- `windows/WindowsLibraryExample/ClipboardPage.idl`
- `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`

### 1.2 既存変更

- `windows/WindowsLibraryExample/MainMenuPage.xaml`（Clipboard メニューカード追加、7 行）
- `windows/WindowsLibraryExample/MainMenuPage.xaml.h`（`ClipboardCard_Click` 宣言、1 行）
- `windows/WindowsLibraryExample/MainMenuPage.xaml.cpp`（`ClipboardCard_Click` 実装、6 行）
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj`（`ClInclude` / `Page` / `ClCompile` / `Midl` へ 4 エントリ、11 行）

### 1.3 非変更（計画どおり手を付けていない）

- `windows/WindowsLibrary` 配下すべて
- `windows/UnityWindowsPlugin`
- `windows/WindowsLibraryExample/App.xaml` / `App.xaml.cpp` / `MainWindow.xaml*`
- `windows/WindowsLibraryExample/Package.appxmanifest`
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`
- `windows/WindowsLibraryExample/pch.h`（`ThreadPool` は `ClipboardPage.xaml.cpp` 側で個別 include）

`git diff --stat` は既存 4 ファイル 25 行追加のみ。v5 §11 の「新規 4 ファイルと既存 4 ファイルだけを変更する」を満たしている。

---

## 2. 実装したサンプル機能

### 2.1 画面

`MainMenuPage` に Clipboard カードを追加し、`Frame().Navigate` で `ClipboardPage` へ遷移する。`ClipboardPage` は既存 `NotificationPage` と同じ骨格（Back / タイトル / `ResultTextBlock` / カテゴリ別ボタン群）に、ログ表示領域を加えた 2 段構成。

ボタン総数 49（機能 48 + Back）。v5 §3.2 の一覧と 1 対 1 で一致する。

| セクション | ボタン数 |
|---|---|
| Init / Lifecycle | 4 |
| Copy | 8 |
| Write Options | 4 |
| Paste | 5 |
| Inspect / Clear | 4 |
| Deferred Rendering | 2 |
| History | 7 |
| Threading | 3 |
| Error cases | 11 |

### 2.2 対象 API

Bridge の Clipboard 27 関数すべてをサンプルから呼び出す。`WindowsClipboardManager.h` のみを include し、`WindowsClipboardManagerInternal.h` などの内部ヘッダと Unity プラグインには依存していない（`common.md`「サンプルアプリの依存方向」準拠）。

### 2.3 実行スレッド分離（v5 §1.2）

- UI スレッド直呼び: `initClipboardManager` / `setClipboardHistoryCallbacks` / `uninitClipboardManager` / `canDestroyClipboardManager` / `reserveDeferredFormats` / `recoverDeferredState` / 履歴非同期 6 関数
- worker 実行: Copy 6 / Paste 5 / Inspect 3 / `clearClipboard` / 一時ファイル I/O / Threading 検証 3

### 2.4 v5 で確定した実装判断の反映

| 判断 | 実装箇所 |
|---|---|
| `WorkerResult` / `WorkerOutcome` / `WorkerPrecondition` を implementation class の private nested type にする | `ClipboardPage.xaml.h` |
| `get_weak()` を `auto` で受け、promotion 後に implementation member を直接呼ぶ。`get_self` を使わない | `ClipboardPage::RunOnWorker` |
| busy 解除責務は `BusyLease` のデストラクタだけが持つ | `ClipboardPage.xaml.cpp` 無名 namespace |
| OOM 時は enum のみ更新し、catch 内で文字列を構築しない | `RunOnWorker` の `catch (std::bad_alloc const&)` |
| busy 中に許可するのは `CanDestroy` のみ | `CheckNotBusy(allowUnderBusy)` |
| `Ready` + worker in-flight の `CanDestroy` は結果をそのまま表示 | `CanDestroy_Click` |
| 3 状態管理と遷移条件（worker Uninit は状態を動かさない） | `g_managerState`、`UninitializeOnWorker_Click` |
| 遅延 payload は予約時に確定 | `ReserveDeferredFormats_Click` で `g_deferredPayloads` を構築 |
| ページ離脱中の callback は破棄し復元しない | `OnNavigatedFrom` で hub を null、`OnRequestCompleted` の unknown id 分岐 |
| Uninit `TRUE` 後の cleanup は主結果を上書きしない | `WorkerResult::logOnly` |

---

## 3. 共通実装パターン: 維持した点と拡張した点

### 3.1 維持（既存 Windows サンプル / macOS 相互参照ペア）

- メインメニュー -> サンプル画面の導線（`Frame().Navigate` / `Frame().GoBack()`）
- Back ボタン + タイトル `FontSize="28"` + `Border` + `ResultTextBlock` の骨格
- `Width="600"` 中央寄せ、`ScrollViewer` 内のカテゴリ別ボタン群
- 既存 `NotificationButtonStyle` の再利用（新スタイルを追加していない）
- 成功 / 失敗マーカー記号による結果表示
- C コールバック -> forwarding hub -> `DispatcherQueue().TryEnqueue` の UI 反映
- `DLog` / `DFLog` による全ハンドラ先頭のログ
- 全 UI 文言・ログ・コメントを英語で記述

macOS 側にクリップボードのサンプル画面が存在しないため、画面構成は Windows の `NotificationPage` を正本とした（v5 §2.1 の判断どおり）。

### 3.2 拡張

| 拡張 | 内容 |
|---|---|
| ログ表示領域 | `ResultTextBlock`（最新 1 件 + manager state）の下に `LogScrollViewer` + `LogTextBlock`（高さ 160、最大 200 行、自動スクロール）を追加 |
| process-lifetime 状態 | `g_managerState`（3 状態）と `g_workerBusy` を無名 namespace に配置し、ページ再生成をまたいで保持 |
| worker task runner | `StartWorkerOperation` / `RunOnWorker` / `CompleteWorkerOperation` を追加し、同期 Bridge を `ThreadPool::RunAsync` で実行 |
| エラー区分の分離 | Bridge の `errorCode=<n>` と `Sample operation failed: <reason>` を別区分で表示 |
| エラーケース専用セクション | 意図的に失敗させる 11 ボタンを独立セクションに分離 |

### 3.3 実装時の追加判断（計画に明記が無く、実装で決めた事項）

| 判断 | 理由 |
|---|---|
| `StartWorkerOperation` を追加し、precondition 判定・busy 取得・token 生成・`RunOnWorker` 呼び出しをまとめた | v5 §5.2 の疑似コードをボタン 30 個分そのまま展開すると同一ロジックが重複する。`RunOnWorker` 自体は v5 の指定どおり状態 guard を持たない |
| `CheckNotBusy(bool allowUnderBusy)` を追加 | UI 直呼びボタンの busy 判定を 1 箇所に集約するため。`CanDestroy` だけが `true` を渡す |
| `WorkerResult::logOnly` を追加 | Uninit 成功後の自動 cleanup が主結果を上書きしないようにするため（v5 §7 の要求を型で表現） |
| `MakeBridgeResult` を private static member にした | v5 §5.1 の「`WorkerResult` を使う anonymous helper は作らない」に従い、無名 namespace ではなく class 内へ置いた |
| `BufferFetch` 構造体を無名 namespace に追加 | 二相 buffer helper が `WorkerResult` を使わずに結果を返せるようにするため（同上の制約） |
| `winrt/Windows.System.Threading.h` を `pch.h` ではなく `ClipboardPage.xaml.cpp` で include | `pch.h` は v5 の変更ファイル一覧に無い。ページ単独の include で足りる |
| CF_HTML の組み立てをサンプル側に実装 | `ClipboardFormats::BuildCfHtml` はライブラリ内部 API で公開されていない。固定幅 10 桁のオフセットで header 長が再フォーマットで変わらないようにした |
| base64 エンコーダをサンプル側に実装 | 公開 API は `Base64Decode` 相当を提供していない（decode もライブラリ内部） |
| DIB を 8x8 / 32bpp / `BI_RGB` の単色で生成 | 外部アセットを増やさないため。v5 §7 のとおり |

---

## 4. ビルド結果

### 4.1 実行コマンド

```
MSBuild.exe windows\WindowsLibraryExample\WindowsLibraryExample.vcxproj ^
  -t:Rebuild -p:Configuration=Debug -p:Platform=x64
```

### 4.2 結果

- 結果: SUCCESS（exit code 0）
- 成果物: `windows\WindowsLibraryExample\x64\Debug\WindowsLibraryExample\WindowsLibraryExample.exe`
- エラー: 0

### 4.3 警告

| 警告 | 件数 | 発生元 |
|---|---|---|
| `C4828` | 370 | `windows\WindowsLibrary\common.h`（既存の非 UTF-8 文字） |
| `C4819` | 11 | `WindowsNotificationManager.*` / `WindowsClassicActivator.*` / `WindowsAppSdkBootstrap.cpp`（既存） |
| `C4190` | 16 | `common.h` の `ToWString` の C リンケージ（既存） |

**新規 4 ファイルを発生元とする警告は 0 件。** 警告の発生元ファイルは `common.h`、`WindowsNotificationManager.*`、`WindowsClassicActivator.*`、`WindowsNotificationBackend.h`、`WindowsAppSdkBootstrap.cpp` と MSBuild targets のみで、`ClipboardPage.*` は 1 件も含まれない。

ページ別の警告数は `ClipboardPage.xaml.cpp` 75 件、`DialogPage.xaml.cpp` 75 件、`MainMenuPage.xaml.cpp` 75 件、`MainWindow.xaml.cpp` 75 件、`NotificationPage.xaml.cpp` 75 件と完全に同数で、いずれも `common.h` を include したことによる既存警告である。新規ファイルが警告の傾向を変えていない。

`C4828` は機能実装結果 v4 の M5 で記録された既存事項（`WindowsLibraryExample` は全構成で `/utf-8`、`WindowsLibrary/common.h` は非 UTF-8）であり、本サンプル実装の範囲外。

---

## 5. 自動UIテスト（workflow ステップ4）: 未実施

### 5.1 未実施の理由

workflow ステップ4 は「既存のUIテストターゲットが無くても、OS標準のUIテストターゲット構成に従って追加する」と定めており、自動化可能な観点の実装を必須としている。今回はこれを実施していない。

理由は承認済み計画 v5 の完了条件との競合である。

- v5 §11 は「新規 4 ファイルと既存 4 ファイルだけを変更する」と定めている
- UIテストプロジェクトの追加はこの条件を必ず超える

**補足（当初の記載を訂正）**

- 開発者モードは**既に有効**（`AllowDevelopmentWithoutDevLicense=1` / `AllowAllTrustedApps=1`）。前提条件として不足していない
- `.sln` の変更は**必須ではない**。`WindowsLibraryTest` は `WindowsLibrary.sln` に属し `WindowsLibraryExample.sln` には含まれていないため、UIテストプロジェクトは独立した `.sln` を持つか直接ビルドする形で追加できる。制約は `.sln` ではなく v5 の変更ファイル数の完了条件であった

### 5.2 ユーザー判断

上記を提示し、「UIテストプロジェクトを追加せず、逸脱として記録する」を選択。Windows のUI自動テストは本リポジトリで初導入となるため、本サンプル実装とは分離し、独立したタスクとして扱う。

なお 8.1 / 8.2 / 8.3 の 28 手動確認項目を自動化しない判断は workflow に沿ったものであり、逸脱ではない。逸脱に該当するのは自動化可能な 26 確認項目を実装していない点のみ。

### 5.3 自動化可能だった範囲

v5 §8 の手動確認 54 項目のうち、アプリ内で完結し UI 自動化の価値がある 26 確認項目。

| 節 | 行数 | 自動化可否 | 備考 |
|---|---|---|---|
| 8.4 Lifecycle / Thread / Busy | 16 | 可能 | 状態遷移・busy・drain はアプリ内で完結 |
| 8.5 Error cases | 10 | 可能 | 期待 errorCode が確定しており照合可能 |
| 8.1 Interoperability | 10 | 不可 | メモ帳 / Word / エクスプローラー / ペイントの内部UI検証 |
| 8.2 Monitoring / Deferred | 8 | 7 行が不可 | 外部アプリでの貼り付けが provider 発火の前提 |
| 8.3 History | 10 | 不可 | Win+V シェルUI、Windows 設定、別デバイスが必要 |

8.1 / 8.2 / 8.3 の 28 手動確認項目は workflow 自身が「自動化できない項目（他アプリ内部のUI検証等）」として挙げている類型に該当する。

v5 で追加した 2 ボタンが自動化の前提を作っている。

- `Request + Immediate Uninitialize`: 1 クリックで `FALSE + CANCELED` を決定的に再現できる
- `Delayed Worker Check (5s)`: busy 状態を決定的に 5 秒間作れる

また全結果が `ResultTextBlock` に `[<method>] errorCode=<n>` の固定書式で出るため、期待値照合が容易である。

### 5.4 フレームワーク選定（決定）

**採用**

> ローカルでの WinUI 3 サンプルアプリの E2E 確認を主目的とし、サーバープロセスを必要とせず UI Automation を直接利用できるため、FlaUI + C# MSTest を採用する。C# は UI テストプロジェクト内に限定して許容し、まず FlaUI を採用する。テストコードは独自 Adapter を介して FlaUI へアクセスさせ、将来生の UIA へ変更する場合もテストシナリオとページオブジェクトへの影響を抑える。将来 WebDriver 互換性や共通 CI 基盤が必要になった時点で Appium 系を再評価する。

**選定理由**

C を選ぶ理由は「UIA が C# 向けだから」ではない。UIA は COM API であり言語非依存で、C++ / C# のいずれからも利用できる。理由は **C# 側のテスト自動化エコシステムが厚く、抽象度を選び直しやすい**点にある。C# を選べば、生の UIA（`Interop.UIAutomationClient`）から FlaUI まで抽象度を後から変更でき、Adapter を挟むことでテストシナリオへの影響を抑えられる。

生の UIA を直接使う場合との差は**能力ではなく自作する配管の量**である。要素検索、待機・再試行、Control Pattern 操作、COM 解放、MSIX 起動処理を自前で整備する必要がある。本サンプルは worker 実行が非同期で待機とリトライが必須のため、この配管は避けられない。

**各案の位置付け**

| 案 | 判定 | 位置付け |
|---|---|---|
| C. FlaUI + C# MSTest | **採用** | サードパーティ OSS（MIT）。Windows 標準 UI Automation を C# から扱いやすくしたラッパー。保守停止時も生の UIA へ移行でき、テスト設計は維持できる |
| A. Appium + Windows Driver | 将来再検討 | Microsoft が WinUI 3 の UI テスト手段として現在案内している公式経路。ただし Appium Windows Driver の実処理は長期間更新されていない WinAppDriver に依存し、Appium 側も Microsoft 提供部分が 2022 年以降未保守と警告している。「公式案内だから最も安定」とは限らない |
| B. WinAppDriver 直接 | 除外 | A と同じ WinAppDriver 本体を直接使うだけで、新規採用の合理性がほぼない。Appium を外して構成は減るが、古いプロトコルと停止したサーバー実装を直接引き受けることになる |
| D. 生の UI Automation API を直接利用 | 「C# 禁止」が明確な場合のみ | C++ / C# のいずれも可。UIA 自体は言語非依存だが、C++ にはテスト用途で定着した高水準ラッパーがほぼないため、C++ を選択した場合は要素検索、待機・再試行、Control Pattern 操作、エラー処理などの配管を自作する必要がある |

### 5.5 採用条件

**ターゲットフレームワーク**

- `net10.0-windows` とする。.NET 9 は 2026-11-10 でサポート終了予定、.NET 10 は 2028-11 までの LTS
- **.NET 10 SDK を導入してからプロジェクトを作成する。未導入のまま実装を開始しない**（現在 `9.0.305` のみ）。着手時に `dotnet --list-sdks` で確認する

**依存の性質**

製品プロジェクトへのビルド依存は持たず、配置済みアプリに対する実行時依存だけを持つ。

| 種別 | 依存先 |
|---|---|
| ビルド時 | MSTest のテスト SDK / アダプター、`FlaUI.UIA3`（`FlaUI.Core` は推移的依存のため明示不要） |
| 実行時 | 配置済み MSIX、AUMID、対話セッション、起動中の `WindowsLibraryExample` |
| 手順上 | `WindowsLibraryExample` のビルドと配置の完了 |

`ProjectReference` を持たないため既存 C++ プロジェクトのビルドグラフは変わらないが、依存が無いわけではない。**通常の MSBuild ビルドだけでは MSIX の登録までは保証されない。** `dotnet test` の前段として配置コマンドまたは Visual Studio の Deploy が必要で、テスト起動時にも AUMID の存在を確認し、未配置なら原因が分かるエラーで停止させる。

**設計条件**

- テストコードは独自 Adapter を介して FlaUI へアクセスする。将来生の UIA へ変更する場合も、テストシナリオとページオブジェクトへの影響を抑える
- 操作対象は表示文字列ではなく `AutomationProperties.AutomationId` で特定する
- **`ClipboardPage.xaml` への `AutomationId` 付与は最低 51 要素**。操作ボタン 48 個、Back ボタン 1 個に加え、検証対象の `ResultTextBlock` と `LogTextBlock` にも付与する。ボタンだけに付けると結果検証が表示文字列や `x:Name` への依存になる
- 現行の `ClipboardPage.xaml` は `x:Name` を 4 要素（`BackButton` / `ResultTextBlock` / `LogScrollViewer` / `LogTextBlock`）に持つのみで、明示的な `AutomationId` はどこにも無い
- 固定時間の Sleep ではなく、要素・結果表示をタイムアウト付きで待つ
- **UI テストは直列実行する。** 運用ルールとしてだけでなく、`[assembly: DoNotParallelize]`（`Properties/AssemblyInfo.cs`）または各テストクラスへの `[DoNotParallelize]` でテスト基盤側からも強制する
- 単体テスト（`WindowsLibraryTest`）と UI テストは別系統で実行する
- ロック画面や非対話セッションでは実行しない
- Clipboard History の消去など元に戻せないテストは、通常の自動テストから分離する
- テストプロジェクトを本体から分離し、C# を製品コードへ持ち込まない
- `.gitignore` の追記は新規プロジェクトのパスに限定する（グローバルな `bin/` / `obj/` は使わない）

```gitignore
/windows/<UITestProject>/bin/
/windows/<UITestProject>/obj/
```

**着手時の小規模検証**

- MSIX アプリの起動方法を最初に検証する（AUMID は `<PackageFamilyName>!App`。PackageFamilyName の発行者ハッシュはインストール後に `Get-AppxPackage` で確定する）
- あわせて `System.Windows.Automation`（UIA2 の管理 API、Microsoft 提供・サードパーティ依存ゼロ）で `ClipboardPage` の要素が取得できるかを確認する。取得できれば依存ゼロの選択肢が残り、できなければ UIA3 系に絞れる

### 5.6 環境の現状（着手時の前提確認用）

| 項目 | 状態 |
|---|---|
| 開発者モード | 有効済み |
| .NET SDK | `9.0.305` のみ（.NET 10 SDK は要導入） |
| WindowsDesktop ランタイム | 8.0.20 / 9.0.9 |
| Node.js | v22.18.0 |
| WinAppDriver | 未インストール |
| CI | `.github/workflows` なし。ローカル実行前提 |
| `.sln` 制約 | なし（`WindowsLibraryTest` が `WindowsLibrary.sln` 側にある前例あり） |

### 5.7 段階案

| Phase | 対象 | 内容 |
|---|---|---|
| 1 | 8.5 Error cases 10 確認項目 | AutomationId 付与、Adapter 層、MSIX 起動検証を含む。価値とコストの比が最も良い |
| 2 | 8.4 Lifecycle / Thread / Busy 16 確認項目 | 順序依存シナリオ。Phase 1 の基盤を再利用 |
| 3 | 8.1 / 8.2 / 8.3 | 自動化せず手動維持 |

### 5.8 Phase 1 実施結果

`windows/WindowsLibraryExampleUITest` を追加し、Phase 1 を完了した。

| 項目 | 結果 |
|---|---|
| テスト件数 | 12（SmokeTests 2 + Error cases 10） |
| 結果 | 12 passed / 0 failed（実行時間 38 秒） |
| 対象 | v5 §8.5 の 10 確認項目すべて |

テスト実行の前提として、Visual Studio から Release / x64 で配置した。インストール場所は従来と同じ `x64\Release\WindowsLibraryExample\AppX` のままで、COM ExeServer のパスは変わっていない。

各テストは自分のアプリインスタンスを起動する。manager 状態がプロセス寿命で保持されるため、`CopyPlainText (after Uninitialize)` のように状態を変えるケースがあり、インスタンスを共有すると実行順序に依存するため。

#### 5.8.1 v5 §8.5 の記載漏れ（自動化により判明）

`PasteImage (size query only)` の期待値を `BUFFER_TOO_SMALL`(7) としていたが、**前提条件が書かれていなかった**。

`pasteImage` はバッファサイズを計算する前に `IsClipboardFormatAvailable(CF_DIB)` を確認する。したがってクリップボードに画像が無い状態では `FORMAT_UNAVAILABLE`(5) が返り、二相バッファ契約に到達しない。

- 正しい手順: **先に CopyImage を実行してから** PasteImage (size query only) を押す
- 前提を満たさない場合の実際の値: `FORMAT_UNAVAILABLE`(5)、`required size=0`

テスト側では `CopyImage` を先に実行する形で対応済み。v5 §8.5 の該当行は、設計を改訂する際にこの前提を追記する必要がある。

これはレビュー v1 の M1（Clear 直後は `EMPTY` ではなく `FORMAT_UNAVAILABLE`）と同種の見落としであり、**手動確認の記述だけでは気付かず、自動テスト化して初めて表面化した**。

#### 5.8.2 残作業

| Phase | 状態 |
|---|---|
| 1 | 完了 |
| 2（8.4 Lifecycle / Thread / Busy 16 確認項目） | 未着手 |
| 3（8.1 / 8.2 / 8.3 の 28 手動確認項目） | 自動化せず手動維持 |

---

## 6. 実機確認（workflow ステップ6）: 未実施

### 6.1 未実施の理由

`WindowsLibraryExample` は MSIX パッケージ済みの WinUI 3 アプリであり、workflow は「Visual Studio から対象アプリを配置(Deploy)して F5 実行する」ことを求めている。これは対話的な Visual Studio セッションを必要とし、本セッションからは実行できない。

さらに v5 §8 の手動確認は、48 個のボタン操作に加えてメモ帳・Word・エクスプローラー・ペイント・Win+V・Windows 設定・別デバイスでの目視確認を伴う。自動UIテストを追加しない判断（第 5 章）と併せ、これらは人手での実施が必要である。

MSIX パッケージの登録（`Add-AppxPackage -Register`）による起動確認も検討したが、ユーザー環境へアプリパッケージを登録する変更になるため、指示なく実施していない。

### 6.2 未確認の手動確認観点

v5 §8 の全 54 確認項目が未実施。内訳は第 5.3 節の表のとおり。

### 6.3 実機確認の実施手順

1. Visual Studio 2022 で `windows/WindowsLibraryExample/WindowsLibraryExample.sln` を開く
2. `WindowsLibraryExample` をスタートアップ プロジェクトにする
3. 構成 `Debug` / `x64` で「配置」を実行する
4. F5 で実行し、メインメニューの「Clipboard Example」から画面へ入る
5. v5 §8.1 から §8.6 の順に確認し、各行の「操作 -> 実際の結果」を記録する
6. NG が出た観点は原因を特定して実装へ戻る

### 6.4 実機で最初に確認すべき項目

v5 §9 の要検証事項のうち、失敗すると以降の全確認が進まないもの。

| No | 項目 | 失敗時の扱い |
|---|---|---|
| 9.1 | InitializeManager が `WRONG_APARTMENT`(18) にならないか | サンプル側で回避せず、機能側の判定条件として報告する |
| 9.7 | worker から Win32 clipboard API を呼べるか | 失敗する場合はサンプルの実行スレッド方針を再検討する |
| 9.2 | `dispatchHwnd` がタスクバー / Alt+Tab に出ないか | 出る場合は機能側へ報告する |

---

## 7. 依存方向チェック

| 確認項目 | 結果 |
|---|---|
| `WindowsLibrary` のみに依存しているか | ○ `WindowsClipboardManager.h` と `common.h` のみ include |
| Unity プラグインへの依存追加がないか | ○ `windows/UnityWindowsPlugin` への参照なし |
| ライブラリ経由で呼べない API をプラットフォーム API 直呼びで代替していないか | ○ Clipboard 操作はすべて Bridge 経由 |
| 内部ヘッダを参照していないか | ○ `WindowsClipboardManagerInternal.h` 等は未参照 |

Win32 API の直接使用は `GetTempPathW` / `CreateFileW` / `WriteFile` / `DeleteFileW` / `WideCharToMultiByte` / `MultiByteToWideChar` / `GetLocalTime` / `Sleep` のみで、いずれもサンプルデータの生成・後始末・表示用であり、クリップボード操作の代替ではない。

---

## 8. 要検証事項（v5 §9 から引き継ぎ、実機未確認）

| No | 項目 | 状態 |
|---|---|---|
| 9.1 | WinUI UI thread の STA 判定 | 未確認 |
| 9.2 | hidden dispatch HWND がタスクバー / Alt+Tab へ出ないか | 未確認 |
| 9.3 | deferred provider の UI queue で hang しないか | 未確認 |
| 9.4 | `NOT_FOREGROUND` の実挙動 | 未確認 |
| 9.5 | history ID が restore / delete で受理されるか | 未確認 |
| 9.6 | 予約中の形式列挙 | 未確認 |
| 9.7 | worker から Win32 clipboard API を呼べるか | 未確認 |
| 9.8 | `Request + Immediate Uninitialize` が `FALSE + CANCELED` になるか | 未確認 |
| 9.9 | `MONITOR_REGISTER_FAILED` 後の復旧 | 未確認 |

コンパイル時に確定した項目:

- v5 §0.1 の `get_weak()` / `get_self` 不使用 / private nested type の可視性は、ビルドが通ることで確認済み

---

## 9. 機能側へ報告する事項（v5 §10 から変更なし）

| 項目 | 内容 |
|---|---|
| preferred format | `PickPreferredFormat` の候補が `{CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP}` 固定で `HTML Format` を含まない。サンプルは現行実装に合わせた期待値を持つ |
| manager state query | Bridge に状態照会 API がなく、利用者が 3 状態を自前で保持する必要がある |
| shutdown gate contract | owner UI スレッドの Uninit 呼び出しで gate が閉じる点を Doxygen へ明記する余地がある |
| write concurrency | Copy / Reserve / Recover が同一 self-write mutex で直列化され、UI caller が待つ可能性を Doxygen へ明記する余地がある |
| CF_HTML / base64 の組み立て手段 | サンプルが CF_HTML と base64 を自前実装する必要があった。`copyMultipleFormats` に base64 payload を渡す利用者は全員同じ実装を持つことになるため、公開ヘルパの要否を検討する余地がある |

---

## 10. 実行確認

このサンプル実装結果を採用して、次工程へ進めますか？

- 実行する: この実装結果を採用して `review-implementation-sample-app` の工程へ進む
- 修正する: 指摘内容を反映して再実装
- キャンセル: ここまでの修正差分は保持したまま終了
