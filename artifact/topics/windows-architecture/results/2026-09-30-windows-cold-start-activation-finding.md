# 調査結果: コールドスタートの通知の活性化が 2 回届いていた

- 実施日: 2026-09-30
- 対象: パッケージ化しないアプリの通知の活性化のうち、プロセスが動いていないときにボタンを押した場合（コールドスタート）。`windows/WindowsLibrary/src/Notification/WindowsNotificationManager.cpp`、`Data/WindowsClassicActivator.cpp`
- ブランチ: `feature/NTKIT-16`
- きっかけ: `2026-09-27-windows-unpackaged-activation-finding.md` の 3 で「コールドスタートは試していない」とした残りを、1.12.0 のリリース前に確かめた

## 1. 何が起きていたか

コールドスタートで、ハンドラが **2 回**呼ばれていた。

| 回 | 中身 | どこから |
|---|---|---|
| 1 | `rawArguments = "{}"`、値 0 個（中身の無い偽物） | `Manager::Create` がコマンドラインの `-ToastActivated` を見つけて出していた |
| 2 | 本物（例: `{"action":"open"}`） | COM の `INotificationActivationCallback::Activate` |

2 回とも `Manager::Create` の中で、呼び出したスレッド（STA）に届いた。起動そのもの（`LocalServer32` から exe が起動され、ボタンの引数が届くこと）は正しく動いていた。

利用者から見ると、コールドスタートのたびに「引数の無いクリック」が 1 回余分に届く。引数の無いクリックを「既定の画面を開く」と扱うアプリは、既定の画面を開いてから本来の画面を開くことになる。

## 2. 原因

2026-06 の通知の設計（`artifact/windows/notification/designs/2026-05-30-windows-notification-design-v3.md`、方針 B）は、COM の `Activate` が間に合わない場合に備えて、**起動時のコマンドラインから通知の引数を読む**経路を入れた。この前提が誤っていた。

- COM が `LocalServer32` から起動するときのコマンドラインは、登録した固定の文字列に COM が `-Embedding` を足したものだけである。実測で `activationprobe.exe -ToastActivated -Embedding`
- **ボタンの引数がコマンドラインに載ることは仕組み上無い。** この経路は `-ToastActivated` の後ろの `-Embedding` を `key=value` として読もうとし、何も取れずに空の `{}` を出していた
- 本物は COM の `Activate` で、`Manager::Create` が登録した直後に届いていた（この測定では `Create` が戻る前）

この経路は NTKIT-9（2026-06-14、`3adb1a6a`）で入り、1.x の DLL にも同じコードで入っている。1.x では 9/27 の `CustomActivator` の不具合と重なっていた。

## 3. 確かめ方と結果

`2026-09-27` と同じ素の Win32 のコンソールアプリ（2.0.0 の C++ API、AUMID `NativeToolkit ActivationProbe`、メインスレッドは STA）に、次の 2 つのモードを足した。

- `cold`: 登録して通知を出し、すぐ終了する。通知は通知センターに残る
- 起動されたとき（コマンドラインに `-ToastActivated` がある）: `Manager::Create` をもう一度呼び、コマンドラインと、20 秒の間に届いたハンドラの呼び出しをすべて `probe.log` に書く。2 回目があれば記録される

`cold` を実行してプロセスが無いことを確かめ、通知センターから「Open」を押した。

| 回 | ライブラリ | コマンドライン | ハンドラ |
|---|---|---|---|
| 1 | 修正前（`dist/1.12.0` の `ace78e19`） | `activationprobe.exe -ToastActivated -Embedding` | **2 回**: `{}`、`{"action":"open"}` |
| 2 | 修正後 | 同じ | **1 回**: `{"action":"open"}` |

どちらも `Manager::Create` が戻る前に届いた（`callbacks so far` が `Create` の直後に 2 と 1）。

測っていないこと:

- MTA の呼び出し元。`Create` は COM を MTA で初期化するので、STA で初期化していないスレッドから呼ぶと MTA になる。そのときは COM のスレッドで届くはずで、`Create` の後になることもあり得る
- `Manager::Create` の呼び出しが遅いアプリ。COM がクラスオブジェクトの登録を待つ時間を超えると、活性化は届かない。修正前の実装でも、そのとき届くのは空の 1 回だけだった

試験で作ったショートカットとレジストリ（`AppUserModelId\NativeToolkit ActivationProbe` と `CLSID\{FE818D52-...}`）は、確認後に削除した。

## 4. 対処

コマンドラインから読む経路を削除した。コールドスタートの活性化は、ほかの活性化と同じく COM の `Activate` だけで届く。

- 削除: `TryGetLaunchActivationJson`、`Manager::Create` の中でそれを呼んで配送していた部分、`m_launchActivationConsumed`、`RegisterActivation` の中のログ
- `LocalServer32` の `-ToastActivated` は残す。アプリが「通知から起動された」と自分で判定できる目印になり、害は無い
- 公開ヘッダー（C++ の `Manager` の説明、C の `Notification.h` の冒頭）を直した。コールドスタートの活性化は **ほかと同じ経路で 1 回だけ** 届く。`Create` が戻る前に届き得る（STA では `Create` の中で呼び出しスレッドに届いたのを確かめた）。コマンドラインには通知の中身は載らない
- 単体テスト 404 件は全件成功。この経路を通るテストは元から無かった（サンプルはパッケージ化されている）
- `dist/1.12.0/windows` を作り直し、`check_windows_dist.py` の 4 項目が OK

修正は 9/27 と同じく **2.0.0（dist 1.12.0）だけに入れる**。出荷済みの 1.x はこの挙動のまま。

## 5. 置き換わった記述

次の記述は、今回の測定と合わない。版の付いた文書なので書き換えず、ここで置き換える。

| 文書 | 箇所 | 元の記述 | 今 |
|---|---|---|---|
| `artifact/windows/notification/designs/2026-05-30-windows-notification-design-v3.md` | 方針 B（32、43、460〜494、802、843、887、911 行目） | 起動引数 `-ToastActivated` の自前パースでクリック情報を復元する | コマンドラインに引数は載らない。経路は削除した。コールドスタートも `Activate` で届く |
| `designs/2026-09-20-windows-architecture-cpp-api-design.md` | NTF-09 / NTF-10（484、798、932 行目）、RK-04、RK-10 | cold start の配送は起動引数により、`Manager::Create` の中から呼び出しスレッドでちょうど 1 回 | `Activate` で 1 回。`Create` が戻る前に届き得る。呼び出しスレッドかどうかはアパートメントによる |
| `designs/2026-09-21-windows-architecture-c-abi-design.md` | 143、190 行目 | cold start の 1 回だけは `_create` の中で呼び出しスレッド | 同上。`*out_manager` を前提にしない、という結論は変わらない |
| `designs/2026-09-20-windows-architecture-c-abi-input-inventory.md` | 107 行目 | classic（cold start）はコマンドラインの `-ToastActivated` 以降を解析 | その経路は無い。cold start も classic の `Activate` と同じ規則 |

ハンドラが `Manager`（C では `*out_manager`）を前提にしてはいけない、という利用者への約束（RK-10）は変わらない。

## 6. 申し送り

`unity-native-plugin`（`unity-native-plugin-ba`）には、原因と修正の方針を 2026-09-30 に伝えた。

- Unity 側に空の活性化を特別に扱う処理は無く、受け口は届いたものを積むだけなので、Unity 側で変えるものは無い
- この修正を含む `dist/1.12.0/windows/windows-native-toolkit-capi-2.0.0.dll` で、Unity 側の Player テスト（Mono と IL2CPP）を流し直してもらう。渡すときに、そのコミットと DLL の MD5 を伝える。Unity 側のテストはコールドスタートを扱っていない
