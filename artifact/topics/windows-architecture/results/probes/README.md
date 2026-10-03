# 試験プログラム

段階 6 の後に見つかったことを確かめるのに使った、素の Win32 のコンソールアプリ。このリポジトリのサンプル（MSIX）と UI テストは、パッケージ化しないアプリの通知の経路を通らない。また、クリップボードの close が `BUSY` を返す場面は、テストから作りにくい。そのため、どちらもこのプログラムで確かめた。

ソリューションにもビルドにも入れていない。記録を再現するためと、後で自動テストにするときの土台として置いている。

| フォルダ | 確かめたこと | 記録 |
|---|---|---|
| `activationprobe/` | パッケージ化しないアプリの通知の活性化。warm（起動中）と、コールドスタート | `../2026-09-27-windows-unpackaged-activation-finding.md`、`../2026-09-30-windows-cold-start-activation-finding.md` |
| `closeprobe/` | 履歴の要求の WinRT の処理が走っている間に `Clipboard::Session::Close` を繰り返したとき、メッセージを処理するかどうかで結果が変わるか | `../2026-09-30-windows-clipboard-close-busy-finding.md` |

## ビルドの仕方

どちらも、`NativeToolkit` パッケージ（C++ API の静的ライブラリ）を使う x64 の Release のコンソールアプリである。

1. `dist/1.12.0/windows/windows-native-toolkit-2.0.0.nupkg` を zip として展開する
2. `Microsoft.WindowsAppSDK` 1.7.250513003 を、`nuget install Microsoft.WindowsAppSDK -Version 1.7.250513003` などで用意する
3. 空の C++ コンソールアプリのプロジェクト（v143、Unicode、C++20、`/utf-8`）を作り、`main.cpp` を 1 つ入れる
4. `packages.config` の利用者と同じように、次を import する
   - `<Project>` の先頭: `Microsoft.WindowsAppSDK.props` と、展開したパッケージの `build/native/NativeToolkit.props`
   - `<Project>` の末尾: `Microsoft.WindowsAppSDK.targets`
5. `activationprobe` は、リンクに `shell32.lib` を足す（`SetCurrentProcessExplicitAppUserModelID` のため）

`Microsoft.WindowsAppRuntime.Bootstrap.dll` は、`Microsoft.WindowsAppSDK.targets` が exe の隣に置く。

## 使い方

### activationprobe

AUMID は `NativeToolkit ActivationProbe` で固定している。スタートメニューのショートカットと、`HKCU\Software\Classes` の `AppUserModelId\NativeToolkit ActivationProbe` と `CLSID\{FE818D52-...}` を作るので、確かめた後に削除する。アイコンとして、exe の隣の `probe.png` を使う（何かの PNG を置く）。

| 引数 | 動作 |
|---|---|
| `sta`（既定） / `mta` / `sta-aumid` | warm。通知を出し、90 秒待つ。その間に通知センター（Win+N）で「Open」を押す。届けば `ACTIVATED` を出力する |
| `cold` | コールドスタート。通知を出してすぐ終了する。その後に「Open」を押すと、COM がこの exe を `-ToastActivated -Embedding` で起動する。起動された側は、コマンドラインと、20 秒の間に届いたハンドラの呼び出しをすべて exe の隣の `probe.log` に書く |

### closeprobe

最前面のウィンドウを出し、クリックされて最前面になるのを待つ。履歴の要求は、プロセスが最前面でないと `NotForeground` で断られるためである。その後、次の 2 つを順に行う。

- メッセージを処理せずに `Close` を 10 秒繰り返す
- 再試行の合間にメッセージを処理しながら `Close` を繰り返す

クリップボードは読むだけで、書き込みはしない。
