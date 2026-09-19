# Windows ライブラリの構成再編と C++ API / C ABI 分離

- 記録日: 2026-09-19
- 分類: 横断課題（アーキテクチャ）。機能追加ではない
- 対象: `windows/WindowsLibrary`、`windows/UnityWindowsPlugin`（`windows/WindowsLibraryCApi` に置き換える）、`windows/WindowsLibraryTest`、`windows/WindowsLibraryExample`、`scripts/build_windows_library_dll.ps1`、NuGet パッケージ `NativeToolkit`
- チケット: 未採番
- 関連: `artifact/topics/migration/README.md` の `windows-toolchain-migration`（重複あり。未決事項 D-1）

## 1. 何が問題か

### 1.1 Windows だけライブラリとプラグインの役割が逆になっている

| OS | ライブラリ本体 | Unity プラグイン |
|---|---|---|
| Android | `android_library`: Kotlin の API | `unity_android_plugin`: C ABI / JNI ブリッジ |
| iOS | `IosLibrary`: Swift の API | `UnityIosPlugin`: C ABI ブリッジ |
| macOS | `MacLibrary`: Swift の API | `UnityMacPlugin`: C ABI ブリッジ |
| **Windows** | **`WindowsLibrary`: C ABI（47 関数）** | **`UnityWindowsPlugin`: MFC の雛形だけで中身が無い** |

Windows だけ、ライブラリ本体がブリッジの役を担い、ブリッジ側が空になっている。

### 1.2 内部の C++ クラスが C ABI の形をしている

`WindowsClipboardManagerInternal.h` の `ClipboardManager` はクラスだが、シグネチャは C ABI と同じ形をしている。

```cpp
DWORD    PastePlainText(wchar_t* buffer, DWORD bufferSize, DWORD* pError);
uint32_t GetClipboardHistory(ClipboardRequestCallback cb, DWORD* pError);  // 結果は JSON 文字列
```

C++ の層が無いのではなく、C++ の層が C ABI の都合に合わせて作られている。

### 1.3 ソースが 1 つのフォルダに並んでいる

`windows/WindowsLibrary` 直下に 37 ファイルが並び、そのうち Clipboard だけで 18 ファイルある。他の 3 OS は `<Feature>/{Application,Data,Domain}` に分けている。

### 1.4 使っていない MFC と COM の雛形が残っている

| 項目 | 状態 |
|---|---|
| `UseOfMfc` | WindowsLibrary: Static ×2 / Dynamic ×2、UnityWindowsPlugin: Static ×4、WindowsLibraryTest: Dynamic ×2 |
| `CWinApp` | `WindowsLibrary.h` / `WindowsLibrary.cpp` の雛形 |
| MFC の実使用 | `WindowsDialogManager.cpp` の `CDialogEx m_dialogEx` だけ。生成されるだけで使われていない（`IDD_DIALOG` リソースも同様） |
| COM | `.idl` と、`.def` の `DllCanUnloadNow` / `DllGetClassObject` / `DllRegisterServer` / `DllUnregisterServer` |

Dialog は Win32 の common dialog、Clipboard は Win32 + WinRT、Notification は Windows App SDK で実装されており、MFC も COM も機能には使われていない。

### 1.5 関数の公開方法が 2 種類ある

公開している 47 関数（Dialog 6 / Notification 14 / Clipboard 27）のうち、39 関数は `.def` に書かれている。残りの 8 関数は `.def` に無く、`__declspec(dllexport)` だけで公開されている。

- Dialog の 6 関数すべて
- `initWinAppSdk`
- `openNotificationSettings`

### 1.6 NuGet パッケージに Clipboard のヘッダーが入っていない

`scripts/build_windows_library_dll.ps1` の `Headers` に書かれているのは `common.h`、`WindowsDialogManager.h`、`WindowsNotificationManager.h` の 3 つだけで、`WindowsClipboardManager.h` が無い。そのため NuGet 経由では Clipboard を使えない。

### 1.7 構成によって C++ 標準が違う

`WindowsLibrary.vcxproj` の `LanguageStandard` は `stdcpp17` が 4 構成、`stdcpp20` が 1 構成。

## 2. なぜ今やるか

- **Windows の share が未実装**（他の 3 OS は実装済み）。今の構成のまま share を追加すると、追加した分も含めて後で書き直すことになる。share の前にやれば、share は最初から新しい構成で 1 回書けば済む
- 今の規模は、ライブラリ 8,349 行（Clipboard 4,665 / Notification 1,592 / Dialog 844）、公開関数 47 個、サンプル 3 画面で 2,545 行。機能が増えるほど、移す作業も増える
- C ABI を配っている NuGet パッケージを作り変える破壊的変更になる。利用者が少ない今がいちばん影響が小さい

## 3. 目標の構成

```
windows/
  WindowsLibrary/                           # C++ API（公開）
    include/NativeToolkit/                  # NuGet に入れる公開ヘッダー
      Clipboard.h  Notification.h  Dialog.h  Error.h  Types.h
    src/
      Clipboard/{Application,Data,Domain}/  # 他の 3 OS と同じ分け方
      Notification/{Application,Data,Domain}/
      Dialog/{Application,Data,Domain}/
      Common/
  WindowsLibraryCApi/                       # 汎用の C ABI（公開）
    include/NativeToolkitC/                 # C ABI の公開ヘッダー
      Clipboard.h  Notification.h  Dialog.h
    src/
      Clipboard/  Notification/  Dialog/    # C++ API を呼び出して型を変換するだけ
    WindowsLibraryCApi.def                  # 47 関数をここに移す
```

依存の向きは `WindowsLibraryCApi` → `WindowsLibrary`。機能の実装は `WindowsLibrary` にだけ置き、`WindowsLibraryCApi` は型の変換（`std::wstring` とバッファ、構造体とデータ受け渡し形式、`std::function` と関数ポインタ）だけを受け持つ。

- ネイティブの利用者（`WindowsLibraryExample` など C++ / WinRT のアプリ）は C++ API を使う
- C ABI の利用者（C#、Rust、Python など）は `WindowsLibraryCApi` を使う。Unity もその 1 つで、Unity 側の確認は別リポジトリ `unity-native-plugin` で行う

### 3.1 名前を Unity から変える理由

他の 3 OS のプラグイン（`unity_android_plugin` / `UnityIosPlugin` / `UnityMacPlugin`）も、コードは Unity に依存していない（`UnitySendMessage` などの Unity 固有 API の使用は 0 件）。それでも名前を残すのは、既に配布していて、変えると `unity-native-plugin` への破壊的変更になるからである。

Windows だけ名前を変えるのは、次の 2 つが理由である。

- `UnityWindowsPlugin` は一度も配布していない（ビルドスクリプトで `Packable = $false`、`dist/` に成果物が無い）。名前を変えても外部に影響しない
- Windows の C ABI は Unity 専用ではなく、汎用の C ABI として設計する

| 項目 | 変更前 | 変更後 |
|---|---|---|
| プロジェクト | `UnityWindowsPlugin` | `WindowsLibraryCApi` |
| 配布物の接頭辞 | `unity-windows-native-toolkit` | `windows-native-toolkit-capi` |

`UnityWindowsPlugin` の中身は MFC の雛形だけなので、名前を変えるのではなく、`WindowsLibraryCApi` を新しく作って `UnityWindowsPlugin` を削除する。

## 4. C++ API の方針

| 今の C ABI | C++ API |
|---|---|
| 出力引数 `DWORD* pError` | `std::expected<T, Error>`（C++23）か自前の `Result<T>`。どちらにするかは D-2 |
| `#define CLIPBOARD_ERROR_*` | `enum class ClipboardError : uint32_t` |
| `wchar_t* buffer, DWORD bufferSize` | `std::wstring` を返す |
| 履歴などを JSON 文字列で返す | `std::vector<ClipboardHistoryItem>` などの構造体 |
| 関数ポインタのコールバック | `std::function<void(...)>` |
| `init` / `uninit` / `canDestroy` を手で呼ぶ | RAII のオブジェクト |

```cpp
namespace NativeToolkit::Clipboard {

class Session {
public:
    static std::expected<Session, Error> Create(HWND owner);
    ~Session();

    std::expected<void, Error>         CopyPlainText(std::wstring_view text, WriteOptions = {});
    std::expected<std::wstring, Error> PastePlainText();
    std::future<std::expected<std::vector<HistoryItem>, Error>> GetHistory();

    void OnClipboardChanged(std::function<void()> handler);
};

}
```

C ABI でのデータの受け渡し形式は D-6 〜 D-10 で決める。どの形式にしても変換は `WindowsLibraryCApi` が受け持ち、`WindowsLibrary` の C++ API には持ち込まない。

## 5. 段階

1 段階 = 1 ブランチ = 1 PR。段階 0 で全機能の自動テストをそろえてから着手する。段階 1・2 は動作を変えないので、段階 3 以降のレビューを API の設計だけに絞れる。

| 段階 | 内容 | 動作の変更 | ブランチ | PR |
|---|---|---|---|---|
| 0a | スパイク: FlaUI でトーストとバッジを扱えるかを確かめ、computer use で補う項目を確定する（7.2）。**完了** | 無し | `feature/NTKIT-16` | - |
| 0b | `DialogPage.xaml` と `NotificationPage.xaml` に AutomationId を付ける（見た目も動作も変えない。例外として、Notification 画面に 5 秒後に予約するボタンを 1 つ足す） | 無し | - | - |
| 0c | Dialog と Notification の UI テストを追加する。FlaUI で扱えない項目は computer use の確認手順書にする | 無し | - | - |
| 0d | `scripts/test_windows.ps1` を作る。**今のコードで全件通ることを確かめ、結果を記録する** | 無し | - | - |
| 1 | `WindowsLibrary` と `WindowsLibraryTest` から MFC / COM の雛形を消し、C++ 標準をそろえる | 無し | - | - |
| 2 | ディレクトリを `src/<Feature>/{Application,Data,Domain}` に分ける | 無し | - | - |
| 3 | C++ API を `include/NativeToolkit/` に作り、中身を C++ の形に書き直す。**この時点ではまだ C ABI も残す** | ライブラリに C++ API が増える | - | - |
| 4 | サンプルを C++ API に移行する。移行前と同じ UI テストが通ることを確かめる | 無し（サンプルが使う API だけが変わる） | - | - |
| 5 | `WindowsLibraryCApi` を新しく作って C ABI を移し、`WindowsLibrary` から C ABI を削除する。`UnityWindowsPlugin` を削除する | C ABI を提供する DLL が変わる | - | - |
| 6 | NuGet、マニュアル、Doxygen を新しい API に合わせる | - | - | - |
| 7 | CI を作る（ユニットテストだけ。UI テストと computer use はローカルで実行する） | - | - | - |

サンプルの移行（段階 4）は、C ABI の削除（段階 5）より前に行う。逆にすると、段階 5 が終わった時点でサンプルがビルドできなくなる（C ABI のヘッダーを include しているため）。

### 5.1 設計書

この README は企画書の役割を持つ。実装に着手できる粒度の設計書は、公開 API を決める段階とテストの段階だけに書く。

| 段階 | 設計書 | 理由 |
|---|---|---|
| 0（テスト） | 書く（**作成済み**: `designs/2026-09-19-windows-architecture-ui-test-design.md`） | Dialog と Notification にどんな UI テストを書き、何を確かめるか。段階 0a の結果に基づく FlaUI と computer use の分担 |
| 1 MFC / COM の除去 | 書かない | 機械的な作業。この README の表と実装結果で足りる |
| 2 ディレクトリの再編 | 書かない | 同上 |
| 3 C++ API | 書く | 公開 API は長く残る約束になる |
| 4 サンプルの移行 | 書かない | 段階 3 の設計書に従って書き換えるだけ |
| 5 C ABI | 書く | 公開 API。D-6 〜 D-10 の決定を反映する |
| 6 ドキュメント / 7 CI | 書かない | この README の表で足りる |

各設計書に書くこと:

| 設計書 | 書くこと |
|---|---|
| UI テスト | 機能ごとのテストケースの一覧と、確かめる内容。FlaUI で扱う項目と computer use で扱う項目の分担。computer use の確認手順書の一覧 |
| C++ API | 47 関数それぞれの置き換え先。エラーの型、所有権、スレッドの約束。**既存の約束が新しい C++ API のどこで守られるかの対応表** |
| C ABI | 公開する関数の一覧。D-6 〜 D-10 の決定の反映。メモリの確保と解放の決まり |

C++ API の設計書にある「既存の約束の対応表」は、次の設計書から作る。C++ API に書き直しても、ここに書かれた約束（たとえば Clipboard の「コールバックは必ずオーナーの UI スレッドで、受け付けた要求 1 件につき 1 回だけ呼ぶ」）は守り続ける必要がある。対応表が無いと、書き直したときに約束が抜けても気づけない。

| 機能 | 約束が書かれている設計書 |
|---|---|
| Clipboard | `artifact/features/clipboard/designs/2026-07-28-windows-clipboard-design-v2.md`（1,518 行） |
| Notification | `artifact/features/notification/designs/2026-05-30-windows-notification-design-v3.md`（922 行） |
| Dialog | **無い**。約束はコードから読み取って書き起こす |

UI テストの設計書は、既存のサンプルアプリの設計書にある手動確認の観点を出発点にする（Clipboard: `2026-07-31-windows-clipboard-sample-app-design-v5.md`、Notification: `2026-05-31-windows-notification-sample-app-design-v2.md`）。Dialog にはサンプルアプリの設計書も無い。

#### 書く時期

全部を先に書かず、各段階の直前に書く。スパイクの結果や未決事項の決定が、設計書の中身を左右するため。

1. 段階 0a のスパイクを行う
2. UI テストの設計書を書き、段階 0b 〜 0d を進める
3. D-1 〜 D-3 を決め、C++ API の設計書を書き、段階 1 〜 4 を進める
4. D-4 〜 D-10 を決め、C ABI の設計書を書き、段階 5 以降を進める

#### 置き場所

```
artifact/topics/windows-architecture/
  README.md                                                  # 企画書の役割（この文書）
  designs/
    YYYY-MM-DD-windows-architecture-ui-test-design.md        # 段階 0
    YYYY-MM-DD-windows-architecture-cpp-api-design.md        # 段階 3
    YYYY-MM-DD-windows-architecture-c-abi-design.md          # 段階 5
  results/                                                   # 段階ごとの実装結果
```

公開 API の 2 本（C++ API と C ABI）は、後から変えると利用者全員に影響する。これまでの機能開発と同じく、別のモデルにレビューしてもらってから着手する。

## 6. 段階ごとに壊れる場所

| 場所 | 内容 | 影響する段階 |
|---|---|---|
| `WindowsLibraryTest.vcxproj` | `..\WindowsLibrary\*.cpp` を 8 ファイル直接指定している。`AdditionalIncludeDirectories` にも `..\WindowsLibrary` がある | 2 |
| `WindowsLibraryTest.vcxproj` | `UseOfMfc: Dynamic` | 1 |
| `WindowsLibrary.vcxproj.filters` | フォルダ定義をすべて書き直す | 2 |
| `WindowsLibraryExample` | 3 画面が `WindowsClipboardManager.h` などを直接 include している | 4 |
| `scripts/build_windows_library_dll.ps1` | `Project` / `Def` / `Rc` / `Headers` のパス | 2・3・5 |
| `windows/WindowsLibrary/docs/` | リポジトリに入っている Doxygen の生成物（html / latex） | 2・3・6 |
| `UnityWindowsPlugin` という名前の参照 | `README.md` / `README.ja.md` / `README.ko.md`、`agent-rules/coding-rules/windows.md`、`scripts/build_windows_library_dll.ps1`、`scripts/check_design_consistency.py`、`WindowsLibraryExample.sln`（リポジトリ内で 15 ファイル・91 か所） | 5 |

## 7. 検証方法

手動テストは行わない。各段階の終わりに、次の 3 つをすべて実行し、段階 0d で記録した結果と変わらないことを確かめる。

| 層 | 手段 | 守るもの | 実行 |
|---|---|---|---|
| ユニットテスト | `WindowsLibraryTest`（CppUnitTest） | ライブラリ内部の動作 | `scripts/test_windows.ps1` |
| UI テスト | `WindowsLibraryExampleUITest`（MSTest + FlaUI） | サンプルアプリから見た動作 | `scripts/test_windows.ps1` |
| 画面の確認 | computer use | FlaUI で扱えない項目だけ | Claude のデスクトップアプリから確認手順書を実行する |

### 7.1 UI テストを回帰テストの基準にする理由

`WindowsLibraryTest` は内部クラス（`ClipboardCore`、`ClipboardHistoryCoordinator`、`NotificationManager` など）の `.cpp` を直接コンパイルしてテストしている。段階 3 では内部クラスそのものを書き直すので、ユニットテストも一緒に書き直すことになる。書き直したテストが通っても、それは以前と同じ動作をする証明にはならない。

UI テストはサンプルアプリをボタン操作と表示で外から確かめるので、ライブラリの中身や、サンプルが呼ぶ API（C ABI か C++ API か）が変わっても同じテストをそのまま使える。**段階の前後で同じ UI テストが通ることを、動作が変わっていない根拠にする。**

段階 0 を始める前のテストの状態:

| 機能 | ユニットテスト | UI テスト | サンプル画面の AutomationId |
|---|---|---|---|
| Clipboard | 88 件 | 31 件 | 52 個 |
| Notification | 21 件 | 0 件 | 0 個 |
| Dialog | 0 件 | 0 件 | 0 個 |
| メニュー・起動 | - | 2 件 | 3 個 |

### 7.2 FlaUI と computer use の使い分け

基本は FlaUI で自動化する。**FlaUI で扱えないとスパイク（段階 0a）で確認できた項目だけ**を computer use で確かめる。

段階 0a の結果で、次のとおり確定した（詳細は `results/2026-09-19-windows-architecture-stage0a-spike-result.md`）。通知は、数秒で消えるバナーではなく、**通知センター（Win+N）から確かめる**のが基本になる。

| 項目 | 手段 | 確認すること |
|---|---|---|
| Dialog（`MessageBox`、ファイル・フォルダのダイアログ） | FlaUI | ダイアログを Win32 で見つけ、コントロール ID でボタンを押し、サンプルに表示された戻り値を確かめる。ダイアログを開くボタンはマウスクリックで押す（UI テストの設計書の 3.1、3.2） |
| Notification の API の戻り値とサンプルの表示 | FlaUI | 他の画面と同じ |
| 通知のタイトル・本文 | FlaUI | 通知センターで通知を見つけ、タイトルと本文を確かめる |
| 通知のボタン・入力欄・選択肢 → コールバック | FlaUI | 通知センターで通知を展開して操作し、サンプルに表示された `argsJson` を確かめる |
| 進捗 | FlaUI | 通知センターで進捗バーの値を確かめる |
| スケジュール通知 | FlaUI | 予約した時刻の後に、通知センターで確かめる |
| 有効期限 | FlaUI | `GetAllNotifications` で確かめる（通知センターは期限が過ぎても表示が残ることがある） |
| バナーの表示とボタン | FlaUI | 集中モード（応答不可）がオフのときだけ表示される。ボタンは表示アニメーションが終わってから押す |
| バッジ（数字） | FlaUI | タスクバーのアプリのボタンの子要素 `BadgeText` の値を確かめる |
| 画像の中身 | **computer use** | 画像の要素があることまでは FlaUI で分かるが、どの画像かは分からない |
| バッジのグリフの種類 | **computer use** | グリフがあることまでは FlaUI で分かるが、種類（alert など）は分からない |
| 音声 | **対象外** | UI Automation でも computer use でも確かめられない。音声の指定を正しく渡していることは、ライブラリのユニットテストで確かめる |

通知センターとバナーには他のアプリの通知も並ぶ。テストの記録もスクリーンショットも、サンプルアプリの通知だけに限る。

### 7.3 computer use を使うときの決まり

computer use は画面を AI が解釈して操作するので、FlaUI と違って結果が毎回同じになる保証が無い。次の決まりで、判定のぶれを抑える。

- **FlaUI で扱える項目には使わない**
- 確認する項目ごとに確認手順書を用意し、`windows/WindowsLibraryExampleUITest/ComputerUse/` に置く。手順書には、操作の手順、期待する結果、合格の条件を書く
- 判定があいまいな場合は失敗として扱う
- 確認した画面のスクリーンショットを、結果の証拠として残す
- このトピックの作業では、各段階の終わりに FlaUI の後で実行する（対象の項目が少ないので負担は小さい）
- computer use は Claude のデスクトップアプリから使う。VS Code のセッションからは使えない

### 7.4 実行環境

- UI テストと computer use は、画面を操作できる環境で、サンプルを MSIX で配置してから実行する。CI には入れない
- `scripts/test_windows.ps1` の中身: `WindowsLibrary` と `WindowsLibraryTest` をビルドして `vstest.console.exe` で CppUnitTest を実行し（`agent-rules/workflows/implement-feature/workflow.md` の Windows の手順と同じ）、続けて `WindowsLibraryExampleUITest` を実行する

## 8. 未決事項

| ID | 決めること | 選択肢 | 推奨 |
|---|---|---|---|
| D-1 | `windows-toolchain-migration` との関係 | 統合する / 分ける | **統合**。段階 1 の C++ 標準の決定がそのまま移行作業になる。分けると、C++17 のまま API を設計して後でやり直すことになる |
| D-2 | C++ 標準とエラーの返し方 | C++20 + 自前の `Result<T>` / C++23 + `std::expected` | 未検討。Toolset v143 の C++23 対応状況を確認してから決める |
| D-3 | WindowsLibrary の配り方 | A: 静的ライブラリ + ヘッダー / B: DLL のまま、公開ヘッダーを C ABI の薄い C++ ラッパーにする | **A**。C++ の型を DLL の境界で受け渡すと、コンパイラ・CRT・Debug/Release の組み合わせが一致しないと動かない。A ならこの問題が起きない |
| D-4 | 破壊的変更の扱い | 2.0.0 で一度に切り替える / 1.x の間は C ABI も非推奨として残す | 未決 |
| D-5 | C ABI の公開方法 | `.def` だけにする / `__declspec(dllexport)` だけにする | `.def` だけにする。公開する関数が 1 か所で分かる |
| D-6 | C ABI でのデータの受け渡し形式 | 今の JSON 文字列のまま / C の構造体を公開する / 不透明なハンドルと取得関数 | **データの種類ごとに使い分ける**（下の表）。JSON はやめる |
| D-7 | C ABI の文字コード | UTF-16（`wchar_t*`。今の形） / UTF-8（`char*`） / 両方 | **UTF-8 を基本にする**。C# 向けに UTF-16 版を足すかは後で決める |
| D-8 | C ABI の公開ヘッダーで使う型 | Windows の型（`DWORD` / `BOOL` / `UINT` / `BYTE`。今の形） / `<stdint.h>` の固定幅の型 | **`<stdint.h>` の型だけを使い、`<windows.h>` を include しない** |
| D-9 | コールバックの文脈ポインタ | 今のまま / すべてのコールバックに `void* user_data` を付ける | **すべてに付ける** |
| D-10 | エラーの返し方 | 最後の引数 `DWORD* pError`（今の形） / 戻り値でエラーコードを返し、結果は出力引数で返す | **戻り値で返す**（libgit2 と同じ形） |

D-6 〜 D-10 は、全言語から使える汎用の C ABI にするための条件である。どれも段階 5 で `WindowsLibraryCApi` を新しく作るときに最初から決めておけば手間はかからない。後から変えると、すべての利用者にとって破壊的変更になる。

#### D-6: データの種類ごとの受け渡し方

| データ | 方式 | 手本 |
|---|---|---|
| 単純な文字列・バイト列 | 呼び出し側がバッファを用意し、必要なサイズを問い合わせてから取得する（今のまま） | Win32 |
| 一覧・複合データ（履歴、形式の一覧など） | 不透明なハンドルと取得関数、解放関数 | SQLite、libgit2 |
| 入力オプション | サイズ欄（`cbSize`）付きの構造体 | Win32 |

```c
ntk_clipboard_history* h;
ntk_clipboard_get_history(&h, &err);

size_t n = ntk_clipboard_history_count(h);
for (size_t i = 0; i < n; ++i) {
    const char* text = ntk_clipboard_history_item_text(h, i);  // h が生きている間だけ有効
    bool pinned = ntk_clipboard_history_item_is_pinned(h, i);
}
ntk_clipboard_history_free(h);
```

選んだ理由:

- 全言語で使われている C ライブラリ（SQLite、libcurl、libgit2）はどれもハンドル方式で、ほぼ全ての言語にバインディングがある
- 構造体をそのまま公開すると、項目を足しただけで ABI が壊れる。ハンドル方式なら内部に項目を足しても利用者に影響しない
- JSON は使う側が言語ごとにデータの形を定義し直す必要があり、間違いに実行時まで気づけない
- ハンドル方式は関数の数が増えるが、C# は ClangSharp、Rust は bindgen、Python は cffi、Go は cgo でヘッダーからバインディングを自動生成できる

短所: データの項目 1 つにつき取得関数が 1 つ必要になり、公開関数は今の 47 個から大きく増える。

#### D-7 〜 D-10: 今の公開ヘッダーの状態

| ID | 今の状態 |
|---|---|
| D-7 | 文字列はすべて `wchar_t*`（UTF-16）。JSON も `wchar_t*` で渡しているが、JSON は仕様上 UTF-8 でやり取りするものなので、JSON を残す場合でもずれている。libgit2 と libcurl は UTF-8 だけを扱い、SQLite は UTF-8 と UTF-16 の両方の関数を用意している |
| D-8 | `<windows.h>` を include しているのは `WindowsClipboardManager.h` だけ。`WindowsDialogManager.h` と `WindowsNotificationManager.h` は include せずに `DWORD` などを使っているので、先に `<windows.h>` を読み込まないとコンパイルできない。バインディングの自動生成ツールでは `windows.h` 全体を読み込むことになる |
| D-9 | コールバックの型は 6 つあり、文脈ポインタを持つのは `ClipboardRenderCallback` だけ。`ClipboardChangedCallback`、`ClipboardHistoryChangedCallback`、`ClipboardFlagChangedCallback`、`ClipboardRequestCallback`、`NotificationInvokedCallback` には無く、Rust のクロージャや C# のインスタンスメソッドなどをグローバル変数なしで渡せない |
| D-10 | すべての関数が最後の引数 `DWORD* pError` でエラーを返している |

決定済み:

| 決定 | 内容 |
|---|---|
| `WindowsLibrary` は C++ API にする | ネイティブの利用者向け |
| C ABI は `WindowsLibraryCApi` に移す | Unity 専用ではなく汎用の C ABI とする。名前を変える理由は 3.1 |

## 9. DoD

- [ ] D-1 〜 D-10 を決める
- [ ] チケットを割り当てる
- [x] 段階 0a のスパイクで、FlaUI と computer use の分担を確定する（`results/2026-09-19-windows-architecture-stage0a-spike-result.md`）
- [ ] UI テスト、C++ API、C ABI の設計書を、それぞれの段階の前に書く
- [ ] C++ API と C ABI の設計書が、別のモデルのレビューを通っている
- [ ] Clipboard / Notification / Dialog のすべてに UI テストがある
- [ ] 段階 0d で、今のコードで全件通ることを確かめ、結果を記録する
- [ ] 段階 1 〜 6 を終え、段階ごとに 3 つの層（ユニットテスト、UI テスト、computer use）の結果が記録と変わらないことを確認する
- [ ] `WindowsLibrary` に MFC / COM への依存が無い
- [ ] `WindowsLibrary` の公開ヘッダーに C ABI（`extern "C"`）が無い
- [ ] 47 関数すべてを `WindowsLibraryCApi` から公開している
- [ ] `UnityWindowsPlugin` がリポジトリに残っていない（プロジェクト、ソリューション、スクリプト、README、ルール）
- [ ] NuGet パッケージに全機能の公開ヘッダーが入っている
- [ ] `WindowsLibraryExample` が C++ API だけを使っている
- [ ] 段階 7 の CI が develop で動いている

## 10. 関連

- `artifact/topics/migration/README.md` §2・§7（Windows で決めること: C++ 標準、PlatformToolset、`WindowsTargetPlatformVersion`、サポートする OS）
- `agent-rules/coding-rules/windows.md`
- `artifact/topics/bridge-testing/README.md`（ブリッジ層のテストの穴。段階 5 で `WindowsLibraryCApi` のテストを作るときに参照する）
