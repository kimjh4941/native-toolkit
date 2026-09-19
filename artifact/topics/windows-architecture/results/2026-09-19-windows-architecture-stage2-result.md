# 段階 2 結果: ディレクトリの再編

- 実施日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 2（3 章の `src/`）
- ブランチ: `feature/NTKIT-16`
- 設計書: 書かない（README 5.1）

## 1. 方針

- 層の意味は mac（`mac/MacLibrary/MacLibrary/<Feature>/`）に合わせた。`Domain` はモデルと純粋なロジック、`Application` はポートと状態の管理、`Data` は OS の API を使う実装、機能の直下は外から呼ばれる入り口
- **ファイルを移動するだけで、中身は分けない。** 1 つのファイルに複数の層が混ざっているもの（Manager）は、機能の直下に置いた。分けるのは C++ API に書き直す段階 3
- 中身の無い層のフォルダは作らない（Notification の `Domain`、Dialog の層）。mac の `Application/Port/` のような 1 段下のフォルダも作らない（1 層あたり数ファイルのため）
- ファイル名は変えない（段階 3 で変える）

## 2. 割り振り

```
windows/WindowsLibrary/
  pch.h  pch.cpp  targetver.h            # ビルドの基盤なので直下に残した
  src/
    Common/        common.h/.cpp
    Dialog/        WindowsDialogManager.h/.cpp
    Notification/  WindowsNotificationManager.h/.cpp, WindowsNotificationManagerInternal.h
      Application/ WindowsNotificationBackend.h（ポート）
      Data/        WindowsClassicActivator.h/.cpp, WindowsAppSdkBootstrap.cpp
    Clipboard/     WindowsClipboardManager.h/.cpp, WindowsClipboardManagerInternal.h
      Domain/      WindowsClipboardFormats.h/.cpp
      Application/ WindowsClipboardHistoryBackend.h（ポート）, WindowsClipboardHistoryCoordinator.h/.cpp, WindowsClipboardLifecycle.h/.cpp
      Data/        WindowsClipboardCore.h/.cpp, WindowsClipboardDeferredProvider.h/.cpp, WindowsClipboardHistoryWinRt.h/.cpp, WindowsClipboardWindow.h/.cpp
```

29 ファイルを `git mv` で移動した（履歴は引き継がれる）。

## 3. 変更したこと

| 対象 | 変更 |
|---|---|
| ライブラリの `#include` | インクルードのパスを `src/` にし、`#include "Clipboard/Data/WindowsClipboardCore.h"` のように層まで書く。どの層がどの層に依存しているかが `#include` で分かる。`pch.h` は直下のまま |
| `WindowsLibrary.vcxproj` | 29 ファイルのパス。インクルードのパスに `$(ProjectDir);$(ProjectDir)src` を足した（全構成） |
| `WindowsLibrary.vcxproj.filters` | ソリューションエクスプローラーの表示を `src` のフォルダと同じ構成に作り直した |
| `WindowsLibraryTest` | テストの `#include "../WindowsLibrary/..."` を `src` からのパスにした。直接コンパイルしているライブラリの `.cpp` 8 つのパス。インクルードのパスに `..\WindowsLibrary\src` を足した。ライブラリの `.cpp` は、今までどおりインクルードのパス（`..\WindowsLibrary`）からライブラリの `pch.h` を読み込む |
| `WindowsLibraryExample` | `#include` を `src` からのパスにした（5 ファイル）。インクルードのパスにあった**絶対パス**（`C:\Users\User\Desktop\...\WindowsLibrary`）を、相対パス `$(ProjectDir)..\WindowsLibrary\src` にした。これまでは、ほかの PC やフォルダではビルドできなかった |
| `scripts/build_windows_library_dll.ps1` | NuGet に入れる公開ヘッダー 3 つのパス。公開ヘッダーはほかのヘッダーを読み込まないので、パッケージの中は今までどおり平らに並べる。NuGet の利用者に影響は無い |
| `README.md` / `README.ja.md` / `README.ko.md` | 公開ヘッダーのパス（各 2 か所） |

`#include` の書き換えは、`#include` の行だけが変わったことを差分で確かめた。`common.h` は元から Shift_JIS で保存されており、中身を変えずに移動しただけである。

`UnityWindowsPlugin` はライブラリのヘッダーを読み込んでいないので変えていない（段階 5 で削除する）。

## 4. 確かめたこと

| 確認 | 結果 |
|---|---|
| `test_windows.ps1`（全件） | **基準と同じ**（`Same outcomes as the baseline of 2026-09-19 14:51`）。ユニットテスト 106 件成功、UI テスト 93 件成功、1 件（履歴の `Clear`）は既定どおり実行されない。OS の設定はすべて戻った |
| ビルドの警告（Debug のリビルド） | 段階 1 と同じ（`MSB3106` 1、`C4819` 24、`C4190` 17） |
| プロジェクトへの登録 | `src` の下の 29 ファイルがすべて `WindowsLibrary.vcxproj` にある |
| NuGet の公開ヘッダー | スクリプトに書いた 3 つのパスがすべて存在する。`nuget` がこの PC に無いので、パッケージの作成までは確かめていない |
| 古いパスへの参照 | `artifact/features`（過去の記録）を除き 0 件 |
| CU-01 | 実施しない（段階 1 と同じく、利用者の判断） |

UI テストの所要時間は 16 分 46 秒だった。段階 1 と同じく、実行中の Gradle のデーモンと Java の言語サーバーの CPU 負荷の影響と見ている（段階 1 の結果の 2.1）。
