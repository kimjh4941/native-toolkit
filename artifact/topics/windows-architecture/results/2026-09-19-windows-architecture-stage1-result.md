# 段階 1 結果: MFC / COM の雛形の削除と C++20 への統一

- 実施日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 1（1.4、1.7、D-2）
- ブランチ: `feature/NTKIT-16`
- 設計書: 書かない（README 5.1）

## 1. 変更したこと

### 1.1 削除したもの（`windows/WindowsLibrary/`）

| ファイル | 中身 | 使われていなかった理由 |
|---|---|---|
| `WindowsLibrary.cpp` / `WindowsLibrary.h` | `CWindowsLibraryApp`（`CWinApp`）。DLL の読み込み時に `AfxSocketInit` と `COleObjectFactory::RegisterAll`。COM の登録用の関数 4 つ | ライブラリはソケットを使わない。COM のクラスは 1 つも無い |
| `framework.h` | MFC のヘッダー一式（OLE、ODBC、DAO、ソケットを含む） | `pch.h` から読み込まれていただけ |
| `WindowsLibrary.idl` / `WindowsLibrary_h.h` | COM のタイプライブラリ（中身が空） | — |
| `Resource.h` / `res/WindowsLibrary.rc2` | `IDD_DIALOG` と `IDP_SOCKETS_INIT_FAILED`。テンプレートのコメント | 上の 2 つ専用 |

### 1.2 書き換えたもの

| ファイル | 変更 |
|---|---|
| `pch.h` | `framework.h`（MFC）の代わりに `targetver.h` と `windows.h` を読み込む |
| `WindowsDialogManager.cpp` | 使われていなかった `CDialogEx m_dialogEx` と、コンストラクターの `CWnd*` を削除した |
| `WindowsLibrary.def` | COM の登録用の 4 行（`DllCanUnloadNow` など）を削除した |
| `WindowsLibrary.rc` | バージョン情報（`VERSIONINFO`）だけを残した。`afxres.h` の代わりに `winres.h` を読み込む。文字コード（UTF-16LE）は変えていない（`build_windows_library_dll.ps1` がリリース時に版を書き込むため） |
| `WindowsLibrary.vcxproj` / `.filters` | `UseOfMfc`、`Midl`、削除したファイルの項目を外した。`Keyword` を `Win32Proj` にした。`LanguageStandard` を全構成で `stdcpp20` にし、`WindowsClipboardHistoryWinRt.cpp` だけの C++20 の上書きと、プリコンパイル済みヘッダーを使わない設定を外した |
| `WindowsLibraryTest.vcxproj` | `UseOfMfc` を外し、`stdcpp20` にした |
| コメント（5 ファイル） | MFC と「C++17 の翻訳単位」への言及を今の状態に合わせた |

### 1.3 C++20 にして出たエラーの修正

| ファイル | エラー | 原因 | 修正 |
|---|---|---|---|
| `WindowsClipboardFormats.cpp` | `DROPFILES` が定義されていない | MFC のヘッダーが `shlobj.h` を間接的に読み込んでいた | `<shlobj_core.h>` を明示的に読み込む（`WindowsClipboardCore.cpp` と同じ） |
| `WindowsNotificationManager.cpp`（2 か所） | `AppNotificationManager` の一時オブジェクトを `auto&` で受けられない（C2440） | C++20 で既定になる `/permissive-` が、非 const 参照を一時オブジェクトに束縛する MSVC の拡張を認めない | `auto` で受ける。WinRT のオブジェクトは参照カウント付きのハンドルなので、同じ `AppNotificationManager` を指し、動作は変わらない |

### 1.4 スクリプトの修正（`scripts/test_windows.ps1`）

1 回目の実行で、サンプルのソリューションのビルドが `UnityWindowsPlugin` で失敗した（MSB8011「出力の登録に失敗しました」）。

- `UnityWindowsPlugin` は `WindowsLibrary` を参照しているので、ライブラリを変えるとリンクし直される
- `UnityWindowsPlugin` にはビルドの後に regsvr32 で COM に登録する設定（`RegisterOutput=true`）があり、管理者権限が無いと失敗する
- 段階 0d では `UnityWindowsPlugin` が最新だったので登録が動かず、表に出ていなかった

サンプルもテストも `UnityWindowsPlugin` を使わないので、スクリプトがソリューションのうち `WindowsLibraryExample` とその参照先だけをビルドするようにした。`UnityWindowsPlugin` は段階 5 で削除する。

## 2. 確かめたこと

| 確認 | 結果 |
|---|---|
| `test_windows.ps1`（全件） | **基準と同じ**（`Same outcomes as the baseline of 2026-09-19 14:51`）。ユニットテスト 106 件成功、UI テスト 93 件成功、1 件（履歴の `Clear`）は既定どおり実行されない。OS の設定はすべて戻った |
| ビルドの警告 | 変更の前後で同じ（`MSB3106` 1、`C4819` 24、`C4190` 17。Debug のリビルド）。変更の前は、変更を一時的に退避してビルドして数えた |
| DLL の依存先（Release） | `mfc140u.dll` が無くなった。依存先は Windows の DLL、VC ランタイム、`Microsoft.WindowsAppRuntime.Bootstrap.dll` だけ |
| DLL の公開関数（Release） | 52 個。`.def` の 39 個がすべて公開されている。消えたのは COM の登録用の 4 つだけ |
| CU-01 | **実施しない**（利用者の判断。2026-09-19） |

### 2.1 UI テストの所要時間について

UI テストの所要時間は 14 分 36 秒で、基準（8 分 17 秒）より長かった。遅くなったのは一部のテストではなく全体（テストの時間の合計 497 秒 → 876 秒）で、アプリを起動するだけのテストも 3 秒から 21 秒になった。実行中、Gradle のデーモンと Java の言語サーバーが合わせて CPU を 3 コア以上使い続けており（CPU 使用率 70 〜 85%）、その影響と判断した。Dialog だけを実行し直しても、段階 0d のとき（69 秒）より遅かった（102 秒）。所要時間は基準との比較の対象にしていない。

## 3. 段階 5 に持ち越すこと

- **内部のログ用の関数が DLL から公開されている。** `DLog`、`DFLog`、`DFLLog`、`ToWString`、`ConcatWStrings`（`common.h` の `__declspec(dllexport)`）。API の 47 関数ではない。`ToWString` は C リンケージで `std::wstring` を返しており、警告 `C4190` の原因でもある。C ABI の設計（段階 5）で、公開しない形にする
- `.def` に書かれていない API（ダイアログの 6 個、`initWinAppSdk`、`openNotificationSettings`）は `__declspec(dllexport)` で公開されている。公開の方法が 2 通りあるので、段階 5 でそろえる

## 4. 範囲外として残したもの

- Win32（x86）の構成。ソリューションにはあるが、スクリプトも NuGet も x64 だけを使う。残すか消すかは別に決める
- 警告 `C4819`（ソースの文字コード）。変更の前からある
