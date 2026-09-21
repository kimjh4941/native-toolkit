# Windows ライブラリ C++ API 実装設計書（段階 3）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/windows-architecture/README.md` |
| 対象段階 | 段階 3（C++ API を `include/NativeToolkit/` に作り、中身を C++ の形に書き直す） |
| 対象 OS | Windows 11 以降 |
| 作成日 | 2026-09-20（レビュー 2 周を反映した第 3 版） |
| ブランチ | `feature/NTKIT-16` |
| 前段階 | 段階 0a〜0d、1、2 は完了（`results/` に記録） |
| 反映した決定 | D-1（統合）、D-2（C++20 + 自前の `Result`）、D-3（静的ライブラリ + ヘッダー）、D-4（2.0.0 で一括切替） |

> **機械照合（この設計書を更新したら必ず両方を実行する）**
>
> - `python3 scripts/check_design_consistency.py <この設計書>` — 設計書が**自分自身と**矛盾していないか（OP 件数、§8.1 と §9 の対応、タスクの粒度と合計、ID 昇順、表の列数、見出し順）
> - `python3 scripts/check_cpp_api_contract.py` — 設計書が**外側と**矛盾していないか（T-13）。§8.1 の 47 操作を両端から導出（C 名は `.def` の輸出一覧、C++ 名は公開ヘッダー）、エラー列挙と `#define` の 1 対 1、`@retval` と §11.4、§10 が引く行番号と引用先。壊れたときに落ちることは `scripts/tests/test_check_cpp_api_contract.py` が検査する

## 0. レビューの反映

2 者（Claude のサブエージェント、Codex）に 2 周レビューしてもらい、指摘を反映した。結果は `reviews/2026-09-20-windows-architecture-cpp-api-design-review-v1.md` と同 `-v2.md`。

### 0.1 第 2 版での反映（v1 のレビュー）

| # | 指摘 | 反映 |
|---|---|---|
| R-1 | 段階 3 の成果物のままでは C++ API をリンクできない | 成果物を分ける（7.6） |
| R-2 | `Session` の参照カウントは最終破棄のスレッドなどが未定義 | ムーブのみの単独所有に戻す（7.4） |
| R-3 | `Close()` の失敗を `Busy` に潰しており今の返し分けを壊す | 5 通りをそのまま返す（7.4.1、11.4） |
| R-4 | `Result` は `std::expected` に差し替えられない | `Unexpected<E>` を導入し、差し替え可能という主張を取り下げ（7.2） |
| R-5 | 8.2 の型が実装できる粒度でない | 宣言の形で書き下す（8.2） |
| R-6 | 10 章に Dialog の表が無い | 10.3 を追加 |
| R-7 | 9 章の OP-43 / OP-44 などが実装と違う | 修正（9 章） |
| R-8 | 静的ライブラリの依存伝播を段階 5 に送るのは遅い | 7.6 と 7.5.2 で段階 3 の範囲にする |
| R-9 | `CLP-xx` / `NTF-xx` の ID は元の設計書に無い | この設計書の番号であることを明記し、出典を併記（10 章） |

### 0.2 第 3 版での反映（v2 の再レビュー）

| # | 指摘 | 反映 |
|---|---|---|
| S-1 | 分割すると参照されない export が DLL から消える。C ブリッジが実装と同じ翻訳単位にある | **C ブリッジを T-02 で DLL 側の翻訳単位へ移す**。`.def` に 47 + `Common` 5 を列挙し、`dumpbin /exports` の差分ゼロを完了条件にする（7.6、T-02） |
| S-2 | `WindowHandle` のコードがコンパイルできない | `struct HWND__;` を大域に置く（7.1） |
| S-3 | DTO が今の C ABI の入力を表せない（`MB_*`、`scenario`、`timestamp`、音声のプリセット名、ボタンの `args`、相対の有効期限、`OFN_*`、既定フィルター） | 実装のパーサから導出し直す（8.2、10.3）。Win32 のフラグ語と生のフィルター文字列は**ブリッジが内部層を直接呼ぶ逃げ道**を用意する（N-9） |
| S-4 | `Session` のデストラクタの方針が実装できない | **`Close()` の成功を必須**とし、デストラクタは放棄 + デバッグ時 assert に一本化する。非同期に片付くという約束を取り下げる（7.4.1、N-5） |
| S-5 | 通知の 2 回目の init は今コールバックを差し替えている | `Manager::SetInvokedHandler` を足す（8.2、N-10） |
| S-6 | 通知の COM は MTA。`S_FALSE` も解除が要る。解除を足すと C ABI の動作が変わる | mode と許容を明記し、**段階 3 では現状維持**にする（7.4.2、N-8） |
| S-7 | `Runtime` の後始末を段階 5 に送る境界が誤り。`initWinAppSdk` は unpackaged 専用 | **`Runtime` トークンを段階 3 で導入**する（N-7）。packaged では不要であることを 7.5.4 に書く |
| S-8 | T-03 をブロッキングのスパイクにすべき | 格上げする（T-03）。結果が出るまで 7.5 の配布構成は暫定とする |
| S-9 | `Result` の特殊メンバが未定義でムーブのみの型を入れられない | 条件付きの特殊メンバ、`error() &&`、無検査アクセサの `noexcept`、`<new>` の許可（7.1、7.2） |
| S-10 | 公開の集約型が不定・矛盾した状態を許す | `FormatPayload` を `std::variant` にし、全スカラーに既定値を置く（8.2） |
| S-11 | 11.4 が実装から導出されていない箇所が残る | `OP-21` の `Unknown`、`OP-08` の `HResultFailure`、通知の意味検証が `InvalidParameter` であることを反映（11.4） |
| S-12 | 10 章の引用 2 件が誤り。引用を検査する仕組みが無い | 修正し、引用行の照合を機械照合に足す（T-13） |
| S-13 | `SessionOptions::foregroundWindow` は誰も読まない | 削除（8.2） |
| S-14 | T-02 がテストプロジェクトの対象を変える。サンプルの `ProjectReference` の付け替えが未記載 | T-02 / T-03 の完了条件に追加 |

## 1. 設計目的

- `WindowsLibrary` の公開 API を C ABI から C++ API へ置き換える。C ABI は段階 5 まで残るため、この段階では **C++ API を足し、C ABI をその上に載せ替える**
- 既存の 47 個の C ABI 関数それぞれについて、C++ API での置き換え先を決める
- 既存の約束（コールバックの回数・スレッド、所有権、状態機械、エラー）が、新しい C++ API のどこで守られるかを対応表で示す
- 段階 4（サンプルの移行）が、この設計書だけで書き換えられる粒度にする
- 公開する型は、**`designs/2026-09-20-windows-architecture-c-abi-input-inventory.md`（今の C ABI が受け付ける入力の一覧）から導出する**。サンプルが使っていない入力を落とさないため

## 2. スコープ

### 2.1 In scope

- 公開ヘッダー `windows/WindowsLibrary/include/NativeToolkit/` の構成と全シグネチャ、公開する型の宣言
- `Result<T, E>`、`Unexpected<E>`、`Failure<Code>` と機能ごとのエラー列挙
- Clipboard / Notification / Dialog の 3 機能の C++ API
- 既存の内部クラスを C++ API の下にどう置き直すか。段階 2 で機能の直下に残した層が混ざったファイルの分割
- **成果物の分割**（静的な C++ コアと DLL ブリッジ）と、それに伴うビルドの配管
- 利用者の前提（ビルド、リンク、実行、呼び出し方）
- 単体テスト（`WindowsLibraryTest`）の追加・変更方針

### 2.2 Out of scope

- C ABI の新しい形（D-6〜D-10）。段階 5 の設計書で決める
- `WindowsLibraryCApi` への改名と `UnityWindowsPlugin` の削除（段階 5）
- サンプルアプリの書き換え（段階 4）。この設計書は移行先の API を決めるだけ
- NuGet の配布物の最終形、マニュアル、Doxygen の生成（段階 6）、CI（段階 7）
- `Common/common.h` の 5 関数（`DLog` / `DFLog` / `DFLLog` / `ToWString` / `ConcatWStrings`）の公開をやめる判断。段階 3 では `.def` に載せて今どおり公開し続ける（7.6.1）。やめるかは段階 5 の C ABI 設計書で決める。**`ToWString` が `extern "C"` の境界で `std::wstring` を値返ししていること、`ConcatWStrings` が呼び出し側に `delete[]` を求めていることを、そこへの申し送りとして記録する**
- `docs/` 配下

## 3. 企画書由来の前提と不足前提

### 3.1 企画書（README）由来の前提

| 前提 | 出典 |
|---|---|
| 目標の構成は `include/NativeToolkit/` に `Clipboard.h` / `Notification.h` / `Dialog.h` / `Error.h` / `Types.h` | README 3 |
| `WindowsLibraryCApi` → `WindowsLibrary` の依存方向。機能の実装は `WindowsLibrary` にだけ置く | README 3 |
| C++ API の方針（`Result`、`enum class`、`std::wstring`、構造体、`std::function`、RAII） | README 4 |
| 段階 3 の時点では C ABI も残す | README 5 |
| C++ API の設計書に「既存の約束の対応表」を含める | README 5.1 |
| 検証は 3 層（ユニットテスト、UI テスト、computer use）で、段階 0d の記録と変わらないこと | README 7 |

### 3.2 不足前提

| ID | 不足している前提 | この設計書での扱い |
|---|---|---|
| G-1 | Dialog には機能の設計書が無く、約束がコードにしか無い | コードから読み取って 10.3 に書き起こす |
| G-2 | `Result` の具体的な形（`std::expected` との差、例外の扱い） | 7.2 で決める |
| G-3 | 静的ライブラリにしたときの WinRT / Windows App SDK の依存の伝播 | **7.6 で決める**（段階 5 に送らない）。実測での確認は T-03 の完了条件 |
| G-4 | C++ API の名前空間と最小 Windows SDK / ツールセット（D-1 で段階 3 送り） | 7.1、7.5 で決める |
| G-5 | Windows App SDK のブートストラップの後始末（`MddBootstrapShutdown`）が今のコードに無い | 10.4 の N-7 で決める |

## 4. 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用可否 | この設計での扱い |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | 段階 2 で `src/<Feature>/{Application,Data,Domain}` に分けた。C++ API は Manager 層の公開面として `include/NativeToolkit/` に置く |
| 層とモジュールの対応（Manager 層まではネイティブライブラリ） | 適合 | Manager 層までは C++ コア。DLL ブリッジ（7.6）は Bridge 層だけを持つ |
| Port はドメイン型のみ | 適合 | Port は抽象基底クラス。WinRT 型を Port の引数・戻り値に出さない |
| Manager は UseCase 経由で Data へ | 部分適合 | `windows.md` の段階適用のトリガーに従い、非自明なロジックを持つ操作にだけ UseCase を作る。素通しの操作は Manager から Repository を呼ぶ。差は 4 章末に記す |
| Manager の公開 API 方式（同期性 × スレッドアフィニティ） | 適合 | 9 章の対応表で全公開操作について決める |
| システム Delegate / コールバックの所有は Manager の 1 クラス | 適合 | 既存の所有関係を変えない。C++ API は所有クラスへ委譲する |
| ネイティブ版はエラーを型付きのまま伝播 | 適合 | `Result<T, E>` で機能ごとの `Failure<Code>` を返す。番号にも文字列にも潰さない |
| サンプルアプリはネイティブライブラリのみに依存 | 適合 | 段階 4 でサンプルを C++ API に移す |
| テスト（TDD）、検査の書き方 | 適合 | 12 章。実装の集合を主題にする検査は両辺をソースから導出する |
| 最小 OS バージョン Windows 11 以降 | 適合 | 7.5 |

common.md との差は次の 1 点で、`windows.md` の既定（Manager + フラット構造、層は痛みが出た箇所にだけ足す）に従ったものである。

- 素通しの操作に UseCase を作らない（common.md「Manager は必ず UseCase 経由」の例外）。理由は、47 操作の多くが Win32 API の 1 対 1 の呼び出しで、UseCase を作ると検証対象のないクラスが 40 個以上増えるため

## 5. 個別実装方針の適用チェック（windows.md 準拠）

`windows.md` は今の C ABI（`extern "C"` + JSON + `DWORD* pError`）を前提に書かれている。段階 3 では C ABI が DLL ブリッジとして残るため、C ABI についての記述は段階 5 まで正しいままである。したがって **`windows.md` はこの段階では変更しない**。変更案は 5.2 に書き、段階 5 の C ABI 設計書と同じ PR で反映する。

### 5.1 そのまま適用する節

| 節 | 適用 |
|---|---|
| ログ（DLog / DFLog / DFLLog） | 適用する。C++ API の公開メソッドも先頭 1 行目に全パラメータのログを入れる |
| コメント（Doxygen） | 適用する。公開ヘッダーは `@brief` / `@param` / `@return` / `@retval` を必須にする |
| コメントと言語ポリシー（英語） | 適用する |
| 同期 / 非同期の方針（システム API に準拠、STA で `get()` を呼ばない、`wait_for` を使う、アパートメントの扱い） | 適用する。9 章の根拠になる |
| 実装の落とし穴（文字コード、WinRT と STA、通知の登録、進捗のデータバインド、ビルド ≠ 表示確認） | 適用する |
| UI 自動テスト | 適用する。段階 0 で作ったテストをそのまま回帰に使う |

### 5.2 C++ API と食い違うため、段階 5 で直す節

| 節 | 今の記述 | 段階 5 での変更案 |
|---|---|---|
| アーキテクチャ / Bridge の配置 | 「`extern "C"` C Bridge は `WindowsLibrary` に実装し、`WindowsLibrary.dll` からエクスポートする」「中継用の別 DLL やラッパープロジェクトを追加しない」 | C Bridge は `WindowsLibraryCApi` に置く。機能の実装は静的な C++ コアに置く（D-3、7.6） |
| アーキテクチャ / 基本構造 | 「`XxxManager (singleton)` ← 公開 API・システム Delegate 所有・ロジック集約」 | **公開面からは singleton を外す**。実体がプロセスに 1 個である点は変わらないが、取得は静的アクセサではなくオブジェクトの所有にする（7.4.4）。内部の singleton は残る |
| 原則 | 「C Bridge は薄く保つ（複雑なデータは JSON 文字列で渡す）」 | JSON をやめる（D-6）。薄く保つ原則は残す |
| 文字列・API 取り扱い方針 | 「公開 API は `extern "C"` + `__declspec(dllexport/dllimport)` で公開する」 | C++ API は名前空間付きの通常の C++ 宣言。C ABI の公開方法は `.def` だけにする（D-5） |
| 文字列・API 取り扱い方針 | 「エラー情報は `DWORD* pError` など out 引数で返す」 | C++ API は `Result`（D-2）。C ABI は戻り値でエラーコードを返す（D-10） |
| 文字列・API 取り扱い方針 | 「文字列は `wchar_t*` / `std::wstring` を優先」 | C++ API は `std::wstring` を維持。C ABI は UTF-8（D-7） |
| Bridge の配置 | 「`windows/UnityWindowsPlugin` は…そのまま残す」 | `UnityWindowsPlugin` は削除する（README 5 の段階 5） |

## 6. 既存実装差分サマリー（段階 2 完了時点の実測）

### 6.1 今の公開面

| 区分 | 数 | 形 |
|---|---|---|
| Dialog の公開関数 | 6 | 呼び出し側バッファ。戻り値は件数または `BOOL`。エラーは OS の生の値。キャンセルは `*pError = -1` |
| Notification の公開関数 | 14 | 入力は JSON 文字列。`getAllNotifications` は JSON をバッファへ返すが、必要サイズを返さない |
| Clipboard の公開関数 | 27 | バッファ（必要サイズを戻り値で返す）、JSON、コールバック |
| `Common/common.h` | 5 | 2.2 の申し送りの対象 |
| 合計 | 52 | うち機能の 47 関数がこの設計書の対象 |

- `.def` に載っているのは 39 個だけで、Dialog の 6 個、`Common` の 5 個、`initWinAppSdk`、`openNotificationSettings` の計 13 個は `__declspec(dllexport)` のみ（D-5 の前提を実測で確認）
- コールバックの型は 6 種。文脈ポインタを持つのは `ClipboardRenderCallback` だけ（D-9 の前提を実測で確認）
- `ClipboardFlagChangedCallback` は 2 つの事象で**型を共用している**が、登録は 3 口（`onHistoryChanged` / `onHistoryEnabledChanged` / `onRoamingEnabledChanged`）に分かれており、受け手はどちらが起きたか分かる

### 6.2 機能ごとの内部構成の偏り

| 機能 | 層 | 実装の状態 |
|---|---|---|
| Clipboard | `Application` / `Data` / `Domain` が揃っている | `ClipboardManager` を中心に、ライフサイクル、履歴の調整役、Win32 コア、遅延レンダリング、監視、隠しウィンドウ、WinRT 背面に分かれている。Bridge は `SafeBridgeCall` で例外を捕捉する |
| Notification | `Application`（ポートと DTO）と `Data`（背面 2 種）はあるが `Domain` が無い | `WindowsNotificationManager` に JSON 解析・検証・組み立て・エラー変換・コールバック中継が集まっている。Bridge に例外の捕捉が無い |
| Dialog | 層分けが無い | `src/Dialog/` は `.h` と `.cpp` の 2 ファイルのみ。実装クラスは `.cpp` 内で宣言された singleton。エラーコードの空間も例外の捕捉も無い |

### 6.3 C++ 標準とツールセット（実測）

| プロジェクト | LanguageStandard | ツールセット | 種別 |
|---|---|---|---|
| `WindowsLibrary` | `stdcpp20`（4 構成すべて、`/EHsc`） | v143 | DynamicLibrary。Release 2 構成に `WholeProgramOptimization`（`/GL`）が有効 |
| `WindowsLibraryTest` | `stdcpp20`（2 構成） | v143 | DynamicLibrary |
| `WindowsLibraryExample` | **未設定（MSVC 既定の C++14）** | v143 | Application。include は `..\WindowsLibrary\src` のみ |
| `UnityWindowsPlugin` | 未設定。`UseOfMfc: Static` が残る | v143 | `.sln` から外れており、公開 API を 1 つもエクスポートしていない |

**段階 3 の着手時に `WindowsLibraryExample` を `stdcpp20` にする**（T-01）。C++20 の公開ヘッダーを C++14 のサンプルから include できないため、段階 4 まで先送りすると段階 3 の完了をサンプルで確かめられない。

### 6.4 サンプルの呼び出し箇所（段階 4 の規模の目安）

| 機能 | ファイル | 呼び出し箇所 | 置き換えの重い点 |
|---|---|---|---|
| Dialog | `DialogPage.xaml.cpp`（197 行） | 6 | 固定長のスタックバッファ |
| Notification | `NotificationPage.xaml.cpp`（423 行） | 約 23 | thunk と `TryEnqueue` による UI スレッドへの引き戻し |
| Clipboard | `ClipboardPage.xaml.cpp`（1,938 行） | 約 51 | 6 個の静的 thunk、ファイル有効域の `DispatcherQueue`、2 回呼びのサイズ問い合わせ、JSON の組み立てと解析、`uninitClipboardManager` の再試行ループ 4 か所 |

### 6.5 既存のテスト（段階 0d の記録）

`scripts/test_windows.baseline.json` の記録は **ユニットテスト 106 件**（Clipboard 85 = Core 13 + DeferredProvider 3 + Formats 39 + HistoryCoordinator 30、Notification 21）、**UI テスト 94 件**。README 7.1 の「Clipboard 88 件」は段階 0 以前の数であり、回帰の基準は baseline のほうである。

### 6.6 破壊的変更

- 公開 API の破壊的変更は無い。C ABI の 52 関数とその動作はそのまま残る（`dumpbin /exports` の差分 0 件を完了条件にする）
- 公開の方法は変わる。`__declspec(dllexport)` に頼っていた 13 個を `.def` に移す（7.6.1）。export される名前の集合は変わらない
- ただし **配布物の構成は変わる**（7.6）。`WindowsLibrary` を静的な C++ コアと DLL ブリッジに分けるため、`WindowsLibrary.vcxproj` の種別、`.def`、ビルドスクリプトの対象が変わる。DLL から出る C ABI の 47 関数とその動作は変えない
- 利用者から見た破壊的変更は段階 5（C ABI の置き換え、2.0.0）で起きる（D-4）

## 7. 実装アーキテクチャ

### 7.1 公開ヘッダーの構成

```
windows/WindowsLibrary/
  include/NativeToolkit/
    Types.h          # WindowHandle、WriteOptions、RequestId などの共通の値型
    Error.h          # Failure<Code>、Unexpected<E>、Result<T, E>、機能ごとの enum class
    Dialog.h         # namespace NativeToolkit::Dialog
    Notification.h   # namespace NativeToolkit::Notification
    Clipboard.h      # namespace NativeToolkit::Clipboard
  src/               # 段階 2 の構成のまま
```

- 名前空間は `NativeToolkit::<Feature>`（G-4）
- **各ヘッダーは自分が使う名前の標準ヘッダーをすべて自分で include する。** 使うのは `<cstdint>` / `<cstddef>` / `<string>` / `<string_view>` / `<vector>` / `<span>` / `<optional>` / `<variant>` / `<functional>` / `<chrono>` / `<utility>` / `<type_traits>` / `<new>` に限る（`<new>` は `Result` の活性メンバの構築に要る）。WinRT と MFC の型は出さない
- **`<windows.h>` は include しない。** ウィンドウハンドルは `Types.h` で次のように定義する。`struct HWND__;` は `<windows.h>` と同じく**大域名前空間**に置く（名前空間の中に置くと別の型になり、`::HWND__` が未宣言になる）

```cpp
struct HWND__;                                   // <windows.h> と同一の宣言。重複しても害は無い

namespace NativeToolkit {
using WindowHandle = ::HWND__*;                  // HWND と同じ表現
}
```

- **公開ヘッダーは ASCII だけで書く。** 非 ASCII を入れると、`/utf-8` を付けない利用者の翻訳単位が CP932 として解釈されて壊れる（`warning C4819`）。実測で確認した（`results/2026-09-20-windows-architecture-stage3-header-spike-result.md`）
- 公開宣言では `HWND` ではなく `WindowHandle` だけを使う。`HWND` との相互運用は **`STRICT`（MSVC の既定）が前提**であることを Doxygen に書く。`NO_STRICT` では `HWND` が汎用ハンドル型になり暗黙変換が成立しない
- ツールセットは v143、Windows SDK は `10.0`、サンプルの `WindowsTargetPlatformMinVersion 10.0.17763.0` は維持する。対応 OS は Windows 11 以降

### 7.2 `Result<T, E>` とエラー（G-2）

```cpp
namespace NativeToolkit {

template <class Code>
struct Failure {
    Code     code{};
    uint32_t systemCode = 0;  // GetLastError / HRESULT / CommDlgExtendedError。無ければ 0
};

template <class E>
struct Unexpected {           // std::unexpected と同じ役割。エラー側の構築を明示する
    E error;
};
template <class E> Unexpected(E) -> Unexpected<E>;

template <class T, class E>
class Result {
public:
    Result(T value);
    Result(Unexpected<E> error);

    // 特殊メンバは T と E の性質から条件付きで有効にする。
    // T がムーブのみ（Session / Manager）ならコピーは delete される。
    Result(const Result&)            = /* T と E がコピー可能なときだけ */;
    Result(Result&&)                 = /* T と E がムーブ可能なときだけ */;
    Result& operator=(const Result&) = /* 同上 */;
    Result& operator=(Result&&)      = /* 同上 */;
    ~Result();                       // 活性メンバだけを破棄。T と E が自明に破棄可能なら自明

    bool      has_value() const noexcept;
    explicit  operator bool() const noexcept;

    T&        value() & noexcept;          // 事前条件: has_value() == true。違反は未定義（投げない）
    const T&  value() const& noexcept;
    T&&       value() && noexcept;
    T         value_or(T fallback) const&; // T がコピー可能なときだけ有効

    E&        error() & noexcept;          // 事前条件: has_value() == false
    const E&  error() const& noexcept;
    E&&       error() && noexcept;
};

template <class E>
class Result<void, E> {                    // 値を返さない操作用
public:
    Result() noexcept;                     // 成功
    Result(Unexpected<E> error);

    bool      has_value() const noexcept;
    explicit  operator bool() const noexcept;
    const E&  error() const& noexcept;
    E&&       error() && noexcept;
};

}

// 各機能のヘッダーは、自分のエラー型を束ねた別名を置く
namespace NativeToolkit::Clipboard {
    using Error = Failure<ClipboardError>;
    template <class T = void> using Result = NativeToolkit::Result<T, Error>;
}
```

- **エラーの型を消さない。** `Clipboard::Result<T>` と `Dialog::Result<T>` は別の型で、`error()` はその機能の `Failure<Code>` を返す
- 8 章のシグネチャに書く `Result<...>` は、すべてその機能の名前空間の別名を指す。`Result<>` は `Result<void>` と同じ
- 実装の要件
  - コピー系の特殊メンバは `T` と `E` がともにコピー可能なときだけ有効にする。**`Result<Session>` と `Result<Manager>` はムーブのみになる**。実装には **`requires` 節による制約が要る**（T-04 で実測）。コピーを削除した基底クラスを継承するだけでは、派生側がコピーコンストラクタを宣言している限り `std::is_copy_constructible_v` は `true` を返し、標準ライブラリが型特性を見て誤った経路を選ぶ
  - `value_or` は `T` がコピー可能なときだけ有効にする
  - 破棄は活性メンバのみ。`T` と `E` がともに自明に破棄可能なら `Result` も自明に破棄可能にする
  - 代入で活性メンバが入れ替わるとき、旧メンバを破棄してから新メンバを構築する。構築が例外を投げた場合は `Unexpected<E>`（`E` は `nothrow` で構築できる `Failure<Code>`）へ退避し、**値を持たない有効な状態**にする。`valueless` を公開しない
  - 無検査のアクセサ（`value()` / `error()`）は `noexcept`。事前条件の違反はデバッグビルドで assert する
  - `T == E` でも曖昧にならない（エラー側は `Unexpected` を必須にすることで区別する）

**実装方式**: `std::variant<T, E>` を添字で保持する形で骨組みを作り、MSVC v143 / C++20 で上の要件（別名が別の型、`Result<Session>` がムーブのみ、`Result<int>` が自明に破棄可能、`T == E` が曖昧でない）が満たせることを確認した。ただし `std::variant` は `valueless_by_exception` を持ちうるため、「値を持たない不正状態を公開しない」を厳密に満たすには自前の union にするか、`valueless` を内部で `Failure` に写す必要がある。どちらを採るかは T-04 で決める。

**`std::expected` との関係**: **差し替えは機械的には済まない**。違いを次に示す。段階 3 では自前の `Result` を使い、C++23 へ移す判断は別の作業として扱う。

| 項目 | 自前の `Result<T, E>` | `std::expected<T, E>` |
|---|---|---|
| エラーの構築 | `Unexpected<E>{...}` | `std::unexpected<E>{...}` |
| `value()` の失敗時 | 事前条件違反（投げない） | `bad_expected_access` を投げる |
| 値を持たない不正状態 | 持たない（上の退避規則） | `valueless_by_exception` に相当する状態がある |
| `and_then` / `transform` | 持たない | 持つ |

**例外の約束**: 「公開 API は例外を投げない」は成立しないので、次の形に狭める。

- **本体に入ってからの失敗（OS / WinRT の失敗、内部の確保失敗）は必ず `Failure` で返す。例外にしない**
- 引数の構築（`std::function` への変換、コンテナのコピー）は呼び出し側の式であり、そこで `std::bad_alloc` が出ることはある。これは通常の C++ の振る舞いとして文書化する
- 保存したコールバックの呼び出しは、**呼び出し境界で必ず捕捉する**（Clipboard は既にそうなっている。Notification は捕捉が無いので T-08 で足す）
- デストラクタはすべて `noexcept`。確保を伴うメソッドに `noexcept` を付けない

### 7.3 層の置き直し

| 機能 | 段階 3 で行うこと |
|---|---|
| Clipboard | 層はそのまま。`ClipboardManager` の公開面を `NativeToolkit::Clipboard::Session` に置き換える。JSON の組み立てと解析は C++ API から外し、DLL ブリッジ側に残す |
| Notification | `Domain` を作り、`WindowsNotificationManager` の検証・組み立てのうち WinRT に依存しない部分を移す。JSON 入力は C++ API から外し、構造体 `NotificationContent` を入力にする |
| Dialog | `src/Dialog/{Application,Data,Domain}` を作る。`.cpp` 内の singleton を `Data` の実装クラスへ出し、`Domain` に `DialogError` と結果の型を置く |

- UseCase を作るのは Clipboard の履歴（`ClipboardHistoryCoordinator` が既に状態機械を持つ）と Notification の検証・組み立てに限る
- system コールバックの所有は今のまま（`ClipboardManager`、`WindowsNotificationManager`）。C++ API は所有クラスへ委譲するだけにする

### 7.4 所有権とライフサイクル

#### 7.4.1 `Clipboard::Session`

- **ムーブのみ・単独所有**。コピーは禁止。`Session::Create(const SessionOptions&)` は `Result<Session>` を返す
- 2 個目の `Create` は、**同じスレッドからなら `ClipboardError::NotSupported`、別スレッドからなら `WrongThread`**。今の C ABI の冪等な init は、DLL ブリッジが `Session` を 1 個だけ保持することで再現する
- **終了は `Close()` を成功させることを必須とする**（S-4）。`Result<void> Session::Close()` は今の `uninitClipboardManager` と同じ意味を持つ

| `Close()` の結果 | 今の `uninit` |
|---|---|
| 成功（閉じ終わった。既に閉じている場合も成功） | `TRUE` + `CLIPBOARD_ERROR_NONE` |
| `WrongThread` | 非オーナースレッドからの呼び出し |
| `MonitorRegisterFailed` | 監視または履歴のトークンを解除できていない |
| `Canceled` | ドレインが終わっていない |
| `Busy` | lifecycle または coordinator が破棄可能でない |
| `PartialState` ほか | 部分状態からの回復に失敗 |

- **`Close()` は冪等**で、閉じ終わった後の呼び出しは成功を返す。今の再試行ループ（`while (!done)`）がそのまま書ける
- データ系の API は、閉じた後は `NotInitialized` を返す
- **デストラクタは「放棄」であり、後始末を約束しない**（N-5）。`Close()` が成功していない `Session` が破棄された場合、次のように振る舞う
  - デバッグビルドでは assert し、リリースビルドでは `DFLog` に残す
  - 内部状態（配送用ウィンドウ、リスナー、pending）は**そのまま残る**。プロセスが終わるまで解放されない
  - この状態では新しい `Session::Create` は `NotSupported`（同スレッド）を返し続ける。**回復する手段は無い**
  - 予約済みの遅延フォーマットは失われる（`WM_RENDERALLFORMATS` が配送されないため）
- 「メッセージポンプが今後回るか」を判定する確実な Win32 の手段は無く、`PostMessage` の成功も実行を保証しないため、**デストラクタが非同期に片付ける設計は採らない**。v2 の自己破棄の記述は撤回した
- **コールバックの中で `Session` を破棄してはならない。** 捕捉も禁止（循環になる）。Doxygen と 7.5.4 に明記する

#### 7.4.2 `Notification::Manager` と `Runtime`

- **`Manager` はムーブのみ・単独所有**。2 個目の `Create` は `NotificationError::NotSupported`
- 今の実装は 2 回目の `init` でも**コールバックを差し替える**（早期 return の前に代入している）。これを保つため、`Manager::SetInvokedHandler` を公開する（N-10）。DLL ブリッジはこれを使って今の動作を再現する
- **COM は段階 3 では現状維持**（N-8）。今の実装は `CoInitializeEx(nullptr, COINIT_MULTITHREADED)` を呼び、`RPC_E_CHANGED_MODE` を許容し、それ以外の失敗を `HResultFailure` にする。`CoUninitialize` は呼んでいない
  - 対になる解除を足すと `uninitNotificationManager` が**呼び出し側のスレッドの COM を落とす**ことになり、「動作を変えない」に反するため、段階 3 では足さない
  - Doxygen に次を明記する。(a) ライブラリは MTA で初期化を試みる、(b) 解除しない、(c) **MTA で初期化されたスレッドから `Session::Create` を呼ぶと `WrongApartment` になる**ため、Clipboard と同じスレッドで使う場合は利用者が先に STA で初期化する
  - `S_FALSE` も成功であること、釣り合いを取るなら同じスレッドでしか解除できないことは、段階 5 の C ABI 設計書への申し送りにする
- **Windows App SDK のブートストラップは `Runtime` トークンにする**（N-7、S-7）

```cpp
namespace NativeToolkit::Notification {
class Runtime {                                   // ムーブのみ。破棄で MddBootstrapShutdown
public:
    static Result<Runtime> Initialize(RuntimeVersion);   // 今の initWinAppSdk 相当
    Runtime(Runtime&&) noexcept;
    Runtime& operator=(Runtime&&) noexcept;
    ~Runtime();                                   // noexcept
};
}
```

- `Runtime` が要るのは **unpackaged のときだけ**。packaged のプロセスでは呼ばない（今の C ABI のヘッダーも unpackaged 用と書いている）。7.5.4 に利用者向けの条件として書く
- DLL ブリッジはプロセスに 1 つの `Runtime` を保持し、`initWinAppSdk` の今の振る舞い（後始末しない）を維持する。後始末が増えるのは C++ API の利用者だけで、C ABI の動作は変わらない

#### 7.4.3 値と参照の受け渡し

- 文字列とバイト列は `std::wstring` / `std::vector<std::byte>` を値で返す。呼び出し側のバッファと必要サイズの 2 回呼びは C++ API から無くす
- **`std::wstring_view` は NUL 終端を保証しない。** 実装は Win32 / WinRT の NUL 終端 API に渡す前に必ずコピーし、埋め込み NUL を `InvalidParameter` として弾く
- **`std::span` と `std::wstring_view` は呼び出しの間だけ有効**とし、実装は保持しない。例外は `ReserveDeferred` で、形式名と provider は**深いコピーを取って保持する**
- 遅延レンダリングの provider は `RenderProvider`（8.2）にする。2 相の呼び出しは**内部の `DeferredClipboard` には残し**、C++ API の表面だけ 1 回にまとめる（N-2）
- コールバックはすべて `std::function` にする。公開 API に `void* context` を出さない

#### 7.4.4 なぜ静的アクセサを公開しないか

「プロセスに 1 個」であることと、「どう取得するか」は別の話である。混同しやすいので分けて記す。

| 事柄 | 由来 |
|---|---|
| `Session` と `Manager` がプロセスに 1 個しか作れない | **Windows 側の制約**。Clipboard はオーナー UI スレッドと配送用ウィンドウがプロセスに 1 組、Notification は `CoRegisterClassObject` と `AppNotificationManager::Register` がプロセス 1 回きり |
| 静的アクセサ（`GetInstance()` / `Default()`）を公開せず、オブジェクトを渡す | **この設計の判断**。Windows の制約ではない |

インスタンスを渡す形にした理由は次の 3 つ。

- `Close()` の成功を必須にできる（N-5）。静的アクセサでは「誰も閉じない」経路を型で塞げない
- 内部の singleton をテストで差し替えても、公開面がプロセス全体の状態に依存しない
- 閉じた後・ムーブした後の呼び出しを `NotInitialized` として扱える

**流儀との関係**: WinRT 自身は `AppNotificationManager::Default()` のような静的アクセサを多用するため、その流儀に寄せる案もありうる。採らないのは、WinRT のそれらは OS が寿命を持つのに対し、ここでは利用者に `Close()` を守らせる必要があるためである。`agent-rules/coding-rules/windows.md` の「`XxxManager (singleton)`」とも食い違うので、段階 5 でルールを直す（5.2）。

利用者がアプリ内の離れた場所から使いたい場合は、**利用者のアプリ側でオブジェクトを保持する**（`App` のメンバに持つなど）。ライブラリはその方法を強制しない。

### 7.5 利用者の前提

段階 6 のマニュアルはこの節を元に書く。配布構成は **T-03 のスパイクで確定した**（`results/2026-09-20-windows-architecture-stage3-link-spike-result.md`）。

#### 7.5.1 ビルド

| 前提 | 理由 |
|---|---|
| MSVC v143、`/std:c++20` | 公開ヘッダーが `std::span` などを使う。**C++17 のままの利用者は、段階 5 までは今の `WindowsLibrary.dll` の C ABI を使う** |
| `/EHsc` | ライブラリが `/EHsc` でビルドされている |
| 構成（Debug / Release）と CRT（`/MD` / `/MT`）がライブラリと一致していること | 静的ライブラリに C++ の型が出入りするため |
| C++/WinRT のマクロ設定がライブラリと一致していること | 1 つの EXE / DLL を構成する全ファイルで一致している必要がある（公式の要件）。`.props` で揃える |
| x64 | 配るのは x64 のみ。ARM64 は段階 5 で判断する。**パッケージに ARM64 対応と書かない** |
| リンカーがライブラリのビルドに使った MSVC 以上であること | 新しい v143 でビルドした `.obj` は古い v143 のリンカーで扱えないことがある。配布物に最小のビルド番号を明記する |

**配る静的ライブラリ**: x64 の Debug / Release × `/MD` / `/MT` の **4 種で確定**。`/MT` は Windows App SDK と C++/WinRT を含めてコンパイル・リンク・実行まで確認済み（T-03）。`/MT` を配らないと `/MT` の利用者はリンクできない。

**`/GL` を使わない**: 配る `.lib` では `WholeProgramOptimization` を無効にする（D-3）。今の Release 2 構成では有効なので外す（T-03）。

**不一致の検出**: MSVC は `RuntimeLibrary` と `_ITERATOR_DEBUG_LEVEL` の食い違いを `.obj` に記録し、`LNK2038` で止める。**全ての ABI 差を捕まえるものではない**（C++/WinRT のマクロ、構造体のパッキング、ヘッダーとライブラリの版など）。ヘッダーの版と主要な設定について `#pragma detect_mismatch` を自前で仕込む（T-03）。

- DLL 境界で C++ の型を渡すと、別ヒープでの解放やイテレータのデバッグ水準の違いが**実行時に**壊れる
- 静的ライブラリでは、記録された項目については**リンク時のエラー**になる。問題が消えるのではなく、検出が早くなる

#### 7.5.2 リンクと配布

- 静的ライブラリは MSBuild の設定を伝播しない。今 `WindowsLibrary` が NuGet の `.props` / `.targets` から受け取っている C++/WinRT と Windows App SDK の設定は、**利用者側に同じものを用意する必要がある**
- そのため、**配布物に `.props` / `.targets` の層を付ける**。骨組みは `windows/WindowsLibrary/build/` に作成済み（T-03）。サンプルでの検証は段階 4 でサンプルを Core にリンクするときに行う
- 伝播が必要なものは T-03 で実測した。次のとおり

| 種別 | 内容 |
|---|---|
| import / system ライブラリ | `user32.lib`、`advapi32.lib`、`shell32.lib`、`shlwapi.lib`、`ole32.lib`、`oleaut32.lib`、`propsys.lib`、`windowsapp.lib` |
| Windows App SDK の `.lib` | `packages\Microsoft.WindowsAppSDK.<版>\lib\**win10-x64**\Microsoft.WindowsAppRuntime.Bootstrap.lib`（`MddBootstrapInitialize` を解決する。NuGet の中にしか無い） |
| 実行時の資産 | `Microsoft.WindowsAppRuntime.Bootstrap.dll`（unpackaged で通知を使う場合） |
| マクロ | C++/WinRT のマクロ設定（`WINRT_*`）。助言ではなく一致が要件 |

- `/await` は伝播しない。コルーチンを含むコードはライブラリ側でコンパイル済みで、`/std:c++20` で標準のコルーチンが有効になる

#### 7.5.3 実行

| 前提 | 対象 |
|---|---|
| Windows 11 以降 | 全機能 |
| Windows App Runtime が導入済み | Notification |
| MSIX パッケージ済み | Notification の `RemoveById` / `GetAll` / `SetBadge`（未パッケージではいずれも `NotSupported`） |
| 自プロセスが前面にあること | Clipboard の履歴（`NotForeground` はコールバックで返る） |

#### 7.5.4 呼び出し方

| 前提 | 対象 |
|---|---|
| **unpackaged のときだけ** `Runtime::Initialize` を `Manager::Create` より前に行う。packaged では不要 | Notification |
| ライブラリは COM を MTA で初期化しようとし、解除しない。**Clipboard と同じスレッドで使うなら、利用者が先に STA で初期化する** | Notification / Clipboard |
| `Session::Create` を STA かつメッセージを回しているスレッドから呼ぶ。そのスレッドがオーナーになる | Clipboard |
| **メッセージループを抜ける前に `Close()` が成功するまで呼ぶ。** 成功しないまま破棄すると資源は解放されず、再作成もできない | Clipboard |
| コールバックの中から `Close` / `SetHistoryHandlers` を呼ばない。**`Session` を破棄も捕捉もしない** | Clipboard |
| 遅延レンダリングの provider の中でクリップボード API を呼ばない。ブロックしない | Clipboard |
| 引数に渡した `span` / `wstring_view` は呼び出しの間だけ有効であればよい | Clipboard |
| ダイアログは呼び出しスレッドを塞ぐ（モーダル）。UI スレッドから呼ぶ前提 | Dialog |
| フォルダのダイアログはライブラリが `CoInitializeEx(COINIT_APARTMENTTHREADED)` を呼ぶ。別のアパートメントで初期化済みでも続行する | Dialog |
| 通知のコールバックは OS が選んだスレッドで来る。ただし cold start の 1 回だけは `Manager::Create` の中から呼び出しスレッドで来る | Notification |
| 完了のコールバックはオーナー UI スレッドで来る | Clipboard |
| **`using namespace NativeToolkit::Clipboard;` のような取り込みをしない。** `Session` / `Manager` / `Runtime` は機能ごとの名前空間で文脈を与えた一般名なので、取り込むと利用者の型と衝突しうる。使うなら `namespace clip = NativeToolkit::Clipboard;` のように別名を切る | 全機能 |

### 7.6 成果物の分け方

段階 4 でサンプルが C++ API にリンクできるよう、段階 3 で次のように分ける。

| 成果物 | 種別 | 中身 | 利用者 |
|---|---|---|---|
| `WindowsLibraryCore` | **StaticLibrary** | C++ API（`include/NativeToolkit/`）と全機能の実装 | サンプル（段階 4 以降）、ネイティブの利用者 |
| `WindowsLibrary` | DynamicLibrary | 既存の C ABI 47 関数 + `Common` の 5 関数。`WindowsLibraryCore` にリンクし、型の変換だけを行う | 今の C ABI の利用者。段階 5 で `WindowsLibraryCApi` に改名・移動する |

#### 7.6.1 C ブリッジの分離（S-1）

今は `extern "C"` の関数が実装と**同じ翻訳単位**にある（例: `WindowsClipboardManager.cpp` の末尾に 27 個の C 関数）。このまま静的ライブラリへ入れると次の問題が起きる。

- 静的ライブラリのオブジェクトは**参照されたものだけ**がリンクされる。`.def` に載っていない Dialog の 6 関数と `initWinAppSdk` は、ライブラリ内から呼ばれないため **DLL から消える**
- `WINDOWSLIBRARY_EXPORTS` を静的コアで定義すると、コアを直接リンクする利用者の成果物に export 指令が混入する。定義しないと、定義側が `dllimport` 宣言に従うことになり破綻する

したがって **T-02 で次を行う**（T-14 ではない）。

1. `extern "C"` の関数を、機能ごとの**ブリッジ用の `.cpp`**（`src/Bridge/<Feature>Bridge.cpp` など）へ移し、**DLL プロジェクトにだけ**登録する。段階 5 ではこのファイル群が `WindowsLibraryCApi` へ移る
2. `WINDOWSLIBRARY_EXPORTS` は **DLL プロジェクトでのみ定義**する。コアのヘッダーは `dllimport` / `dllexport` を一切持たない中立の宣言にする。`Common/common.h` のログ関数も、内部用の宣言と export 用のファサードに分ける
3. **`.def` に 52 個すべて**（機能 47 + `Common` 5）を列挙する。D-5 の「`.def` だけにする」に沿うため、`__declspec(dllexport)` は段階 3 で落とす
4. 完了条件を機械的にする。**分割前後の DLL に対する `dumpbin /exports` の差分が 0 件**であることを確かめ、段階 3 の結果ファイルに残す

#### 7.6.2 ほかのプロジェクトへの影響

- `WindowsLibraryTest` は今、ライブラリの **8 つの `.cpp` だけ**を選んでコンパイルし、`WINDOWSLIBRARY_EXPORTS` を定義している（`WindowsClipboardManager.cpp` や WinRT 背面は意図的に外し、`SetHistoryBackendFactoryForTest` で差し替えている）。静的コア全体をリンクすると対象が変わるため、**今と同じ対象範囲を保つか、増える分を意図として記録する**（T-02 の完了条件）
- `WindowsLibraryExample` は段階 4 で `WindowsLibraryCore.vcxproj` を参照するようにする。段階 3 では include パスの追加と、`.props` の骨組みが効くことの確認まで（T-03）
- `scripts/build_windows_library_dll.ps1` の `Project` / `Headers` を更新する。`Headers` は今 `src` 配下の 3 ファイルだけなので、`include/NativeToolkit` の 5 ヘッダーを加える（T-03）
- 段階 5 でやることは「ブリッジ用の `.cpp` 群を `WindowsLibraryCApi` へ移し、中身を新しい C ABI に置き換える」だけになる

## 8. API 設計

**公開 OP**: OP-01〜OP-47 の **47 件**。内訳は Dialog 6（OP-01〜OP-06）、Notification 14（OP-07〜OP-20）、Clipboard 27（OP-21〜OP-47）。

### 8.1 C ABI から C++ API への置き換え先

`C++ API` 列のシグネチャは各機能の名前空間の中のものとし、`Result<T>` はその名前空間の別名を指す（7.2）。

| OP | 今の C ABI | C++ API | 主な変更点 |
|---|---|---|---|
| OP-01 | `showAlertDialog` | `Result<AlertResult> ShowAlert(const AlertRequest&)` | `MB_*` の 4 引数を `enum class` + `extraFlags`（N-9）にする。戻り値は `AlertResult`（`IDCLOSE` / `IDHELP` を含む） |
| OP-02 | `showFileDialog` | `Result<std::wstring> ShowOpenFile(const FileRequest&)` | バッファを廃止。キャンセルは `DialogError::Canceled` |
| OP-03 | `showMultiFileDialog` | `Result<std::vector<std::wstring>> ShowOpenFiles(const FileRequest&)` | `\0` 区切りの解析を呼び出し側から無くす |
| OP-04 | `showSaveFileDialog` | `Result<std::wstring> ShowSaveFile(const SaveFileRequest&)` | `def_ext` は `SaveFileRequest::defaultExtension` |
| OP-05 | `showFolderDialog` | `Result<std::wstring> ShowPickFolder(const FolderRequest&)` | 同上 |
| OP-06 | `showMultiFolderDialog` | `Result<std::vector<std::wstring>> ShowPickFolders(const FolderRequest&)` | 同上 |
| OP-07 | `initWinAppSdk` | `Result<Runtime> Runtime::Initialize(RuntimeVersion)` | ムーブのみのトークンにし、破棄で `MddBootstrapShutdown` を呼ぶ（N-7）。`isPackaged` は足さない（今の実装は元から `DeploymentManager` を呼ばない）。**unpackaged 専用** |
| OP-08 | `initNotificationManager` | `Result<Manager> Manager::Create(const ManagerOptions&)` | ムーブのみの RAII。2 個目は `NotSupported`（7.4.2） |
| OP-09 | `uninitNotificationManager` | `void Manager::Close()` / `~Manager()` | 戻り値は今も無い。revoke → callback を null の順序を維持（NTF-40） |
| OP-10 | `showNotification` | `Result<void> Manager::Show(const NotificationContent&)` | JSON 入力を構造体にする |
| OP-11 | `scheduleNotification` | `Result<void> Manager::Schedule(const NotificationContent&, std::chrono::system_clock::time_point)` | Unix ミリ秒を `time_point` にする |
| OP-12 | `cancelScheduledNotification` | `Result<void> Manager::CancelScheduled(std::wstring_view tag, std::wstring_view group)` | そのまま |
| OP-13 | `updateNotificationProgress` | `Result<void> Manager::UpdateProgress(const ProgressUpdate&)` | 6 引数を構造体に。`sequenceNumber` は呼び出し側が持つ（NTF-44） |
| OP-14 | `setBadge` | `Result<void> Manager::SetBadge(int value)` | unpackaged では `NotSupported`（今の実装どおり） |
| OP-15 | `removeNotificationById` | `Result<void> Manager::RemoveById(uint32_t id)` | unpackaged では `NotSupported` |
| OP-16 | `removeNotificationsByTag` | `Result<void> Manager::RemoveByTag(std::wstring_view tag, std::wstring_view group)` | そのまま |
| OP-17 | `removeAllNotifications` | `Result<void> Manager::RemoveAll()` | そのまま |
| OP-18 | `getAllNotifications` | `Result<std::vector<NotificationRef>> Manager::GetAll()` | JSON とバッファを廃止 |
| OP-19 | `getNotificationSetting` | `Result<NotificationSetting> Manager::GetSetting()` | `int` と `-1` の二重の意味を解消 |
| OP-20 | `openNotificationSettings` | `Result<void> Manager::OpenSettings()` | そのまま |
| OP-21 | `initClipboardManager` | `Result<Session> Session::Create(const SessionOptions&)` | ムーブのみの RAII。2 個目は同じスレッドから `NotSupported`、別スレッドから `WrongThread`（7.4.1） |
| OP-22 | `setClipboardHistoryCallbacks` | `Result<void> Session::SetHistoryHandlers(HistoryHandlers)` | 3 つのハンドラを構造体で渡す。空の `HistoryHandlers{}` が解除（CLP-112） |
| OP-23 | `uninitClipboardManager` | `Result<void> Session::Close()` | 5 通りのエラーをそのまま返す。冪等（7.4.1） |
| OP-24 | `canDestroyClipboardManager` | `bool Session::CanClose() const` | **任意スレッドから呼べる**。助言であることを Doxygen に明記（CLP-104） |
| OP-25 | `copyPlainText` | `Result<void> Session::CopyText(std::wstring_view, WriteOptions = {})` | そのまま |
| OP-26 | `pastePlainText` | `Result<std::wstring> Session::PasteText()` | 2 回呼びを廃止 |
| OP-27 | `copyHtml` | `Result<void> Session::CopyHtml(std::wstring_view fragment, std::wstring_view plainText, WriteOptions = {})` | そのまま |
| OP-28 | `pasteHtml` | `Result<std::wstring> Session::PasteHtml()` | 2 回呼びを廃止 |
| OP-29 | `copyFiles` | `Result<void> Session::CopyFiles(std::span<const std::wstring>, WriteOptions = {})` | JSON 入力を廃止 |
| OP-30 | `pasteFiles` | `Result<std::vector<std::wstring>> Session::PasteFiles()` | JSON 出力を廃止 |
| OP-31 | `copyImage` | `Result<void> Session::CopyDib(std::span<const std::byte>, WriteOptions = {})` | DIB のバイト列という契約は維持（CLP-125） |
| OP-32 | `pasteImage` | `Result<std::vector<std::byte>> Session::PasteDib()` | 2 回呼びを廃止 |
| OP-33 | `copyCustomFormat` | `Result<void> Session::CopyCustom(std::wstring_view formatName, std::span<const std::byte>, WriteOptions = {})` | そのまま |
| OP-34 | `pasteCustomFormat` | `Result<std::vector<std::byte>> Session::PasteCustom(std::wstring_view formatName)` | 2 回呼びを廃止 |
| OP-35 | `copyMultipleFormats` | `Result<void> Session::CopyMultiple(std::span<const FormatPayload>, WriteOptions = {})` | JSON 入力を判別付きの `FormatPayload` にする。並びと事前検証の契約は維持（CLP-123、CLP-137） |
| OP-36 | `hasClipboardFormat` | `Result<bool> Session::HasFormat(std::wstring_view formatName)` | そのまま |
| OP-37 | `getClipboardFormats` | `Result<std::vector<std::wstring>> Session::GetFormats()` | JSON 出力を廃止 |
| OP-38 | `getPreferredClipboardFormat` | `Result<std::wstring> Session::GetPreferredFormat()` | 2 回呼びを廃止 |
| OP-39 | `clearClipboard` | `Result<void> Session::Clear()` | そのまま |
| OP-40 | `reserveDeferredFormats` | `Result<void> Session::ReserveDeferred(std::span<const std::wstring> formats, RenderProvider)` | `void* context` を廃止。形式名と provider は深いコピー（7.4.3）。provider の禁止事項は Doxygen に維持（CLP-28） |
| OP-41 | `recoverDeferredState` | `Result<void> Session::RecoverDeferredState()` | そのまま |
| OP-42 | `getClipboardHistory` | `Result<RequestId> Session::GetHistory(HistoryItemsHandler)` | ハンドラは `void(RequestId, Result<std::vector<HistoryItem>>)`。JSON を構造体にする |
| OP-43 | `restoreHistoryItem` | `Result<RequestId> Session::RestoreHistoryItem(std::wstring_view itemId, CompletionHandler)` | ハンドラは `void(RequestId, Result<void>)`。ペイロード無しの完了（CLP-14） |
| OP-44 | `deleteHistoryItem` | `Result<RequestId> Session::DeleteHistoryItem(std::wstring_view itemId, CompletionHandler)` | 同上 |
| OP-45 | `clearUnpinnedHistory` | `Result<RequestId> Session::ClearUnpinnedHistory(CompletionHandler)` | pinned が残る契約は維持（CLP-82） |
| OP-46 | `getClipboardHistoryAvailability` | `Result<RequestId> Session::GetHistoryAvailability(AvailabilityHandler)` | ハンドラは `void(RequestId, Result<HistoryAvailability>)` |
| OP-47 | `cancelClipboardRequest` | `Result<void> Session::CancelRequest(RequestId)` | 任意スレッドから呼べる（CLP-18）。未知・完了済みの ID は `InvalidParameter`、投稿の失敗は `Unknown`。「配送中の完了は取り消さない」を Doxygen に維持（CLP-17） |

### 8.2 公開する型

**型は実装のパーサ（`BuildFromJson` ほか）と `MessageBoxW` / `GetOpenFileNameW` の引数から導出する**（S-3）。サンプルが使っていない項目も落とさない。

```cpp
// ---- Types.h ----
struct HWND__;                                    // 大域。7.1

namespace NativeToolkit {
using WindowHandle = ::HWND__*;

struct WriteOptions {                             // 今のビットフラグに対応
    bool excludeHistory = false;                  // 0x1
    bool excludeRoaming = false;                  // 0x2
};                                                // 両方 true が今の SENSITIVE (0x3)
}

// ---- Dialog.h ----
namespace NativeToolkit::Dialog {
enum class AlertButtons { Ok, OkCancel, YesNo, YesNoCancel, RetryCancel, AbortRetryIgnore, CancelTryContinue };
enum class AlertIcon { None, Information, Warning, Error, Question };
enum class AlertDefaultButton { First, Second, Third, Fourth };
enum class AlertResult { Ok, Cancel, Yes, No, Retry, Abort, Ignore, TryAgain, Continue, Close, Help };

struct AlertRequest {
    std::wstring       title;
    std::wstring       message;
    AlertButtons       buttons       = AlertButtons::Ok;
    AlertIcon          icon          = AlertIcon::None;
    AlertDefaultButton defaultButton = AlertDefaultButton::First;
    bool               topMost       = false;
    bool               showHelpButton = false;     // MB_HELP
    uint32_t           extraFlags    = 0;          // 上で表せない MB_* を素通しする逃げ道（N-9）
    WindowHandle       owner         = nullptr;    // 今は常に nullptr
};

struct FileFilter {                                // 今の "説明\0*.txt;*.log\0" を構造にする
    std::wstring              description;
    std::vector<std::wstring> patterns;            // 空なら *.* とみなす
};

struct FileRequest {
    std::wstring             title;                // 今の C ABI には無い新機能（DLG-13）
    std::vector<FileFilter>  filters;              // 空なら L"All Files\0*.*\0" 相当（DLG-12）
    bool                     fileMustExist = true; // OFN_FILEMUSTEXIST（DLG-11）
    WindowHandle             owner = nullptr;
};

struct SaveFileRequest {
    std::wstring             title;
    std::vector<FileFilter>  filters;
    std::wstring             defaultExtension;
    bool                     overwritePrompt = true;  // OFN_OVERWRITEPROMPT（DLG-11）
    WindowHandle             owner = nullptr;
};

struct FolderRequest { std::wstring title; WindowHandle owner = nullptr; };  // 空なら OS の既定（DLG-05）
}

// ---- Notification.h ----
namespace NativeToolkit::Notification {
enum class NotificationSetting { Enabled, DisabledForApplication, DisabledForUser, DisabledByGroupPolicy, DisabledByManifest };
enum class Scenario  { Default, Reminder, Alarm, Urgent, IncomingCall };
enum class AudioKind { Event, Mute, Uri };         // 既定は Event（今の "event"）
enum class Duration  { Short, Long };
enum class LogoCrop  { None, Circle };

struct RuntimeVersion { uint32_t majorMinor = 0; };

using ArgumentPairs = std::vector<std::pair<std::wstring, std::wstring>>;  // 任意のキー値を落とさない

// フィールド名は JSON のキーに合わせる（label / placeholder / defaultSelection）
struct Button {
    std::wstring  label;                           // JSON: label（必須）
    ArgumentPairs args;                            // JSON: args。args と invokeUri はボタン単位で排他
    std::wstring  invokeUri;
};
struct TextInput  { std::wstring id; std::wstring placeholder; std::wstring title; };
struct ComboItem  { std::wstring id; std::wstring label; };
struct ComboInput { std::wstring id; std::wstring title; std::wstring defaultSelection; std::vector<ComboItem> items; };
struct AppLogo    { std::wstring uri; LogoCrop crop = LogoCrop::None; };   // JSON: appLogo は入れ子のオブジェクト

struct AudioSpec {
    AudioKind    kind = AudioKind::Event;
    std::wstring eventName;                        // JSON: event。reminder / alarm / loopingAlarm / loopingCall
    std::wstring uri;                              // JSON: uri（kind == Uri のとき必須）
    bool         loop = false;                     // loop は duration == Long が必須
};                                                 // kind == Mute のとき eventName と loop は捨てられる（今の実装と同じ）

struct ProgressSpec {
    std::wstring                title;             // JSON: title
    double                      value = 0.0;       // JSON: value（範囲の検査は無い）
    std::optional<std::wstring> valueStr;          // JSON: valueStr。**キーの有無**がバインドの有無を決める
    std::optional<std::wstring> status;            // JSON: status。同上
};

struct NotificationContent {
    std::wstring                title;
    std::wstring                body;
    std::wstring                tag;
    std::wstring                group;
    Scenario                    scenario = Scenario::Default;
    std::wstring                heroImage;         // JSON: heroImage
    std::wstring                inlineImage;       // JSON: inlineImage
    std::optional<AppLogo>      appLogo;           // JSON: appLogo（uri + crop）
    std::wstring                attribution;       // JSON: attribution
    Duration                    duration = Duration::Short;
    std::optional<AudioSpec>    audio;             // JSON: audio。空なら音は OS に任せる（T-08）
    std::vector<Button>         buttons;           // 最大 5（NTF-34）
    std::vector<TextInput>      textInputs;
    std::vector<ComboInput>     comboInputs;
    std::optional<ProgressSpec> progress;              // Schedule では無視される（今の実装と同じ）
    std::optional<std::chrono::system_clock::time_point> timestamp;  // JSON: timestamp（絶対・Unix 秒）
    std::optional<std::chrono::seconds> expiration;    // JSON: expiration（相対秒）。Schedule では無視される
    bool                        expiresOnReboot = false;              // unpackaged では無視される
    ArgumentPairs               unknownKeys;                          // 今は黙って無視される未知のキーを保持する
};
// 最上位に arguments / invokeUri は無い（今の C ABI に存在しないため足さない）

struct ProgressUpdate {
    std::wstring tag;
    std::wstring group;
    double       value = 0.0;
    std::wstring valueString;
    std::wstring status;
    uint32_t     sequenceNumber = 0;
};
struct NotificationRef { uint32_t id = 0; std::wstring tag; std::wstring group; };

struct ActivationArgs {                            // 併合された辞書を失わずに渡す
    ArgumentPairs values;                          // action / id / reply / combo_selection_id なども含む
    std::wstring  rawArguments;
};

struct ManagerOptions {
    std::function<void(const ActivationArgs&)> onInvoked;
    bool         isPackaged = true;
    std::wstring displayName;                      // unpackaged では必須
    std::wstring iconUri;                          // unpackaged では必須
};

class Runtime { /* ムーブのみ。7.4.2 */ };

class Manager {                                    // ムーブのみ
public:
    static Result<Manager> Create(const ManagerOptions&);
    Manager(Manager&&) noexcept;
    Manager& operator=(Manager&&) noexcept;
    ~Manager();                                    // noexcept。Close() を試みる

    void SetInvokedHandler(std::function<void(const ActivationArgs&)>);  // 2 回目の init 相当（N-10）
    void Close();

    Result<void>                        Show(const NotificationContent&);
    Result<void>                        Schedule(const NotificationContent&, std::chrono::system_clock::time_point);
    Result<void>                        CancelScheduled(std::wstring_view tag, std::wstring_view group);
    Result<void>                        UpdateProgress(const ProgressUpdate&);
    Result<void>                        SetBadge(int value);
    Result<void>                        RemoveById(uint32_t id);
    Result<void>                        RemoveByTag(std::wstring_view tag, std::wstring_view group);
    Result<void>                        RemoveAll();
    Result<std::vector<NotificationRef>> GetAll();
    Result<NotificationSetting>         GetSetting();
    Result<void>                        OpenSettings();
};
}

// ---- Clipboard.h ----
namespace NativeToolkit::Clipboard {
enum class RequestId : uint32_t {};                // 強い型。戻り値の判定に 0 を使わない

struct TextPayload  { std::wstring formatName; std::wstring text; };
struct HtmlPayload  { std::wstring formatName; std::wstring html; };   // CF_HTML を内部で組み立てる
struct BytesPayload { std::wstring formatName; std::vector<std::byte> bytes; };
using  FormatPayload = std::variant<TextPayload, HtmlPayload, BytesPayload>;   // 矛盾した状態を作れない

struct HistoryItem {
    std::wstring                id;
    std::optional<std::wstring> text;              // テキストを持たない項目は nullopt（CLP-118）
    std::vector<std::wstring>   contentTypes;      // 無加工（CLP-121）
    int64_t                     timestampTicks = 0;
};
struct HistoryAvailability { bool historyEnabled = false; bool roamingEnabled = false; };

struct HistoryHandlers {                           // 空の構造体を渡すと解除（CLP-112）
    std::function<void()>     onHistoryChanged;
    std::function<void(bool)> onHistoryEnabledChanged;
    std::function<void(bool)> onRoamingEnabledChanged;
};

struct SessionOptions { std::function<void()> onClipboardChanged; };

using RenderProvider      = std::function<Result<std::vector<std::byte>>(std::wstring_view formatName)>;
using CompletionHandler   = std::function<void(RequestId, Result<void>)>;
using HistoryItemsHandler = std::function<void(RequestId, Result<std::vector<HistoryItem>>)>;
using AvailabilityHandler = std::function<void(RequestId, Result<HistoryAvailability>)>;

class Session {                                    // ムーブのみ。7.4.1
public:
    static Result<Session> Create(const SessionOptions&);
    Session(Session&&) noexcept;
    Session& operator=(Session&&) noexcept;
    ~Session();                                    // noexcept。Close() 未成功なら放棄（N-5）

    Result<void> Close();
    bool         CanClose() const noexcept;        // 任意スレッド
    Result<void> SetHistoryHandlers(HistoryHandlers);

    // 同期 Win32 コア（OP-25〜OP-39）と遅延レンダリング（OP-40、OP-41）、
    // 履歴（OP-42〜OP-47）は 8.1 のシグネチャのとおり
};
}
```

- `Manager` / `Session` / `Runtime` はムーブのみ。コピーは `= delete`
- ムーブ後の状態は「閉じた `Session`」と同じで、データ系の API は `NotInitialized` を返し、デストラクタは何もしない
- エラーの列挙（`DialogError` / `NotificationError` / `ClipboardError`）は 11 章。ヘッダーでは値を明示した `enum class ... : uint32_t` として宣言する
- JSON のキーと C++ のフィールド名の対応（`content` ↔ `label` など）は U-B の比較表として `WindowsLibraryTest` 側に持つ

### 8.3 C++ API で意図的に変えないもの

- Notification のコールバックの配送スレッド（NTF-02）。UI スレッドへ移すと観測できる契約が変わる
- cold start の活性化が `Manager::Create` の中から呼び出しスレッドで 1 回配送されること（NTF-09、Codex 16）
- Clipboard のコールバックは非 inline・オーナー UI スレッド・ちょうど 1 回（CLP-01、CLP-02、CLP-06）
- `Close()` の再試行の契約と、5 通りのエラーの返し分け（CLP-20、CLP-103）
- 遅延レンダリングが `HGLOBAL` 形式に限られること（CLP-67）と、内部の 2 相呼び出し
- 画像が DIB のバイト列であること（CLP-125）
- Dialog のフォルダ選択がライブラリ側で COM を初期化すること（DLG-06）

## 9. 同期・非同期レイヤー対応表

全 47 操作を対象とする。`スレッド` 列は**完了が届くスレッド**。受付を呼べるスレッドは `キャンセル・所有権` 列に書く。

| OP | System API と実行方式 | Repository | UseCase | Manager | C++ API | スレッド | キャンセル・所有権 | 変換の理由 |
|---|---|---|---|---|---|---|---|---|
| OP-01 | `MessageBoxW` 同期・モーダル | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | - |
| OP-02 | `GetOpenFileNameW` 同期・モーダル | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 文字列は値で返す | - |
| OP-03 | `GetOpenFileNameW`（複数選択）同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 同上 | - |
| OP-04 | `GetSaveFileNameW` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 同上 | - |
| OP-05 | `IFileOpenDialog`（フォルダ）同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | COM は Data 層の RAII。ライブラリが `CoInitializeEx` する（DLG-06） | - |
| OP-06 | `IFileOpenDialog`（複数フォルダ）同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 同上 | - |
| OP-07 | `MddBootstrapInitialize` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | `Runtime` トークンが所有し、破棄で `MddBootstrapShutdown`（N-7） | unpackaged 専用。packaged では呼ばない |
| OP-08 | `CoRegisterClassObject` / `AppNotificationManager::Register` 同期 | 同期 | 検証（同期） | 同期 | 同期 | 呼び出しスレッド | `Manager` が backend を所有（NTF-22） | 登録の順序は NTF-38 のまま |
| OP-09 | `CoRevokeClassObject` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | revoke → callback を null（NTF-40） | - |
| OP-10 | `AppNotificationManager::Show` 同期 | 同期 | 組み立て・検証（同期） | 同期 | 同期 | 呼び出しスレッド | `NotificationContent` は値渡し | - |
| OP-11 | classic `ScheduledToastNotification` 同期 | 同期 | 同上 | 同期 | 同期 | 呼び出しスレッド | 無し | packaged でも classic を使う唯一の例外を維持（NTF-50） |
| OP-12 | `GetScheduledToastNotifications` / `RemoveFromSchedule` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | tag / group で照合（NTF-46） | - |
| OP-13 | `UpdateAsync` 非同期・アフィニティ要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | `sequenceNumber` は呼び出し側 | `windows.md` の表 3 行目（非同期・要件なし → 同期を維持）。今の `RunSyncOffSta` を維持する |
| OP-14 | `BadgeUpdater` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | - |
| OP-15 | `RemoveByIdAsync` 非同期・要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | 同 OP-13 |
| OP-16 | `RemoveByTagAsync` 非同期・要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | 同 OP-13 |
| OP-17 | `RemoveAllAsync` 非同期・要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | 同 OP-13 |
| OP-18 | `GetAllAsync` 非同期・要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | 一覧は値で返す | 同 OP-13 |
| OP-19 | `Setting` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | 変換は明示の `switch`（NTF-33） |
| OP-20 | `Launcher::LaunchUriAsync` 非同期・要件なし | 非 STA ワーカーで待機 | 無し | 同期 | 同期 | 呼び出しスレッド | 無し | 同 OP-13 |
| OP-21 | `CoGetApartmentType` / `CreateWindowExW` / `AddClipboardFormatListener` 同期・STA 限定 | 同期 | 無し | 同期 | 同期 | オーナー UI スレッド | 呼び出しスレッドをオーナーとして採用（CLP-35） | STA でなければ `WrongApartment`（CLP-38） |
| OP-22 | WinRT イベントの購読 同期・UI 限定 | 同期 | 差し替え（同期） | 同期 | 同期 | オーナー UI スレッド | 置き換えは原子的で失敗しない（CLP-108） | - |
| OP-23 | `RemoveClipboardFormatListener` / `DestroyWindow` 同期・UI 限定 | 同期 | ドレイン（同期） | 同期 | 同期（再試行あり） | オーナー UI スレッド | 完了権をドレインキューへ移す（CLP-100） | 1 回で終わらない契約と 5 通りのエラーを維持（7.4.1） |
| OP-24 | 状態の問い合わせのみ | 無し | 無し | 同期 | 同期 | 呼び出しスレッド | **任意スレッドから呼べる**（今の実装どおり。同期化された状態の写しを返す） | 助言であることを維持（CLP-104） |
| OP-25 | Win32 `SetClipboardData` 同期・アフィニティ要件なし | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | `PutFormat` 成功時のみ所有権が移る（CLP-61） | - |
| OP-26 | Win32 `GetClipboardData` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 文字列は値で返す | 2 回呼びを廃止（C++ 側のみ） |
| OP-27 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-25 | - |
| OP-28 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-26 | 同 OP-26 |
| OP-29 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-25 | JSON の解析を廃止 |
| OP-30 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-26 | JSON の生成を廃止 |
| OP-31 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-25 | - |
| OP-32 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-26 | 同 OP-26 |
| OP-33 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-25 | - |
| OP-34 | Win32 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 同 OP-26 | 同 OP-26 |
| OP-35 | Win32 同期（複数形式） | 同期 | 事前検証・配置・巻き戻し（同期） | 同期 | 同期 | 呼び出しスレッド（任意） | 失敗時は再 `EmptyClipboard`（CLP-75） | 配置前の種別検証を維持（CLP-137） |
| OP-36 | `IsClipboardFormatAvailable` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 無し | - |
| OP-37 | `GetUpdatedClipboardFormats` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 一覧は値で返す | 列挙の失敗時の扱いは維持（CLP-93） |
| OP-38 | `GetPriorityClipboardFormat` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 無し | - |
| OP-39 | `EmptyClipboard` 同期 | 同期 | 無し | 同期 | 同期 | 呼び出しスレッド（任意） | 無し | - |
| OP-40 | `SetClipboardData(nullptr)` 同期・UI 限定 | 同期 | 予約の状態機械（同期） | 同期 | 同期 | オーナー UI スレッド | 形式名と provider は深いコピー（7.4.3） | UI 限定を維持（CLP-46） |
| OP-41 | 同上 | 同期 | 同上 | 同期 | 同期 | オーナー UI スレッド | 保存済みのオーナーを使う（CLP-70） | - |
| OP-42 | `GetHistoryItemsAsync` 非同期・UI 限定 | コルーチン | 受付と状態機械（同期） | 非同期（コールバック） | 非同期（コールバック） | オーナー UI スレッド | 受付は任意スレッド。受付後はちょうど 1 回（CLP-06）。キャンセルは論理（CLP-16） | UI スレッドで開始が必須のため（`windows.md` の表 4 行目） |
| OP-43 | `GetHistoryItemsAsync` で項目を引き当ててから同期の `SetHistoryItemAsContent` | コルーチン | 同上 | 非同期（コールバック） | 非同期（コールバック） | オーナー UI スレッド | 同上 | 非同期なのは**項目の引き当て**のほう。状態の写像（`AccessDenied` / `ItemDeleted`）は同期側 |
| OP-44 | `GetHistoryItemsAsync` で項目を引き当ててから同期の `DeleteItemFromHistory` | コルーチン | 同上 | 非同期（コールバック） | 非同期（コールバック） | オーナー UI スレッド | 同上 | 同 OP-43。`false` は `Unknown` に写す（CLP-90） |
| OP-45 | `ClearHistory` 同期・UI 限定 | 同期 | 同上 | 非同期（コールバック） | 非同期（コールバック） | オーナー UI スレッド | 同上。pinned は残る（CLP-82） | 受付と完了を分ける既存の契約を維持（CLP-07） |
| OP-46 | `IsHistoryEnabled` / `IsRoamingEnabled` 同期・UI 限定 | 同期 | 同上 | 非同期（コールバック） | 非同期（コールバック） | オーナー UI スレッド | 同上 | 同期版は廃止済み（CLP-115）。復活させない |
| OP-47 | 無し（内部の配送のみ） | 無し | 取り消し（同期） | 同期 | 同期 | 呼び出しスレッド | 任意スレッドから呼べる。完了権の take（CLP-22） | 任意スレッドの契約を維持（CLP-18） |

### 9.1 変換の理由（企画書の分類との差）

- 企画書の分類表は C ABI の分類であり、C++ API では次の 3 点だけが変わる。いずれも同期性の変更ではない
  - 出力バッファの 2 回呼び（OP-18、OP-26、OP-28、OP-30、OP-32、OP-34、OP-37、OP-38）を値返しにする。C ABI の 2 回呼びは DLL ブリッジに残る
  - `void* context`（OP-40）を `std::function` の捕捉にする
  - 履歴の完了に `RequestId` を渡す（今の C ABI と同じ情報量。v1 では落としていた）
- Notification の非同期 WinRT 操作（OP-13、OP-15〜OP-18、OP-20）は `windows.md` の表 3 行目（非同期・アフィニティ要件なし → 同期を維持）に該当するため、今の非 STA ワーカーでの待機を維持する。**呼び出しスレッドを塞ぐ点も今と同じ**である
- Clipboard の履歴は UI スレッド要件があるため非同期（コールバック）を維持する。該当する `windows.md` の行は 2 つに分かれる
  - **OP-42、OP-43**: 非同期 + UI 要件 → 表の 4 行目
  - **OP-44、OP-45、OP-46**: 同期 + UI / フォアグラウンド要件を任意スレッドから呼ばせる → 表の 2 行目（`PostMessage` で UI へ配送し、コールバックで完了通知）
- `std::future` にはしない。完了がオーナー UI スレッドに限られる契約（CLP-01）を `std::future` では表せないため

## 10. 既存の約束の対応表

README 5.1 が求める表。既存の設計書とコードが定めた契約が、C++ API のどこで守られるかを示す。

**ID の扱い（R-9 の反映）**: `CLP-xx` / `NTF-xx` / `DLG-xx` は**この設計書が振った番号**であり、元の設計書には存在しない。照合できるよう、出典の行番号（`clipboard v2` = `artifact/features/clipboard/designs/2026-07-28-windows-clipboard-design-v2.md`、`notification v3` = `artifact/features/notification/designs/2026-05-30-windows-notification-design-v3.md`）を併記する。Dialog は設計書が無いため、出典は実装のファイルとする。

ここに載せるのは「書き直しで壊れうるもの」に限る。内部実装の規約（ロックの順序、RAII の使い方など）は実装が変わらないため対象外とする。

### 10.1 Clipboard

| ID | 出典（clipboard v2） | 約束 | C++ API での守り方 |
|---|---|---|---|
| CLP-01 | 280 | 全ての完了コールバックはオーナー UI スレッドで呼ぶ | 完了の配送経路（coordinator）に手を入れない |
| CLP-02 | 281 | 完了を同一スタックから inline に呼ばない。UI スレッドからでも `PostMessage` を経由する | 同上。C++ API は受付だけを行う |
| CLP-04 | 282 | 呼び出し元スレッドへは戻さない | Doxygen に明記する |
| CLP-05 / CLP-34 | 283、873 | コールバック内から `Close` / `SetHistoryHandlers` を呼んではならない | Doxygen に明記し、デバッグビルドの assert を維持する。**`Session` の捕捉禁止も併記する**（7.4.1） |
| CLP-06 / CLP-10 | 889-892、1122 | 受付前の失敗は 0 回、受付後はちょうど 1 回 | 受付失敗は `Result<RequestId>` のエラー側で返し、コールバックを呼ばない。戻り値の判定に `0` を使わない |
| CLP-07 | 887 | 受付成立は「引数検証 → lease 取得 → pending 登録 → `PostMessage`」がすべて成功した時点 | 変更なし |
| CLP-08 | 894 | フォアグラウンド判定は受付後に行い、コールバックで返す | 変更なし |
| CLP-11 | 934-937 | コールバックは単一の終端まで有効でなければならない | `std::function` を `Session` の内部で保持する。関数ポインタの寿命の注意は DLL ブリッジ側に残る |
| CLP-12 / CLP-15 / CLP-65 | 931-933、1134-1135 | JSON のポインタはコールバック中だけ有効で、toolkit が解放する | **C++ API では消える**（値で渡すため）。DLL ブリッジ側で維持する |
| CLP-13 / CLP-14 | 1136-1137 | 失敗時は payload が null。ペイロード無しの成功がある | `Result<void>`（OP-43〜OP-45）と `Result<T>`（OP-42、OP-46）で型として表す |
| CLP-16 / CLP-17 / CLP-18 | 334、1112-1117 | キャンセルは論理。配送中の完了は取り消さない。任意スレッドから呼べる | `CancelRequest` の Doxygen に維持。未知の ID は `InvalidParameter`、投稿失敗は `Unknown`（実装どおり） |
| CLP-20 / CLP-103 | 384、386 | `uninit` は 2 回以上呼ぶ設計。失敗後はメッセージを回して再試行する | `Session::Close()` で維持（7.4.1）。冪等性と 5 通りのエラーも維持 |
| CLP-27 / CLP-28 / CLP-29 | 662-663、682 | provider は UI スレッド上・`WM_RENDERFORMAT` の中で呼ばれ、クリップボード API を呼ばず、ブロックせず、2 相で呼ばれる | 呼ばれる場所と禁止事項を Doxygen に維持。**2 相は内部に残す**（10.4 N-2）。provider が投げた例外は捕捉して `Unknown` にする（N-3） |
| CLP-31 | 971-973 | `onHistoryChanged` は新規項目の追加でだけ発火する | Doxygen に維持する |
| CLP-32 | 863、720-722 | フラグの値はイベントスレッドではなくオーナー UI スレッドで解決する | 実装は変えない |
| CLP-35〜CLP-39 | 252-265、947-953 | オーナースレッドの採用、UI 限定 API のスレッド判定、二重 init の扱い、STA の事前確認、アパートメントに触れない | `Session::Create` に同じ判定を残す。二重 init は 7.4.1 のとおり（C ABI の冪等性はブリッジが保つ） |
| CLP-40 / CLP-41 / CLP-42 | 243、267-269 | 配送用 HWND はライブラリが作る。`HWND_MESSAGE` を使わない。ホストのウィンドウをサブクラス化しない | `SessionOptions::foregroundWindow` は判定の参照のみで、配送には使わない |
| CLP-46 / CLP-48 | 1092、1018 | 遅延レンダリングの 2 API と履歴ハンドラの登録はオーナー UI スレッド限定 | 変更なし |
| CLP-58 | 769 | フォアグラウンド判定はプロセス ID の一致で行う | 変更なし |
| CLP-64 | 1099 | バッファ不足は必要サイズを返す 2 回呼び | **C++ API では消える**。DLL ブリッジ側で維持する |
| CLP-67 | 646 | 遅延レンダリングは `HGLOBAL` 形式のみ | `RenderProvider` はバイト列を返し、`HGLOBAL` 化は内部で行う。受け付ける形式の制限は維持 |
| CLP-68 | 639-644 | 遅延レンダリングの 3 状態と、状態ごとのテーブル保持 | 実装は変えない |
| CLP-75 | 559 | 複数形式の配置は全構築 → 失敗時に巻き戻し → 巻き戻し失敗で `PartialState` | 変更なし |
| CLP-82 | 1309 | `ClearHistory` 後も pinned 項目は残る | Doxygen に維持する |
| CLP-86 | 1175 | エラーは成功を含めて 20 定数、非成功 19 種。名前は `INVALID_PARAMETER` | `enum class ClipboardError` に 20 個そのまま移す（11.1） |
| CLP-87 | 1216 | `UNKNOWN` を返すときは生の値を必ずログに残す | `Failure::systemCode` に載せたうえでログにも残す |
| CLP-88 / CLP-89 / CLP-90 | 767-773、1253 | 3 段階の前提判定と `HistoryDisabled` / `AccessDenied` / `Unknown` の書き分け。`DeleteItem` / `ClearUnpinned` の `false` は `Unknown` | 変更なし。11.1 の `Unknown` の発生源に明記する |
| CLP-93 | 563-564 | `CountClipboardFormats` の 0 の弁別と列挙の失敗時の扱い | 変更なし |
| CLP-112 | 1020 | 3 つとも `nullptr` で登録解除 | 空の `HistoryHandlers{}` で表す |
| CLP-117 / CLP-118 | 779-781 | 履歴の順序は WinRT の順。テキストの無い項目も含め、項目単位の失敗で全体を失敗させない | `std::vector<HistoryItem>` の順序として維持。`text` は `std::optional` |
| CLP-119 / CLP-120 / CLP-121 | 783、1126-1128 | JSON のスキーマ（`timestamp` は 10 進文字列、`contentTypes` は無加工） | **C++ API では JSON が無くなる**。`timestampTicks` は `int64_t`。スキーマは DLL ブリッジ側の約束として残る |
| CLP-122 | 1062-1069 | 書き込みオプションは全ての copy API に付く | `WriteOptions` を既定引数にする。`SENSITIVE` は 2 つの `bool` の組み合わせ |
| CLP-123 | 1096 | 複数形式は情報量の多い順に並べる | `std::span<const FormatPayload>` の順序として維持し、Doxygen に書く |
| CLP-125 | 実装 `ClipboardCore::CopyDib` / `PasteDib`（clipboard v2 の行は要再確認） | 画像は DIB のバイト列。エンコードは呼び出し側 | 変更なし |
| CLP-133 | 9、1471 | 公開ヘッダーと Win32 コアは C++17 互換を保つ（当時の制約） | **段階 1 で解消済み**（全構成 C++20）。C++20 を前提にする |
| CLP-137 | 実装 `ClipboardFormats::IsMultiFormatPayloadAllowed` / `ClipboardFormatsTest` | 複数形式の投入は、形式と種別の対応と重複を**配置前に**検証して弾く。`"HTML Format"` は**名前の完全一致**で判定し、`CF_BITMAP` は全種別を拒否、`CF_TEXT` + text は **ANSI に変換**される | `FormatPayload` の `variant` で表し、検証は `Domain` の同じ関数を使う |
| CLP-138 | 実装 `reserveDeferredFormats`（`:687`） | 形式名の**重複は黙って上書き**される（`copyMultipleFormats` がエラーにするのと非対称） | 変更しない。Doxygen に書く |
| CLP-139 | 実装 `IsValidWriteOptions`（`Core.cpp:146`） | `options` は `0x3` 以外のビットが立っていると**書き込み前に** `InvalidParameter` | `WriteOptions` の 2 つの `bool` に対応。ブリッジは今の検査を維持する |
| CLP-140 | 実装 `WriteStringToBuffer` / `WriteBytesToBuffer`（`:41`、`:65`） | 戻り値の単位は wchar_t 数（NUL 含む）とバイト数で異なり、**`0` は常にエラー**。長さ 0 の内容を表さない。`getPreferredClipboardFormat` は該当なしのとき空文字列で `1` を返す | C++ API では値返しになる。ブリッジは今の単位と `0` の意味を維持する |
| CLP-141 | 実装 `hasClipboardFormat`（`:607`） | 問い合わせるだけで `RegisterClipboardFormatW` により**形式を登録してしまう** | 変更しない。副作用を Doxygen に書く |
| CLP-142 | 実装 `MakeDeferredRenderer`（`DeferredProvider.cpp:13`） | 2 相の 2 回目で必要サイズが 1 回目と違うと、その形式を**黙って捨てる**。0 のときと例外のときも捨てる | 内部の 2 相を残すので変わらない（N-2）。C++ API の provider が投げた場合は `Unknown`（N-3） |

### 10.2 Notification

| ID | 出典（notification v3） | 約束 | C++ API での守り方 |
|---|---|---|---|
| NTF-02 / NTF-03 | 663-664、712-714 | コールバックは OS が選んだスレッドで呼ばれる。UI へのマーシャリングはしない。ロックの外で呼ぶ | 変えない（8.3）。Doxygen に明記する |
| NTF-04 / NTF-38 | 270、265-281 | コールバックは登録より前に設定する。初期化フラグは最後に立てる | `Manager::Create` の内部順序として維持する |
| NTF-05 / NTF-40 | 313-318 | `Uninit` は revoke を完了してからコールバックを null にする | `Manager::Close()` とデストラクタの内部順序として維持する |
| NTF-09 / NTF-10 | 483-496 | 起動引数による cold start の配送はちょうど 1 回。入力値は best-effort | 変更なし。**配送は `Manager::Create` の中から呼び出しスレッドで起きる**ことを Doxygen に明記する（Codex 16） |
| NTF-14 | - | 通知側には「ちょうど 1 回」「ドレイン」「キャンセル」の契約が無い | Clipboard の契約を持ち込まない。**テストも書かない**（無い約束を固定しないため） |
| NTF-22 / NTF-24 | 228-232、311 | backend の寿命は Init / Uninit に閉じる。AUMID は backend が持つ | `Manager` が `std::unique_ptr` で持つ形を維持 |
| NTF-27 | 587、648 | unpackaged の `GetAll` は `NotSupported` でバッファに触れない | `Result` のエラー側で返す |
| NTF-31 / NTF-36 | 737-738 | 「引数不正」（7）と「形態的に非対応」（8）を分ける | `InvalidParameter` と `NotSupported` に写す |
| NTF-32 | 596-610 | API ごとに返しうるエラーの集合が決まっている | 11.4 の表として維持し、**実装の分岐から導出する**（推測の範囲を書かない） |
| NTF-33 | 529-543 | 設定値は 5 値 + 失敗。`static_cast` の素通しは禁止 | `enum class NotificationSetting` と明示の `switch` |
| NTF-34 | 338、421 | ペイロードの検証規則（ボタン 5 個まで、`audio.loop` は `duration=long` 必須、`args` と `invokeUri` は排他、`audio.type=uri` は uri 必須、badge は `-6` 未満が不正） | JSON の検証から**構造体の検証**に移る。規則は変えず、`Domain` に移した関数で行う |
| NTF-35 | 129-133 | `DeploymentManager` は unpackaged で呼ばない | **今の実装は元から呼んでいない**（無条件）。したがって OP-07 に引数を足さず、現状の振る舞いをそのまま維持する |
| NTF-39 | 122、252 | `initWinAppSdk` は `initNotificationManager` より前に呼ぶ。**ヘッダーは unpackaged 用と明記している** | `Runtime::Initialize` を unpackaged の前提として Doxygen に書く。packaged では不要（7.5.4）。型では強制しない |
| NTF-60 | 実装 `WindowsNotificationManager::Init`（早期 return の前で `m_callback` を代入） | 2 回目の `init` は冪等に成功し、**活性化のコールバックを差し替える** | `Manager::SetInvokedHandler` で表す（N-10）。ブリッジはこれを使って今の動作を再現する |
| NTF-61 | 実装 同 `Init`（`CoInitializeEx(nullptr, COINIT_MULTITHREADED)`） | COM を **MTA** で初期化し、`RPC_E_CHANGED_MODE` を許容する。`CoUninitialize` は呼ばない | 段階 3 では現状維持（N-8）。mode と副作用を Doxygen と 7.5.4 に書く |
| NTF-62 | 実装 同 `BuildPayload`（`now() + seconds`） | `expiration` は**相対の秒数**であり、絶対時刻ではない。`timestamp` は絶対の Unix 秒、`scheduleNotification` の引数は絶対の Unix ミリ秒で、3 つとも単位が違う | `expiration`（`std::chrono::seconds`）と `timestamp`（`time_point`）で型として分ける |
| NTF-63 | 実装 `Schedule` の 2 経路（tag / group しか使わない） | **`expiration` と `progress` は予約の経路では無視される**。`expiresOnReboot` は unpackaged で無視される | 型としては受け取り、**無視されることを Doxygen に書く**。挙動は変えない |
| NTF-64 | 実装 `BuildFromJson`（既知のキーだけを読む） | **未知のキーは黙って無視される**（エラーにならない） | 厳密な構造体にすると今通っている入力が無言で落ちるため、`NotificationContent::unknownKeys` で保持してブリッジが素通しする |
| NTF-65 | 実装 `setBadge`（`:179`〜`:190`） | badge の `int` は**符号で意味が変わる**（正=件数・上限なし、0=消去、-1〜-6=グリフ表、-6 未満は `INVALID_PARAMETER`） | 段階 3 では `int` のまま維持する。列挙への分割は段階 5 の C ABI で判断する |
| NTF-41 / NTF-42 / NTF-43 | 341-373、544 | `Setting()` は 1 操作につき 1 回。Show の順序。5 分を超える予約は警告ログ | 実装の順序として維持する |
| NTF-44 / NTF-45 | 396-408 | 進捗の sequence number は呼び出し側が渡し、そのまま OS に渡す。bind 名の対応 | `ProgressUpdate::sequenceNumber` として維持 |
| NTF-46 | 375-378 | 予約の取り消しは tag / group の一致で行う（ID ではない） | 変更なし |
| NTF-49 | 288、320-322 | CLSID は AUMID から決定的に生成する | 変更なし |
| NTF-50 | 380-384 | packaged でも `Schedule` だけは classic API を使う | 変更なし |
| NTF-52 | 137-148 | 公開 API のシグネチャは不変で、unpackaged では動作だけが変わる | C++ API では `NotSupported` が型の上でも見える。動作の差は Doxygen に維持 |

### 10.3 Dialog（コードから起こした約束。G-1）

出典はすべて `windows/WindowsLibrary/src/Dialog/WindowsDialogManager.cpp` と同 `.h`。

| ID | 約束 | C++ API での守り方 |
|---|---|---|
| DLG-01 | 単一選択の 3 API（`showFileDialog` / `showSaveFileDialog` / `showFolderDialog`）は**キャンセルでも `TRUE` を返す**。呼び出し側は `pError` で区別する | `DialogError::Canceled` として型で分ける。ブリッジは今の `TRUE` + `pError = -1` を維持する |
| DLG-02 | 複数選択の 2 API は**キャンセルで `0`、エラーで `-1`**。成功時の戻り値は、`showMultiFileDialog` が **N+1**（フォルダ名 + ファイル N 件。1 件だけ選んだ場合は `1` でフルパス）、`showMultiFolderDialog` が**フォルダの件数 N** | `Result<std::vector<std::wstring>>` に展開する。**ブリッジはこの非対称な数え方をそのまま再現する** |
| DLG-03 | 失敗時・キャンセル時は必ず `buffer[0] = L'\0'` を書く | C++ API ではバッファが無くなる。ブリッジ側で維持する |
| DLG-04 | 複数ファイルの結果は `folder\0file1\0file2\0\0`、単一は `fullpath\0` の形式 | `std::vector<std::wstring>` に展開する。ブリッジ側で今の形式を維持する |
| DLG-05 | `ShowFolderDialog` の `L"Select Folder"` は**C++ の既定引数**であり、`extern "C"` の入口は呼び出し側の値をそのまま渡す。`title` が `nullptr` なら `SetTitle` を呼ばず、**OS の既定のタイトル**になる | `FolderRequest::title` を空にした場合は `SetTitle` を呼ばない。v2 で既定値を `L"Select Folder"` としたのは誤りで、撤回する |
| DLG-06 | フォルダ選択の 2 API は**自分で `CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)` を呼び**、`RPC_E_CHANGED_MODE` は許容して続行する。失敗した場合だけ中止する | 変更しない。7.5.4 に書く |
| DLG-07 | フォルダ選択は `FOS_PICKFOLDERS \| FOS_FORCEFILESYSTEM`。複数選択版はこれに **`FOS_ALLOWMULTISELECT`** を加える | 変更しない |
| DLG-08 | エラーは OS の生の値をそのまま `pError` に入れる（`GetLastError` / `CommDlgExtendedError` / `HRESULT`）。キャンセルだけは `-1` | `DialogError` に分類し、生の値は `Failure::systemCode` に残す（11.3） |
| DLG-09 | **6 API すべてがオーナーウィンドウを渡していない**（`ofn.hwndOwner = nullptr`、`pFileOpen->Show(nullptr)`、`MessageBoxW(nullptr, ...)`） | 各 Request の `owner` で指定できるようにする。既定は `nullptr` で今と同じ |
| DLG-10 | すべて同期・モーダルで、呼び出しスレッドを塞ぐ | 変更しない。7.5.4 に明記する |
| DLG-11 | `OFN_*` の組み合わせは API ごとに違う。`showFileDialog` は `OFN_PATHMUSTEXIST \| OFN_FILEMUSTEXIST`、`showMultiFileDialog` はこれに `OFN_ALLOWMULTISELECT \| OFN_EXPLORER` を加える、`showSaveFileDialog` は `OFN_PATHMUSTEXIST \| **OFN_OVERWRITEPROMPT**` | `FileRequest::fileMustExist` と `SaveFileRequest::overwritePrompt` で表す。**上書き確認は利用者に見える動作**なので既定を `true` にする |
| DLG-12 | フィルターが `nullptr` のときの既定は `L"All Files\0*.*\0"` | `filters` が空のときに同じものを使う |
| DLG-13 | ファイル系の 3 API には**タイトルの引数が無い**（フォルダ系にはある） | `FileRequest::title` / `SaveFileRequest::title` は C++ API の新機能。ブリッジは常に空を渡すため、C ABI の動作は変わらない |
| DLG-14 | `showAlertDialog` は `buttons \| icon \| defbutton \| options` を OR して `MessageBoxW` の `type` にする。値の検証はしていない | 列挙で表せない組み合わせは `AlertRequest::extraFlags` で素通しする（N-9） |
| DLG-15 | **`showFileDialog` は成功時に `*pError` を 0 にしない**（キャンセルと失敗の経路でしか設定しない）。既存の不具合 | 段階 3 では**そのまま再現する**。修正は別の作業（14 章 RK-12） |
| DLG-16 | `showMultiFolderDialog` は成功時と溢れ時に `IFileOpenDialog::Release()` を呼んでいない。また成功して `count == 0` のときの戻り値がキャンセルと同じ `0`（`*pError` でのみ区別できる） | 同上。C++ API では空の `vector` と `Canceled` で区別できる |
| DLG-17 | `buffer == nullptr` を検査せず即座に `ZeroMemory` する。バッファ不足でも**必要サイズを返さない** | C++ API ではバッファが無くなる。ブリッジ側は今の振る舞いを維持する |
| DLG-18 | 6 つとも**オーナー HWND・初期ディレクトリ・既定ファイル名・フィルター番号を受け取らない**（`nFilterIndex` は 1 固定） | `owner` だけ C++ API で受け取れるようにする。ほかは今の範囲のまま |

### 10.4 新規設計判断（既存の約束を変える点）

| # | 変える点 | 理由 | 影響 |
|---|---|---|---|
| N-1 | `Session` / `Manager` / `Runtime` をムーブのみの単独所有にする | RAII にするため | C ABI の冪等な init は DLL ブリッジが 1 個保持して再現する。C++ API の 2 個目の `Create` は `NotSupported` |
| N-2 | 遅延レンダリングの provider を C++ API の表面では 1 回呼びにする | C++ ではサイズを先に問い合わせる必要が無い | **内部の 2 相は残す**ので、既存のサイズ整合の検査とそのテスト 2 件は変わらない |
| N-3 | provider の「例外を投げてはならない」を緩和する | `std::function` では投げうるため | 投げた場合は捕捉して `ClipboardError::Unknown` にし、ログに残す |
| N-4 | 履歴のペイロードが JSON から構造体になる | C++ API では JSON を使わないため | JSON のスキーマは DLL ブリッジの約束として残る |
| N-5 | **`Session` の終了は `Close()` の成功を必須とし、デストラクタは放棄する** | 「ポンプが今後回るか」を判定する手段が無く、デストラクタで非同期の後始末を約束できないため（S-4） | `Close()` せずに破棄すると資源が残り、再作成もできない。デバッグ時は assert、リリース時はログ。7.4.1 と 7.5.4、RK-03 |
| N-6 | （欠番）v1 の「フラグのコールバックを 2 つに分ける」は事実誤認だったため削除 | 今の登録は既に 3 口に分かれている | 無し |
| N-7 | **Windows App SDK のブートストラップを `Runtime` トークンにする**（段階 3 で行う） | `InitializeRuntime` は段階 3 で公開 API になるため、後始末の有無を段階 5 に送ると公開後の変更になる（S-7） | C++ API の利用者は `Runtime` の破棄で `MddBootstrapShutdown` が呼ばれる。DLL ブリッジはプロセスに 1 つ保持し、C ABI の動作（後始末しない）は変えない。`Runtime` が要るのは unpackaged のときだけ |
| N-8 | 通知の COM は**段階 3 では現状維持**（MTA で初期化し、解除しない） | 対になる `CoUninitialize` を足すと `uninitNotificationManager` が呼び出し側のスレッドの COM を落とすため、「動作を変えない」に反する（S-6） | mode・`RPC_E_CHANGED_MODE` の許容・`S_FALSE` の扱い・Clipboard と同居させる場合の注意を Doxygen と 7.5.4 に書く。釣り合いは段階 5 の課題 |
| N-9 | Win32 のフラグ語と生のフィルター文字列に**逃げ道**を用意する | 列挙だけでは今の C ABI が受け付ける入力を表せず、ブリッジが欠落するため（S-3） | `AlertRequest::extraFlags` を公開し、ブリッジは `MB_*` をそのまま渡す。フィルター文字列は、ブリッジが `Data` 層の内部入口を直接呼んで解析・再構成を経由しない |
| N-10 | `Manager::SetInvokedHandler` を足す | 今の 2 回目の `init` はコールバックを差し替えており、`Create` だけでは再現できない（S-5） | C++ API の利用者もハンドラを差し替えられる。10.2 の約束として記録する |

## 11. ドメインエラー一覧

エラーの番号の空間は機能ごとに分かれており、**同じ番号が別の意味を持つ**（8 は Clipboard では `OutOfMemory`、Notification では `NotSupported`）。C++ API でも 3 つの `enum class` に分け、統合しない。

### 11.1 `ClipboardError`（既存の 20 定数をそのまま引き継ぐ）

| 値 | C++ API | 今の定数 | 主な発生源 |
|---|---|---|---|
| 0 | `None` | `CLIPBOARD_ERROR_NONE` | 成功（`Failure` には現れない。C ABI 互換のために残す） |
| 1 | `InvalidParameter` | `CLIPBOARD_ERROR_INVALID_PARAMETER` | 引数が null / 空、埋め込み NUL、未知または完了済みのリクエスト ID |
| 2 | `NotInitialized` | `CLIPBOARD_ERROR_NOT_INITIALIZED` | `Session` を作る前、または閉じた後のデータ系 API |
| 3 | `Busy` | `CLIPBOARD_ERROR_BUSY` | `OpenClipboard` が再試行の上限まで失敗。`Close()` で lifecycle / coordinator が破棄可能でない |
| 4 | `Empty` | `CLIPBOARD_ERROR_EMPTY` | クリップボードまたは履歴が空 |
| 5 | `FormatUnavailable` | `CLIPBOARD_ERROR_FORMAT_UNAVAILABLE` | 要求した形式が無い |
| 6 | `InvalidData` | `CLIPBOARD_ERROR_INVALID_DATA` | 境界検証の失敗（終端、サイズ、オフセット、DIB の構造） |
| 7 | `BufferTooSmall` | `CLIPBOARD_ERROR_BUFFER_TOO_SMALL` | **C++ API では発生しない**。DLL ブリッジ用に残す |
| 8 | `OutOfMemory` | `CLIPBOARD_ERROR_OUT_OF_MEMORY` | `GlobalAlloc` / `GlobalLock` の失敗、`std::bad_alloc`、コルーチンの確保失敗 |
| 9 | `AccessDenied` | `CLIPBOARD_ERROR_ACCESS_DENIED` | WinRT の `AccessDenied`、`E_ACCESSDENIED` |
| 10 | `HistoryDisabled` | `CLIPBOARD_ERROR_HISTORY_DISABLED` | `IsHistoryEnabled()` が false |
| 11 | `ItemDeleted` | `CLIPBOARD_ERROR_ITEM_DELETED` | WinRT の `ItemDeleted` |
| 12 | `MonitorRegisterFailed` | `CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED` | リスナー／イベントトークンの登録・解除の失敗。`Close()` で解除できていない場合を含む |
| 13 | `PartialState` | `CLIPBOARD_ERROR_PARTIAL_STATE` | 配置の失敗後、巻き戻しも失敗 |
| 14 | `WrongThread` | `CLIPBOARD_ERROR_WRONG_THREAD` | UI スレッド限定の API を他スレッドから呼んだ。別スレッドからの 2 回目の `Create` |
| 15 | `Canceled` | `CLIPBOARD_ERROR_CANCELED` | `CancelRequest`、ドレインによる失効。**`Close()` のドレイン未完了**もこれ |
| 16 | `NotSupported` | `CLIPBOARD_ERROR_NOT_SUPPORTED` | Windows に無い操作。**同じスレッドからの 2 個目の `Session::Create`**（N-1） |
| 17 | `NotForeground` | `CLIPBOARD_ERROR_NOT_FOREGROUND` | 自プロセスが前面でない（コールバックでのみ返る） |
| 18 | `WrongApartment` | `CLIPBOARD_ERROR_WRONG_APARTMENT` | `CoGetApartmentType` が STA 以外 |
| 19 | `Unknown` | `CLIPBOARD_ERROR_UNKNOWN` | 上記以外。**`DeleteItemFromHistory` / `ClearHistory` の `false`**（CLP-90）、`CancelRequest` の投稿失敗、provider が投げた例外（N-3）を含む。生の値は必ずログに残す（CLP-87） |

### 11.2 `NotificationError`（既存の 9 定数）

| 値 | C++ API | 今の定数 | 主な発生源 |
|---|---|---|---|
| 0 | `None` | `NOTIFICATION_SUCCESS` | 成功 |
| 1 | `NotInitialized` | `NOTIFICATION_ERROR_NOT_INITIALIZED` | `Manager` を作る前、または閉じた後 |
| 2 | `Disabled` | `NOTIFICATION_ERROR_DISABLED` | `Setting()` が `Enabled` 以外 |
| 3 | `InvalidPayload` | `NOTIFICATION_ERROR_INVALID_PAYLOAD` | 検証規則（NTF-34）の違反 |
| 4 | `ProgressNotFound` | `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` | 進捗の更新先が無い、または sequence が古い |
| 5 | `HResultFailure` | `NOTIFICATION_ERROR_HRESULT_FAILURE` | ショートカット生成、`CoRegisterClassObject`、ランタイムの初期化の失敗 |
| 6 | `BadgeFailed` | `NOTIFICATION_ERROR_BADGE_FAILED` | バッジの設定の失敗 |
| 7 | `InvalidParameter` | `NOTIFICATION_ERROR_INVALID_PARAMETER` | 引数不正（badge が -6 未満、unpackaged で `displayName` / `iconUri` が無い） |
| 8 | `NotSupported` | `NOTIFICATION_ERROR_NOT_SUPPORTED` | unpackaged の `RemoveById` / `GetAll` / `SetBadge`。**2 個目の `Manager::Create`**（N-1） |

### 11.3 `DialogError`（この設計で新設。G-1）

| 値 | C++ API | 今の表し方 |
|---|---|---|
| 0 | `None` | 成功 |
| 1 | `InvalidParameter` | 引数が null、バッファのサイズが 0 |
| 2 | `Canceled` | `*pError = -1`（`0xFFFFFFFF`）、または複数選択の戻り値 `0`（DLG-01、DLG-02） |
| 3 | `BufferTooSmall` | `ERROR_INSUFFICIENT_BUFFER`。**C++ API では発生しない**が、ブリッジ用に番号を確保する |
| 4 | `SystemError` | `GetLastError()` / `CommDlgExtendedError()` / 失敗した `HRESULT`（`systemCode` に生の値を残す） |
| 5 | `Unknown` | 上記に分類できないもの |

### 11.4 API ごとに返しうるエラー

**実装の分岐から導出する**（NTF-32、Codex 12 の反映）。推測で範囲を広げない。T-13 の機械照合でヘッダーの `@retval` と突き合わせる。

| OP | 返しうるエラー |
|---|---|
| OP-01 | `InvalidParameter`、`SystemError`、`Unknown` |
| OP-02〜OP-06 | `InvalidParameter`、`Canceled`、`SystemError`、`Unknown` |
| OP-07 | `HResultFailure` |
| OP-08 | `InvalidParameter`（unpackaged で `displayName` / `iconUri` が無い）、`HResultFailure`（`CoInitializeEx` の失敗、ショートカット生成、`CoRegisterClassObject`）、`NotSupported`（2 個目） |
| OP-09 | 無し（戻り値を持たない） |
| OP-10 / OP-11 | `NotInitialized`、`Disabled`、`InvalidPayload`（JSON の解析失敗。**C ABI でのみ起きる**。C++ API は JSON を受け取らない）、**`InvalidParameter`（意味の検証の失敗。今の実装はこちらを返す）**、`HResultFailure` |
| OP-12 | `NotInitialized`、`HResultFailure` |
| OP-13 | `NotInitialized`、`ProgressNotFound`、`HResultFailure` |
| OP-14 | `NotInitialized`、`BadgeFailed`、`InvalidParameter`、unpackaged では `NotSupported` |
| OP-15 | `NotInitialized`、`HResultFailure`、unpackaged では `NotSupported` |
| OP-16 / OP-17 | `NotInitialized`、`HResultFailure` |
| OP-18 | `NotInitialized`、`HResultFailure`、unpackaged では `NotSupported` |
| OP-19 | `HResultFailure`（今の `-1` に対応）、`NotInitialized`（閉じた・ムーブ済みの `Manager`。T-14 で所有権を見るようにした結果） |
| OP-20 | `NotInitialized`、`HResultFailure` |
| OP-21 | `InvalidParameter`、`WrongApartment`、`MonitorRegisterFailed`、`OutOfMemory`、`Unknown`（配送用ウィンドウの生成失敗、backend 生成時の例外）、`NotSupported`（同スレッドの 2 個目）、`WrongThread`（別スレッドの 2 個目） |
| OP-22 | `NotInitialized`、`WrongThread`、`MonitorRegisterFailed` |
| OP-23 | `WrongThread`、`MonitorRegisterFailed`、`Canceled`、`Busy`、`PartialState`（回復の失敗） |
| OP-24 | 無し（`bool` を返す） |
| OP-25〜OP-39 | `NotInitialized`、`InvalidParameter`、`Busy`、`Empty`、`FormatUnavailable`、`InvalidData`、`OutOfMemory`、`PartialState`（OP-35）、`Unknown` |
| OP-40 / OP-41 | `NotInitialized`、`WrongThread`、`InvalidParameter`、`PartialState`、`Unknown` |
| OP-42〜OP-46（受付） | `NotInitialized`、`InvalidParameter`、`OutOfMemory`、`Unknown`（投稿の失敗） |
| OP-42〜OP-46（コールバック） | `NotForeground`、`HistoryDisabled`、`AccessDenied`、`ItemDeleted`、`Canceled`、`Empty`、`OutOfMemory`、`Unknown` |
| OP-47 | `InvalidParameter`（未知・完了済みの ID）、`Unknown`（投稿の失敗）、`NotInitialized`（閉じた・ムーブ済みの `Session`） |

## 12. テスト設計

### 12.1 単体テスト（`WindowsLibraryTest` / CppUnitTest）

既存の 106 件（Clipboard 85、Notification 21。6.5）は内部クラスを対象にしており、内部クラスが残るため原則そのまま通る。遅延レンダリングのサイズ整合の 2 件は、v1 の案（2 相を畳む）では変更が必要だったが、N-2 で内部の 2 相を残すため**変更しなくてよい**。追加するのは次の 4 群。

| 群 | 対象 | 内容 |
|---|---|---|
| U-A | `Result<T, E>` / `Unexpected<E>` / `Failure<Code>` | 値とエラーの取り出し、`value_or`、ムーブ、値を返さない形、コピー・ムーブ代入、`T == E` の場合。**機能ごとの別名が別の型になること**（`static_assert`） |
| U-B | 型の変換 | `WriteOptions` とビットフラグ、`NotificationContent` と今の JSON（**キーとフィールドの対応表を持ち、T-17 の入力一覧の全キーを網羅する**）、`HistoryItem` と今の JSON スキーマ、`FormatPayload` の種別と並び、Dialog の列挙と `MB_*` / `OFN_*`。**同じ入力から C ABI と C++ API の両方を作って結果を比較する** |
| U-C | Dialog の新しい層 | `DialogError` への分類（`CommDlgExtendedError` → `SystemError`、キャンセル → `Canceled`）。ダイアログは出さず失敗注入で確かめる |
| U-D | ヘッダーの自己完結 | 5 つの公開ヘッダーと **`src/**/*Internal.h`** のそれぞれを、翻訳単位の最初で単独に include してコンパイルが通ること。`<windows.h>` を先に include した場合としない場合の両方。**内部ヘッダーを対象に含めるのは、T-03 で `WindowsDialogManagerInternal.h` が `<commdlg.h>` を includer 任せにしていたため**。**このテストはプリコンパイル済みヘッダーを使ってはならない**（MSVC は `#include "pch.h"` より前の内容を無視するため、PCH のままでは検査が空回りする。T-04 で実測） |

- 検査の書き方（common.md）に従い、「公開ヘッダーの全操作が 9 章の表に載っていること」を、ヘッダーの宣言一覧と設計書の表の**両辺から導出して**比較する（T-13）
- 空回り防止の下限は「`include/NativeToolkit/` の 3 つの機能ヘッダーで 47 件以上」とする

### 12.2 契約テスト

| ID | 確かめること | 方法 |
|---|---|---|
| C-1 | CLP-06 受付後はちょうど 1 回 | 偽の backend で受付 → 完了。呼び出し回数を数える |
| C-2 | CLP-06 受付前の失敗は 0 回 | 引数不正で受付を失敗させ、コールバックが呼ばれないこと |
| C-3 | CLP-02 非 inline | 受付を呼んだスタックの中でコールバックが呼ばれないこと |
| C-4 | CLP-16 キャンセルは論理 | キャンセル後に backend が完了しても 2 回目が来ないこと |
| C-5 | 7.4.1 `Close()` の 5 通り | ドレイン未完了で `Canceled`、トークン未解除で `MonitorRegisterFailed`、in-flight で `Busy`、非オーナーで `WrongThread` を返し分けること |
| C-6 | 7.4.1 `Close()` の冪等性 | 閉じ終わった後の `Close()` が成功を返すこと（今の `TRUE` + `NONE` と同じ） |
| C-7 | N-1 二重 `Create` | 同じスレッドから `NotSupported`、別スレッドから `WrongThread` |
| C-8 | N-5 デストラクタ | `Close()` 未成功のまま破棄した場合に、デバッグビルドで assert し、資源を解放せず、以後の `Create` が `NotSupported` を返し続けること（非同期の後始末を行わないこと） |
| C-9 | NTF-14 通知に 1 回の契約が無いこと | **テストを書かない**（無い約束を固定しないため） |
| C-10 | CLP-86 エラーの集合 | `enum class ClipboardError` の 20 値が既存の `#define` と 1 対 1 で一致すること。両辺をソースから導出する |
| C-11 | 11.4 の表 | ヘッダーの `@retval` と 11.4 の表が一致すること |
| C-12 | 7.4.3 `wstring_view` | NUL 終端でない部分文字列を渡しても、末尾を越えて読まないこと。埋め込み NUL が `InvalidParameter` になること |

### 12.3 UI テスト

- 段階 3 では UI テストを変更しない。段階 0d の記録（94 件）と同じ結果になることを確かめる
- T-14 で C ABI を C++ API の上に載せ替えるため、**UI テストが段階 3 の回帰の主な防波堤になる**
- ただし UI テストはサンプルの表示を見るもので、**`pError` の値をすべて見ているわけではない**。エラーの写像は U-B と C-10、C-11 で担保する

### 12.4 computer use

- CU-01（画像付き通知の画像）を段階 3 の終わりに 1 回実行する。`NotificationContent` への置き換えで画像の経路に触れるため省略しない

### 12.5 手動確認

- 既存の設計書が未検証としている項目は、段階 3 で新たに検証しない（書き直しで変わらないため）
- 新しい経路として、**`Session` のデストラクタ任せの終了**（N-5）と、**`/MT` でのリンク**（7.5.1）を 1 回ずつ手で確かめる

## 13. 実装タスク分解

合計見積: 約 20.0 日

**T-03 は設計を確定させるためのスパイクであり、これが終わるまで 7.5 の配布構成は暫定とする**（S-8）。結果によっては 7.5 と 15.3 を段階 3 のうちに書き換える。

| ID | 内容 | 見積 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | `WindowsLibraryExample` を `stdcpp20` にし、段階 0d と同じ結果で通ることを確かめる | 0.5日 | 無し | `scripts/test_windows.ps1` が baseline と一致 | C++/WinRT のビルドが壊れていないか |
| T-02 | 成果物の分割（7.6）。`extern "C"` をブリッジ用の `.cpp` へ移して DLL プロジェクトにだけ登録し、`WINDOWSLIBRARY_EXPORTS` を DLL 限定にする。`.def` に 52 個を列挙し、`__declspec(dllexport)` を落とす。`WindowsLibraryCore`（静的）を作る | 1.5日 | T-01 | **分割前後の `dumpbin /exports` の差分が 0 件**。`WindowsLibraryTest` の対象範囲が今と同じ（変わる場合は意図を記録）。単体テストと UI テストが baseline と一致 | コアのヘッダーに `dllimport` / `dllexport` が残っていないか。`Common` の 5 関数が落ちていないか |
| T-03 | **ビルドのスパイク（ブロッキング）**。`/MT` の 2 構成、配布構成の `/GL` 無効化、`detect_mismatch`、サンプルとテストの include パス、`build_windows_library_dll.ps1` の `Project` / `Headers`、`.props` / `.targets` の骨組み | 1.5日 | T-02 | `/MD` と `/MT` の両方でリンクできるか**結論が出ている**。伝播が要るライブラリと `WINRT_*` の一覧が実測で確定。**サンプル（WinUI 3 / MSIX）で `.props` が効くことを確認** | `/MT` が成立しない場合に 7.5 と DoD を書き換えたか |
| T-04 | `Types.h` / `Error.h`（`Result<T, E>`、`Unexpected<E>`、`Failure<Code>`、条件付きの特殊メンバ、3 つの `enum class`、機能ごとの別名、`WindowHandle`）。U-A、U-D | 1.5日 | T-02 | U-A と U-D が通る。`Result<Session>` がムーブのみになる | 活性メンバの入れ替えの例外安全。無検査アクセサの `noexcept`。大域の `HWND__` |
| T-05 | Dialog を `src/Dialog/{Application,Data,Domain}` に分け、`.cpp` 内の singleton を `Data` の実装クラスへ出す。ブリッジ向けの内部入口（生のフラグとフィルター文字列を受ける）を用意する | 1.0日 | T-04 | 既存の C ABI の動作が変わらない | DLG-01〜DLG-14 が保たれているか |
| T-06 | Dialog の C++ API（OP-01〜OP-06）、列挙と `MB_*` / `OFN_*` の写像、`FileFilter` の展開。U-C | 1.0日 | T-05 | 6 関数が `Result` を返す。U-C が通る | キャンセルが `Canceled` か。`extraFlags` の素通し。`overwritePrompt` の既定 |
| T-07 | Notification に `Domain` を作り、検証（NTF-34）と組み立てを移す。JSON 依存を切る | 1.5日 | T-04 | 検証の規則が JSON でも構造体でも同じ結果になる | 規則が 1 つの実装に集約されているか |
| T-08 | Notification の型（8.2 の全項目）、`Runtime` トークン（N-7）、`Manager`（ムーブのみ、`SetInvokedHandler`、コールバック境界の例外捕捉）、C++ API（OP-07〜OP-20） | 1.5日 | T-07 | 14 関数 + `SetInvokedHandler` が動く。Init / Uninit の順序が変わらない | `scenario` / `timestamp` / 音声のプリセット / 相対の有効期限が落ちていないか。COM を現状維持にしたか |
| T-09 | Clipboard の `Session`（ムーブのみ、`Close()` の 5 通り、冪等性、放棄のデストラクタ）。C-5〜C-8 | 1.5日 | T-04 | C-5〜C-8 が通る。既存の lifecycle のテストが通る | エラーの返し分けが今と同じか。デストラクタが非同期の後始末をしていないか |
| T-10 | Clipboard の同期 Win32 コアの C++ API（OP-25〜OP-39）。U-B、C-12 | 1.5日 | T-09 | 15 関数が値を返す。U-B と C-12 が通る | `wstring_view` のコピーと埋め込み NUL の検査。`FormatPayload` の variant |
| T-11 | 遅延レンダリング（OP-40、OP-41）と provider のアダプタ（N-2、N-3）。形式名と provider の深いコピー | 1.0日 | T-10 | 3 状態のテストが通る。既存の 2 相のテストが変わらず通る | 内部の 2 相が残っているか |
| T-12 | 履歴（OP-42〜OP-47）。`RequestId` をコールバックに渡す。C-1〜C-4 | 1.5日 | T-09 | C-1〜C-4 が通る | 完了の配送経路に手を入れていないか |
| T-13 | 機械照合を `scripts/` に追加。47 操作の両辺からの導出、C-10、C-11、**10 章の引用行の照合**（引用行の前後 3 行に約束の語が現れること） | 1.0日 | T-06, T-08, T-12 | 照合が通り、壊すと落ちることを確認済み | 検査が主題を推移的に閉じているか |
| T-14 | 既存の C ABI 52 関数を、DLL ブリッジとして C++ API（と Dialog の内部入口）の上に載せ替える | 1.5日 | T-06, T-08, T-11, T-12, T-17 | `dumpbin /exports` の差分 0 件。**T-17 の入力一覧の全項目が同じ結果になる**。単体テストと UI テストが baseline と一致 | `pError` が今と同じか（`uninit` の 5 通り、`cancel` の 2 通り、Dialog の戻り値の数え方） |
| T-15 | 回帰の確認: `scripts/test_windows.ps1` と CU-01 | 0.5日 | T-13, T-14 | 3 層すべてが段階 0d の記録と一致 | 記録との差分が 0 件か |
| T-16 | 公開ヘッダーの Doxygen（`@brief` / `@param` / `@return` / `@retval`、10 章で維持する注意書き、7.5.4 の前提） | 1.0日 | T-14 | 全公開宣言にコメントがある | スレッド・再入・寿命・`Close()` 必須が書かれているか |
| T-17 | `designs/2026-09-20-windows-architecture-c-abi-input-inventory.md`（**作成済み**）を、分割後のコードに対して検証し直し、T-14 の突き合わせに使える形に保つ | 0.5日 | T-02 | 一覧の全項目が分割後も同じ結果になる | 一覧がサンプルの使う範囲に縮んでいないか |

### 13.1 先行と後続

- 先行（基盤）: T-01、T-02、T-03（スパイク）、T-04、T-17
- 機能ごとに独立して進められる: Dialog（T-05、T-06）、Notification（T-07、T-08）、Clipboard（T-09〜T-12）
- 後続（統合）: T-13、T-14、T-15、T-16
- 段階 4（サンプルの移行）は T-16 の後に始める

## 14. リスクと緩和策

| ID | リスク | 影響 | 緩和策 |
|---|---|---|---|
| RK-01 | T-14 の載せ替えで C ABI の動作が変わる | 段階 3 の「動作を変えない」前提が崩れる | **T-17 の入力一覧**と突き合わせる。UI テストと baseline も併用する。変換のコードは新しく書かず今のものを移す |
| RK-02 | `WindowsLibraryExample` の C++20 化で WinUI 3 / C++/WinRT のビルドが壊れる | 段階 3 の検証ができない | T-01 を最初に単独で行い、壊れたらサンプルの設定だけ戻して切り分ける |
| RK-03 | `Close()` を呼ばずに `Session` を破棄する利用者が出る | 資源が残り、再作成もできない | Doxygen・7.5.4・サンプル（段階 4）で `Close()` を正規の手段として示す。デバッグ時の assert で早期に気づかせる |
| RK-04 | Notification のコールバックが OS のスレッドで来ることを、利用者が UI スレッドだと誤解する | 利用者側のクラッシュ | Doxygen に明記し、cold start の例外も書く。段階 4 のサンプルでマーシャリングの例を残す |
| RK-05 | 静的ライブラリにしたときの依存の伝播が想定より広い | 利用者のリンクが通らない | T-03 のスパイクで実測し、`.props` / `.targets` に落とす。サンプルで実証する |
| RK-06 | 自前の `Result` と `std::expected` の差が将来の移行の負担になる | C++23 への移行が機械的に済まない | 差を 7.2 の表に明記し、「差し替え可能」と謳わない |
| RK-07 | 10 章の約束が設計書ベースで、実装が設計書と食い違っている可能性がある | 守るべき約束を取り違える | 契約テストは**今の実装の振る舞い**に対して書く。引用行の照合（T-13）で劣化を防ぐ |
| RK-08 | （解消）Windows App SDK が `/MT` と組めない | - | T-03 で `/MT` のコンパイル・リンク・実行を確認した。4 種の配布は成立する |
| RK-09 | COM の初期化と解除の不均衡を段階 3 で残す（N-8） | 段階 5 まで解消しない | 現状維持であり悪化はしない。Doxygen で利用者に前提を示す。段階 5 の申し送りに記録する |
| RK-10 | cold start の活性化が `Manager::Create` の中から配送される | 利用者のハンドラが `Manager` を受け取る前に呼ばれる | Doxygen に明記し、ハンドラが `Manager` を前提にしない書き方をサンプルで示す |
| RK-11 | `AlertRequest::extraFlags` の逃げ道が乱用される | 型で表した意味が骨抜きになる | 逃げ道はブリッジの互換用であることを Doxygen に書き、サンプルでは使わない。段階 5 で必要な `MB_*` を列挙に昇格させる |
| RK-12 | 既存の不具合（DLG-15 の `pError` 未設定、DLG-16 の `Release` 漏れ）をそのまま再現する | 不具合が段階 3 の後も残る | 段階 3 は動作を変えない段階なので再現が正しい。**別チケットとして切り出し**、段階 5 か独立の修正で直す |

## 15. Definition of Done

### 15.1 機能

- [ ] `include/NativeToolkit/` の 5 ファイルがあり、47 操作すべての C++ API がある
- [ ] 8.1 の対応表の全 47 行が実装され、9 章の表と操作の集合が一致する
- [ ] 8.2 の型がすべて宣言されている（`Manager` / `Session` / `Runtime` を含む）
- [ ] 公開ヘッダーが `<windows.h>` と WinRT の型を露出しておらず、単独 include でコンパイルできる（U-D）
- [ ] 3 つの `enum class` の値が既存の定数と 1 対 1 で一致する
- [ ] `Result` が機能ごとに別の型で、ムーブのみの `T` を入れられる
- [ ] C ABI 52 関数が DLL ブリッジとして載り、**`dumpbin /exports` の差分が 0 件**で、T-17 の入力一覧の全項目が同じ結果になる

### 15.2 品質

- [ ] 既存の単体テスト 106 件が通る
- [ ] 契約テスト C-1〜C-8、C-10〜C-12 が通る（C-9 は意図的に書かない）
- [ ] `scripts/test_windows.ps1` の結果が `scripts/test_windows.baseline.json` と一致する
- [ ] CU-01 が合格で、証拠のスクリーンショットが残っている
- [ ] 実装のシグネチャ、完了スレッド、キャンセルの契約が 9 章・10 章の表と一致する
- [ ] 公開ヘッダーの全宣言に Doxygen があり、スレッド・再入・寿命・`Close()` 必須が書かれている
- [ ] 機械照合（T-13）が通り、検査を壊して落ちることを確かめてある。**10 章の引用行の照合を含む**

### 15.3 構成

- [ ] `WindowsLibraryCore`（静的）と `WindowsLibrary`（DLL）に分かれ、依存の向きが Core ← DLL である
- [ ] `extern "C"` の関数が DLL 側の翻訳単位にのみ存在し、コアのヘッダーに `dllimport` / `dllexport` が無い
- [ ] `.def` に 52 個が列挙され、`__declspec(dllexport)` に依存する公開関数が無い
- [ ] 3 プロジェクトの C++ 標準が `stdcpp20` で揃っている
- [x] 配布構成で `/GL` が無効になっている（Core の Release 2 構成）
- [x] T-03 の結論が 7.5 に反映されている（`/MT` は可、伝播するライブラリ 8 + 1、`WINRT_*` は `detect_mismatch` で検査）
- [ ] `.vcxproj` と `.vcxproj.filters` の対応が 1 対 1 である
- [ ] `build_windows_library_dll.ps1` が `include/NativeToolkit` の 5 ヘッダーを含む
- [ ] `windows.md` の変更案（5.2）が段階 5 の課題として記録されている
