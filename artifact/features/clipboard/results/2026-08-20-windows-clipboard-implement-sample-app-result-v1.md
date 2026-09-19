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
| 実機動作確認済み | ○ **完了（2026-09-05）**。UIテストが 29 観点を自動化し、残る 26 項目（外部アプリ / Win+V / Windows 設定 / 別デバイス / 遅延レンダリング）を手動確認。OK 24 / NG 1 / 未実施 1。さらにボタン単位の照合で判明した 9 ボタンを追加確認し、49 操作ボタン中 48 を確認済み。結果と発見事項 F1〜F3 は第 6 章 |
| 自動UIテスト | ○ **Phase 1 / 2 実施済み、レビュー v1〜v4 完了（LGTM）**（33 passed、連続実行で再現、残存プロセスなし）。本サンプル実装とは別タスクとして着手した。当初は workflow ステップ4 からの逸脱として未実施（経緯は §5.1 / §5.2）、フレームワーク選定は §5.4、実施結果は §5.8、レビュー対応は §5.9 / §5.11 / §5.13、完了確認は §5.15 |

v5 §8 の手動確認は全 55 項目。うち 29 項目を自動UIテストで、26 項目を手動で確認した。未実施は別デバイスを要する 1 項目のみ（第 6.4 節）。手動確認で見つかった不具合 1 件は修正・再確認済み（F2）、1 件は Windows 側の制約として API 契約に明記した（F3）。

---

## 1. 変更ファイル

本章はレビュー時点（2026-08-21）の最終状態。サンプル実装本体に加え、別タスクとして着手した UI 自動テスト（§5.8）の追加分も含む。

### 1.1 サンプル実装（新規）

- `windows/WindowsLibraryExample/ClipboardPage.xaml`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.h`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp`
- `windows/WindowsLibraryExample/ClipboardPage.idl`

### 1.2 サンプル実装（既存変更）

- `windows/WindowsLibraryExample/MainMenuPage.xaml`（Clipboard メニューカード、後に `AutomationId` 3 要素）
- `windows/WindowsLibraryExample/MainMenuPage.xaml.h`（`ClipboardCard_Click` 宣言）
- `windows/WindowsLibraryExample/MainMenuPage.xaml.cpp`（`ClipboardCard_Click` 実装）
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj`（`ClInclude` / `Page` / `ClCompile` / `Midl` へ 4 エントリ）

### 1.3 UI 自動テスト対応でサンプル側に追加した変更

- `windows/WindowsLibraryExample/ClipboardPage.xaml`（`AutomationProperties.AutomationId` 52 要素）
- `windows/WindowsLibraryExample/ClipboardPage.xaml.h`（`CompleteWorkerOperation` の可視性）
- `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp`（コールバック配送のページ世代分離）

### 1.4 UI 自動テストプロジェクト（新規 14 ファイル）

```
windows/WindowsLibraryExampleUITest/
├─ WindowsLibraryExampleUITest.csproj
├─ Properties/
│   └─ AssemblyInfo.cs
├─ Infra/
│   ├─ AppIdentity.cs
│   ├─ IUiSession.cs
│   ├─ UiElement.cs
│   ├─ FlaUiSession.cs
│   └─ UiSessionFactory.cs
├─ Pages/
│   ├─ MainMenuPage.cs
│   └─ ClipboardPage.cs
└─ Tests/
    ├─ SmokeTests.cs
    ├─ ClipboardErrorCaseTests.cs
    ├─ ClipboardLifecycleTests.cs
    ├─ ClipboardBusyAndNavigationTests.cs
    └─ ClipboardMonitoringTests.cs
```

### 1.5 リポジトリ設定・ルール

- `.gitignore`（UI テストプロジェクトの `bin/` `obj/` をパス限定で追加）
- `agent-rules/coding-rules/common.md`（UI 自動テストの横断方針）
- `agent-rules/coding-rules/windows.md`（Windows 固有の UI 自動テスト方針、MSIX 配置制約、観測方法）

### 1.6 成果物

- `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`

### 1.7 非変更

- `windows/WindowsLibrary` 配下すべて
- `windows/UnityWindowsPlugin`
- `windows/WindowsLibraryExample/App.xaml` / `App.xaml.cpp` / `MainWindow.xaml*`
- `windows/WindowsLibraryExample/Package.appxmanifest`
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`（および他 2 つの既存 `.sln`）
- `windows/WindowsLibraryExample/pch.h`

### 1.8 v5 完了条件との差

v5 §11 は「新規 4 ファイルと既存 4 ファイルだけを変更する」と定めており、**サンプル実装単体ではこれを満たしていた**（当時 `git diff --stat` は既存 4 ファイル 25 行追加のみ）。

その後の UI 自動テスト対応（§5.4 以降）で、計画の想定を超える変更が入っている。いずれもユーザー承認のうえで別タスクとして実施したもので、内訳は 1.3 / 1.4 / 1.5 のとおり。既存 `.sln` と C++ プロジェクトのビルドグラフは変更していない。


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
| ページ離脱中の callback は破棄し復元しない | 配送先をページ instance に紐づける。request completion は受付時の `g_requestOwners[requestId] = m_pageId` を完了時に `g_activePageId` と照合し、発行したページが現役のときだけ配送する。ライブイベント（変更監視・履歴イベント・provider ログ）は発生時に表示中のページへ配送する。初期実装は `OnNavigatedFrom` での hub クリアと unknown id 分岐だけだったが、到着タイミングに依存するためレビュー v2 の指摘を受けて現方式へ変更した（§5.11.2） |
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

## 5. 自動UIテスト（workflow ステップ4）

本サンプル実装の時点では未実施とし、逸脱として記録した（§5.1 / §5.2）。その後、別タスクとして着手し Phase 1 / 2 を完了している（§5.8）。以下は着手前の判断から実施結果までの経緯。

### 5.1 着手時点で未実施とした理由

workflow ステップ4 は「既存のUIテストターゲットが無くても、OS標準のUIテストターゲット構成に従って追加する」と定めており、自動化可能な観点の実装を必須としている。今回はこれを実施していない。

理由は承認済み計画 v5 の完了条件との競合である。

- v5 §11 は「新規 4 ファイルと既存 4 ファイルだけを変更する」と定めている
- UIテストプロジェクトの追加はこの条件を必ず超える

**補足（当初の記載を訂正）**

- 開発者モードは**既に有効**（`AllowDevelopmentWithoutDevLicense=1` / `AllowAllTrustedApps=1`）。前提条件として不足していない
- `.sln` の変更は**必須ではない**。`WindowsLibraryTest` は `WindowsLibrary.sln` に属し `WindowsLibraryExample.sln` には含まれていないため、UIテストプロジェクトは独立した `.sln` を持つか直接ビルドする形で追加できる。制約は `.sln` ではなく v5 の変更ファイル数の完了条件であった

### 5.2 ユーザー判断

上記を提示し、「UIテストプロジェクトを追加せず、逸脱として記録する」を選択。Windows のUI自動テストは本リポジトリで初導入となるため、本サンプル実装とは分離し、独立したタスクとして扱う。

なお 8.1 / 8.2 / 8.3 の外部アプリ依存 26 確認項目を自動化しない判断は workflow に沿ったものであり、逸脱ではない。逸脱に該当するのは自動化可能な 29 確認項目を実装していない点のみ。

### 5.3 自動化可能だった範囲

v5 §8 の手動確認 55 項目のうち、アプリ内で完結し UI 自動化の価値がある 29 確認項目。

| 節 | 項目数 | 自動化 | 備考 |
|---|---|---|---|
| 8.4 Lifecycle / Thread / Busy | 17 | 17 | 状態遷移・busy・drain はアプリ内で完結 |
| 8.5 Error cases | 10 | 10 | 期待 errorCode が確定しており照合可能 |
| 8.2 Monitoring / Deferred | 8 | 2 | self copy 抑止と Reserve -> enumerate のみアプリ内で完結。他 6 項目は外部アプリでの貼り付けが provider 発火の前提 |
| 8.1 Interoperability | 10 | 0 | メモ帳 / Word / エクスプローラー / ペイントの内部UI検証 |
| 8.3 History | 10 | 0 | Win+V シェルUI、Windows 設定、別デバイスが必要 |
| **合計** | **55** | **29** | 残り 26 項目は手動 |

自動化しなかった 26 確認項目（8.1 の 10、8.2 の 6、8.3 の 10）は、workflow 自身が「自動化できない項目（他アプリ内部のUI検証等）」として挙げている類型に該当する。これらは第 6 章で手動確認を実施した。

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
| 2 | 8.4 Lifecycle / Thread / Busy 17 確認項目 | 順序依存シナリオ。Phase 1 の基盤を再利用 |
| 3 | 8.1 / 8.2 / 8.3 | 自動化せず手動維持 |

### 5.8 実施結果

#### 5.8.0 Phase 1

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

#### 5.8.2 Phase 2 実施結果

| 項目 | 結果 |
|---|---|
| テスト件数 | 28（SmokeTests 2 + Error cases 10 + Lifecycle 8 + Busy / 再入場 / shutdown 完了 8） |
| 結果 | 28 passed / 0 failed（実行時間 54 秒） |
| 対象 | v5 §8.4 と §8.5 の確認項目 |

**結果表示は最新 1 件しか保持せず、後続のコールバックで上書きされる。** `Request + Immediate Uninitialize` では `uninit returned FALSE` が表示された直後に、drain が配送した `CANCELED` コールバックの結果へ置き換わる。これは drain が正しく動いている証拠であり不具合ではないが、順序を伴う検証には使えないため、追記型のログ領域から読む形にした。

あわせて、**すべての操作がログを書くわけではない**ことも分かった。単発のコピーは結果表示のみを更新する。ログの存在を前提にする検証は、確実にログを残す操作（予約・履歴リクエスト・shutdown など）で状態を作る必要がある。

これらは `agent-rules/coding-rules/windows.md` の「テストコードの構造」へ反映済み。

### 5.9 レビュー v1 対応

`artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v1.md`（総合評価: 要修正（重大））への対応。

#### 5.9.1 指摘と対応

| 指摘 | 検証結果 | 対応 |
|---|---|---|
| H1 UIテストが再実行で失敗 | **再現（3/3 失敗）** | テスト側の欠陥。予約はプロセス寿命で生きているため、再入場後も provider のレンダリングログが載るのが正しい動作。「ログが空」ではなく「離脱前のトークン `[Reserve] OK` が残っていない」を検証する形へ変更 |
| H1 sink の世代分離 | 妥当 | `g_pageGeneration` を導入。`OnNavigatedFrom` で加算し、離脱前に queue された配送を破棄する |
| M1 二重 Init の偽陽性 | 妥当 | 1 回目の結果が結果行に残ったまま同じ marker を待っていた。2 回目の前に `CopyPlainText` を挟んで結果行を別 marker へ移す |
| M2 自動化範囲の集計誤り | **v5 §8.4 は 17 行、result は 16 と記載** | 17 へ訂正。未検証観点にテストを追加（5.9.2） |
| M3 Store app 終了を待たない | 妥当 | `Close()` 後に `HasExited` を上限付きで待機し、残存時は `Kill()`。失敗は握り潰さず記録する |
| M4 AUMID 照会の timeout が機能しない | 妥当 | 非同期読み取り + `WaitForExit(timeout)` + exit code / stderr 検査。timeout 時はプロセスを終了して明示的な配置エラーにする。PowerShell 側も `Select-Object -First 1` で単一値にする |
| M5 変更ファイル一覧の不一致 | 妥当 | §1 を現状へ全面書き換え（UI テストプロジェクト 12 ファイルとルール変更を含む） |
| L1 `CompleteWorkerOperation` が public | 妥当 | private へ戻した。member function 内の lambda からアクセスできるため公開の必然性がない |
| L2 テストが FlaUI を直接参照 | 妥当 | `UiSessionFactory.Launch()` を追加し、テストから `FlaUiSession` 参照を排除 |

#### 5.9.2 追加したテスト

M2 が挙げた未検証観点に対応する 5 件を追加した。

| テスト | 観点 |
|---|---|
| `Uninitialize_RunsTempCleanupAndLogsTheOutcome` | 8.4-8 cleanup 完了ログ |
| `Reinitialize_AfterFullTeardown_WorksAgain` | 8.4-9 再 Initialize -> Copy |
| `SelfCopy_DoesNotRaiseAChangeNotification` | 8.2-2 self copy の通知抑止 |
| `ReservedFormats_AreEnumeratedWhileStillDeferred` | 8.2-6 Reserve -> enumerate |
| `ReservedFormat_IsReportedAsAvailable` | 8.2-6 の補強 |

8.4-13（request 発行後にページ離脱）は、受付ログを待って完了が in-flight であることを確認したうえで、再入場後に前ページの記録が復元されないことを検証する形へ強化した。ただし**配送の瞬間はアプリ外から観測できない**ため、どちらのタイミングでも成立する契約を検証している。この限界はテストのコメントにも記載した。

#### 5.9.3 対応後の結果

| 項目 | 結果 |
|---|---|
| テスト件数 | 33（SmokeTests 2 + Error cases 10 + Lifecycle 8 + Busy / 再入場 / shutdown 10 + Monitoring 3） |
| 結果 | **33 passed / 0 failed**。連続 3 回の実行で再現 |
| 実行時間 | 約 1 分 30 秒〜1 分 50 秒 |

実行時間が Phase 2 完了時点の 54 秒から伸びたのは、M3 のプロセス終了待ちを追加したため（1 テストあたり約 1.5 秒）。テスト間の分離を優先した結果である。

#### 5.9.4 アプリ側の変更と再配置

L1 と H1 の対応で `ClipboardPage.xaml.h` / `.xaml.cpp` を変更したため、Visual Studio から Release / x64 で再配置している。インストール場所は従来と同じで、COM ExeServer のパスは変わっていない。

### 5.11 レビュー v2 対応

`artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v2.md`（総合評価: 要修正（重大））への対応。

#### 5.11.1 指摘と対応

| 指摘 | 検証結果 | 対応 |
|---|---|---|
| H1 世代分離が離脱後の callback を除外できない | **妥当。§5.9 の対応は不完全だった** | ページ instance ごとの一意 id へ変更し、request の所有ページを受付時に記録する方式にした（5.11.2） |
| M1 終了不能をログ出力だけで処理 | 妥当 | `WaitForExit()` の例外を catch せず伝播させ、テスト失敗にする。`Close()` の失敗のみ best effort。main window 取得に失敗した経路でも `Kill()` するようにした |
| M2 負条件が瞬時検査 | 妥当 | `IUiSession.StaysFalse` / `ClipboardPage.LogStaysWithout` を追加し、3 秒間ポーリングして禁止文字列が一度でも現れたら失敗させる。該当 3 箇所を置換 |
| M3 UI テストファイル数の不一致 | **妥当。12 と記載、実際は 14** | 14 へ訂正し、Tests 5 ファイルを含む全ファイルを列挙（§1.4） |

#### 5.11.2 H1 の修正内容

§5.9 で導入した `g_pageGeneration` は `OnNavigatedFrom` でのみ加算していた。このため離脱後に到着した callback は**加算後の値**を取得し、再入場した新ページ（generation は変わらない）と一致して配送されていた。到着タイミング次第で契約が破れる実装だった。

タイミングに依存しない形へ変更した。

| 対象 | 配送先の決め方 |
|---|---|
| request completion | **発行したページ**。受付時に `g_requestOwners[requestId] = m_pageId` を記録し、完了時に所有ページが現役の場合だけ配送する |
| ライブイベント（変更監視・履歴イベント・provider ログ） | **発生時に表示中のページ**。古い完了ではなく現在進行のイベントなので、この扱いが正しい |

`m_pageId` は `OnNavigatedTo` のたびに採番するため、Back から即座に再入場しても前の instance とは別の id になる。

#### 5.11.3 対応後の結果

| 項目 | 結果 |
|---|---|
| C++ Release / x64 ビルド | 成功、エラー 0 |
| テスト | **33 passed / 0 failed**。再配置後に連続 2 回で再現 |
| 実行時間 | 約 1 分 18 秒 |
| 終了後の残存プロセス | なし |

#### 5.11.4 実施しなかった提案

レビューは「completion を遅延・制御できるテスト境界を設け、受付 -> Back -> 再入場 -> 旧 completion の順序を決定的に作る」ことを提案している。これはサンプルアプリにテスト専用の遅延フックを追加することになるため、実施していない。

現状は 5.11.2 の所有ページ方式により**構造として競合が発生しない**が、そのことをテストで証明できてはいない。負条件テストは 3 秒の観測期間で「旧ページのログが届かない」ことを確認するに留まる。テスト専用フックを追加するかは別途判断が必要。

### 5.13 レビュー v3 対応

`artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v3.md`（総合評価: 要修正（軽微））への対応。v2 の重大指摘 H1 は解消と評価された。

| 指摘 | 対応 |
|---|---|
| M1 main window 取得失敗時に `Kill()` 後の終了を待たない | 終了処理を `EnsureExited` へ共通化し、teardown と起動失敗経路の両方で「待機 -> Kill -> 再待機 -> 残存なら例外」を通す。起動失敗と後始末失敗が重なった場合は `AggregateException` で両方報告する |
| M2 §2.4 が旧 callback 方式のまま | 現行方式（`g_requestOwners` と `g_activePageId` の照合、ライブイベントは表示中のページへ配送）へ更新し、初期実装から変更した経緯も併記した |
| L1 `StaysFalse` に `Dispose` 用コメント | コメントを本来の member へ移した |

テスト専用の遅延フックはレビューで不要と判定されたため追加していない。

アプリ側の変更はなく、再配置は不要。対応後も **33 passed / 0 failed** を連続 2 回で確認した。

### 5.15 レビュー v4: コードレビュー完了

`artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v4.md`

| 項目 | 結果 |
|---|---|
| 総合評価 | **LGTM** |
| v3 の 3 件 | すべて解消 |
| UI テスト | 33 passed / 0 failed |
| 終了後の残存プロセス | なし |
| 新規指摘 | なし |

コードレビューは完了。残るのは外部アプリ・Win+V・Windows 設定・別デバイス・遅延レンダリングを伴う 26 項目の手動確認で、リリース前の未確認事項として open。

#### レビューを通して見つかった実質的な欠陥

自動テストとレビューがなければ残っていた 2 件。

| 欠陥 | 内容 |
|---|---|
| ページ離脱後の callback 配送 | 初期実装は到着タイミングに依存し、離脱後に届いた completion が再入場した新ページへ配送され得た。request の所有ページを受付時に記録する方式へ変更し、構造として保証する形にした |
| 二重 Initialize テストの偽陽性 | 1 回目の結果が結果行に残ったまま同じ marker を待っており、2 回目が Bridge に到達しなくても成功していた |

いずれもサンプルアプリの UI 上は正常に見えるため、手動確認では発見しにくい類のものだった。

### 5.16 残作業

| Phase | 状態 |
|---|---|
| 1（8.5 Error cases） | 完了 |
| 2（8.4 Lifecycle / Thread / Busy） | 完了 |
| レビュー v1 対応 | 完了 |
| レビュー v2 対応 | 完了 |
| レビュー v3 対応 | 完了 |
| コードレビュー（v4 LGTM） | 完了 |
| 8.2 のアプリ内完結分 | 完了（self copy 抑止、Reserve -> enumerate） |
| 8.1 / 8.3 と 8.2 の外部アプリ依存分 | 自動化せず手動維持。第 6 章で 26 項目の手動確認を実施済み |

自動化の対象外として残るのは、他アプリ内部の UI 検証、Win+V のシェル UI、Windows 設定、別デバイス連携を伴う観点。

---

## 6. 実機確認（workflow ステップ6）: 完了

実施日: 2026-09-05
実施環境: Windows 11 Home 10.0.26200 / Release・x64 配置 / .NET 10 SDK 10.0.400

### 6.1 対象と結果

第 5 章で自動UIテスト 33 件を作成したため、本章の対象は**自動化できなかった 26 確認項目**である。内訳は §8.1 全 10 項目、§8.2 の外部アプリ依存 6 項目、§8.3 全 10 項目。

| 節 | OK | NG | 未実施 | 計 |
|---|---|---|---|---|
| 8.1 Interoperability | 10 | 0 | 0 | 10 |
| 8.2 Monitoring / Deferred | 6 | 0 | 0 | 6 |
| 8.3 History | 8 | 1 | 1 | 10 |
| **合計** | **24** | **1** | **1** | **26** |

8.2 は当初 1 件が NG だったが、本章で修正し再確認して OK となった（発見事項 F2）。

なお §8 の項目を消化した後、ボタン単位でのカバレッジ照合を行い 9 ボタンの未操作が判明したため追加確認を実施した（§6.6）。最終的に 49 操作ボタン中 48 を確認済み。

### 6.2 確認項目別の結果

#### 8.1 Interoperability（10/10 OK）

| # | 項目 | 結果 |
|---|---|---|
| 1 | CopyPlainText -> Notepad | OK。末尾改行なしを PastePlainText の往復でも確認 |
| 2 | CopyHtml -> Word | OK。"Hello" のみ太字 |
| 3 | CopyHtml -> Notepad | OK。タグなしのフォールバックテキスト |
| 4 | CopyFiles <-> Explorer | OK。往復2件のパスが一致 |
| 5 | CopyImage <-> Paint | OK。RGB(0,120,215) の 8x8。往復は width=1887 height=820 bitCount=32 |
| 6 | CopyMultipleFormats -> Word / Notepad | OK。1回のコピーから各アプリが対応形式を選択 |
| 7 | text + HTML -> GetPreferredFormat | OK。CF_UNICODETEXT |
| 8 | files only -> GetPreferredFormat | OK。CF_HDROP |
| 9 | image only -> GetPreferredFormat | OK。CF_DIB |
| 10 | custom only -> GetPreferredFormat | OK。(no candidate format) |

項目 5 で報告されたバイト数（6193152）はピクセル実データ（6189400）より約 3.7KB 大きいが、`GlobalSize` が確保ブロックを 4KB 境界へ切り上げる Win32 の既知挙動であり異常ではない。

#### 8.2 Monitoring / Deferred（6/6 OK）

| # | 項目 | 結果 |
|---|---|---|
| 11 | Init -> external copy | OK。コピー回数だけ `[Monitor]` が増加 |
| 12 | Uninit TRUE -> external copy | OK。`uninit returned TRUE` 後は通知なし |
| 13 | Reserve -> external paste | OK。履歴オフで検証。予約時は未発火、貼付時に CF_UNICODETEXT のみ発火 |
| 14 | Reserve -> Word paste | OK。HTML Format(201/201) と CF_UNICODETEXT(52/52) で size と fill が一致 |
| 15 | Reserve -> app exit -> paste | **修正後 OK**（発見事項 F2） |
| 16 | Reserve -> external copy | OK。`[Provider]` は発火せず、貼付結果も外部内容 |

#### 8.3 History（8 OK / 1 NG / 1 未実施）

| # | 項目 | 結果 |
|---|---|---|
| 17 | Availability | OK。設定の on/off に追従 |
| 18 | disabled -> GetHistory | OK。errorCode=10 (HISTORY_DISABLED) |
| 19 | GetHistory callback | OK。newest first、timestamp は文字列 |
| 20 | Restore callback待機 -> Paste | OK。復元内容が貼り付けられる |
| 21 | Delete callback待機 -> GetHistory | OK。count=10 -> 9、対象項目が消失 |
| 22 | Clear callback待機 -> GetHistory | OK。count=3 -> 1、ピン留め項目のみ残存 |
| 23 | Set callbacks -> copy / setting change | **NG**（発見事項 F3）。履歴追加は正常、設定変更イベントが不安定 |
| 24 | SENSITIVE -> Win+V | OK。Ctrl+V では貼付可能、Win+V 一覧には非表示 |
| 25 | EXCLUDE_ROAMING -> another device | **未実施**。2台目デバイスと同期有効が必要な環境制約 |
| 26 | GetHistory -> Cancel | OK。同一 id の completed が常に1行のみ |

### 6.3 発見事項

#### F1: 履歴有効時は予約直後に provider が発火する（実装は正常）

`Reserve Deferred Formats` を押した直後、外部貼り付け前に予約全形式の `[Provider] phase=size` / `phase=fill` が発火した。

切り分けの結果、アプリ側（ClipboardPage.xaml.cpp）もライブラリ側（WindowsClipboardManager.cpp）も予約時にレンダリングを行っておらず、クリップボード履歴を無効にすると発火しなくなることを確認した。**呼び出し元は Windows のクリップボード履歴サービス**であり、履歴に内容を保存するため即座に全形式を要求する。実装の不具合ではない。

対応: 設計書 v5 §8.2 に前提条件として追記。`reserveDeferredFormats` のヘッダーコメントにも明記した。

#### F2: アプリ終了時に遅延レンダリング内容が失われる（修正済み）

予約したままアプリを正常終了するとクリップボードが空になり、設計書 v5 §8.2「Reserve -> app exit -> paste」を満たさなかった。VS デバッガー経由か切り分けるため AUMID から直接起動して再実行したが同じ結果で、デバッガーは無関係と確認した。

原因はサンプルアプリ側にあった。ライブラリは `WM_RENDERALLFORMATS` を実装済み（WindowsClipboardWindow.cpp:28-30、WindowsClipboardCore.cpp:687）だが、このメッセージは所有ウィンドウの `DestroyWindow` 時にのみ送られ、その `DestroyWindow` は `uninitClipboardManager` 経路からしか到達しない。サンプルアプリには終了フックが存在せず、プロセスがそのまま終了していた。

修正: `MainWindow` に `Closed` ハンドラーを追加し、新設した `ShutdownClipboardManagerForAppExit()` を呼ぶ。同関数は初期化済みのときのみ `uninitClipboardManager` を1回呼ぶ。`FALSE` 時の正規の回復手段はメッセージポンプを回しての再試行だが、閉じ中のウィンドウでは回せずアプリ終了をブロックするため、あえて再試行しない。

再確認: Reserve -> × で終了 -> メモ帳へ貼付で内容が保持されることを実機確認。UIテスト 33 件も再実行し回帰なし。

#### F3: 履歴の設定変更イベントが信頼できない（仕様上の制約）

`setClipboardHistoryCallbacks` 登録後の観測結果は次のとおり。

| セッション | 購読時の履歴状態 | 設定変更イベント |
|---|---|---|
| A | オン | 最初のオフで1回だけ発火。以後は何度切り替えても発火せず |
| B（再起動後） | オフ | 一度も発火せず |

セッション B の状態で外部コピーを行うと `[History] a new item was added to the history` は正常に発火した。**購読基盤とコールバック配送は機能しており**、問題は `Clipboard.HistoryEnabledChanged` イベントソース側にある。ライブラリの `RaiseEvent`（WindowsClipboardHistoryWinRt.cpp:95-113）にイベントを消費する処理はなく、`alive` は `StopWatch()` でのみ false になる。

深刻度は限定的。主要な通知である履歴追加は影響を受けない。

対応: 実装では解消できないため API 契約として明文化した。利用側は `onHistoryEnabledChanged` / `onRoamingEnabledChanged` に依存せず、設定の現在値が必要な時点で `getClipboardHistoryAvailability` を呼ぶ（項目 17 で信頼性を確認済み）。`onRoamingEnabledChanged` は同一経路のため同じ制約を持つ可能性が高いが未検証。

#### O1: スクリーンショット撮影がクリップボードを上書きする（手順への注意）

確認中に説明のつかない `[Monitor]` が観測されたが、原因はスクリーンショット撮影によるクリップボードへの画像書き込みだった。外部変更として正しく検知されており不具合ではない。コピーと貼り付けの間に撮影すると内容が失われ、履歴の件数も変動するため、設計書 §8 に注意として追記した。

#### O2: Restore 直後に `[Monitor]` が発火する（実装は正常）

復元を実行するのは Windows の履歴サービスでありライブラリの書き込み経路ではないため、外部変更として扱われるのが妥当。設計書 §8.3 に追記した。

### 6.4 未実施項目

項目 25（EXCLUDE_ROAMING -> another device）のみ。同一 Microsoft アカウントでサインインした2台目の Windows デバイスと、両デバイスでの「デバイス間で同期」有効が必要である。項目 17 の時点で `roamingEnabled: false` であり、前提を満たせないためユーザー判断で対象外とした。

確認できていない項目を OK として扱うことはしていない。

### 6.5 修正に伴う変更

| ファイル | 変更 |
|---|---|
| `windows/WindowsLibraryExample/ClipboardPage.xaml.h` | `ShutdownClipboardManagerForAppExit()` を宣言 |
| `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp` | 同関数を実装 |
| `windows/WindowsLibraryExample/MainWindow.xaml.cpp` | `Closed` ハンドラーを登録 |
| `windows/WindowsLibrary/WindowsClipboardManager.h` | F1・F2・F3 の API 契約を追記 |

コミット: `df206b1d` (fix)、`f1dfda0f` (docs)

`WindowsLibraryExample` の Release/x64 クリーンリビルドは成功。なおソリューション全体のクリーンビルドは `UnityWindowsPlugin` の COM 登録ステップが管理者権限を要求して MSB8011 で失敗するが、本作業と無関係の既存事象である。

### 6.6 追加確認（ボタン単位のカバレッジ照合）

§8 の 55 項目を消化した後、**全 49 操作ボタンが実際に押されたか**を照合したところ、9 ボタンが自動テスト・手動確認のいずれでも未操作であることが判明した。

原因は実施漏れではない。§8 はシナリオの一覧であってボタンの一覧ではないため、シナリオに登場しない操作は誰も押さない構造になっている。設計書 §8.7 として観点を追記した。

| # | ボタン | 結果 |
|---|---|---|
| A-1 | CopyPlainTextEmpty | OK。errorCode=0、CF_UNICODETEXT が載り PastePlainText も成功 |
| A-2 | PasteHtml | OK。CF_HTML のヘッダー・ラッパーを除いたフラグメントのみを返す |
| A-3 | PasteCustomFormat | OK。`29 bytes: native-toolkit-sample-payload` でサイズ・内容とも一致 |
| A-4 | ClearClipboard | OK。形式一覧が `[]`、貼り付けは FORMAT_UNAVAILABLE(5) |
| A-5 | RecoverDeferredState | OK。errorCode=0。呼び出し後も予約 2 形式が残る |
| A-6 | CleanupTempFiles | OK。1 回目 removed 2、2 回目 removed 0 で errorCode=0 |
| A-7 | CopyMultipleFormatsWithImage | OK。3 形式を 1 回で配置し Notepad / ペイント / Word が各々選択 |
| A-8 | CopyExcludeHistory | OK。Win+V に出ず Ctrl+V では貼付可能 |
| - | CopyExcludeRoaming | **未実施**。項目 25 と同じ 2 台目デバイスの制約 |

A-5 は部分状態（`CLIPBOARD_ERROR_PARTIAL_STATE`）の発生に Win32 失敗とロールバック失敗の同時発生が必要で通常操作では再現できないため、「復旧すべき状態がないときに安全に呼べ、正常な予約を破壊しないこと」までの確認である。

#### 最終カバレッジ

| 区分 | 数 |
|---|---|
| 全操作ボタン | 49 |
| 自動UIテストで操作 | 27 |
| 手動確認で操作 | 21 |
| **確認済み合計** | **48** |
| 未確認 | **1**（CopyExcludeRoaming） |

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
