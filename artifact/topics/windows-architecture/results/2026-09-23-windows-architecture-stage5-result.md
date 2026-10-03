# 段階 5 結果: 新しい C ABI（`WindowsLibraryCApi`）

- 実施日: 2026-09-21 〜 2026-09-23
- 対象: `artifact/topics/windows-architecture/README.md` の段階 5
- ブランチ: `feature/NTKIT-16`
- 設計書: `designs/2026-09-21-windows-architecture-c-abi-design.md`（第 3 版、3 者 2 回のレビュー反映）

## 1. 何を作ったか

| 成果物 | 内容 |
|---|---|
| `windows/WindowsLibraryCApi`（DLL） | 新しい C ABI。105 関数（8.2）。公開ヘッダー `include/NativeToolkitC/{Common,Dialog,Notification,Clipboard}.h` |
| `windows/WindowsLibraryCApiTest` | C ABI の単体テスト。130 件 |
| `windows/WindowsLibraryCApiSmoke`（2 つ） | 公開ヘッダーと import ライブラリだけで組んだ C と C++ の実行ファイル（CT-21） |
| `scripts/check_c_abi_contract.py` | 12.3 の機械照合。自己テスト 19 件 |
| 削除 | 1.x の C ABI（DLL、`src/Bridge/`、旧ヘッダー 4 つ、旧テスト 2 群）、`UnityWindowsPlugin` |

設計書からの変更は、設計書の該当箇所に理由とともに記した（E-11 の改名の取りやめ、E-21 のウィンドウクラス、12.1 のテストの置き場所と偽物、通知の内容のビルダーのテストの比べ方（12.1 の表）、`NotificationPayloadTest` を残したこと、T-13 の配布物の名前）。

## 2. `unity-native-plugin` への申し送り

`unity-native-plugin` は 1.x の C ABI を P/Invoke している。2.0.0 はすべての関数のシグネチャが変わるので、書き直しになる（D-4）。

### 2.1 まず見るもの

| 見るもの | 場所 |
|---|---|
| 52 関数と新しい関数の対応表 | 設計書 8.3（**すべての関数でシグネチャが変わる**。`変わる振る舞い` の列に意味の変化） |
| 公開ヘッダー | `windows/WindowsLibraryCApi/include/NativeToolkitC/`。C99、ASCII だけ。bindgen / cbindgen にそのまま通る |
| スレッドと寿命の前提 | 設計書 1.3（機能ごとのスレッド、ハンドルごとの約束、COM とメッセージループ、コールバックの中で呼ばないもの） |
| 受け渡しの 3 方式 | 設計書 1.2（出力のハンドル、`struct_size` 付きの構造体、ビルダーのハンドル） |

### 2.2 配布物

- DLL の名前は `NativeToolkitC.dll`（import ライブラリが読み込む名前）。配布物は `dist/<版>/windows/windows-native-toolkit-capi-<版>.dll`
- `Microsoft.WindowsAppRuntime.Bootstrap.dll` を隣に置く（1.x と同じ）
- x64 のみ。版は `ntk_version()` が `NTK_VERSION`（`0x020000`）を返す

### 2.3 C# から呼ぶときの注意

- **文字列を返す関数は `IntPtr` で受けて自分で複製する。** `[return: MarshalAs(UnmanagedType.LPUTF8Str)]` と書くと、マーシャラーが戻りのポインタを `CoTaskMemFree` で解放してヒープを壊す（7.4）。引数の文字列は `LPUTF8Str` でよい
- 借りたポインタ（`ntk_string_data` など）は、そのハンドルを `_free` するまで有効。コールバックが受け取ったハンドルは**そのコールバックから戻るまで**
- **登録ごとに `GCHandle` を 1 つ作り、`release` で `Free` する。** 同じ `user_data` の値で登録し直すときも別の所有権を渡す（7.5.1）。`release` は、登録した関数が失敗したときも必ず 1 回呼ばれる（呼び出しスレッドで、戻る前に）
- コールバックは `[UnmanagedFunctionPointer(CallingConvention.Cdecl)]`。`NTK_CALL` は `__cdecl`
- 構造体は 0 で埋め、`struct_size` に `Marshal.SizeOf<T>()` を入れる（`sizeof` ではない）。`reserved` は 0 のまま
- エラーは戻り値。OS の生の値は、同期なら直後に同じスレッドで `ntk_last_system_code()`、非同期なら完了の引数
- ハンドルは `SafeHandle` にして、対応する `_free` で解放する

### 2.4 Unity 固有（設計書 1.3.4）

Unity Editor はネイティブの DLL を下ろさない。ドメインリロードやプレイモードの出入りの後も、DLL の中のセッションとマネージャーは残る。一方で C# の static に置いたハンドルは消え、登録した関数ポインタは下ろされたドメインを指す。

- `AssemblyReloadEvents.beforeAssemblyReload`、`EditorApplication.playModeStateChanged`（`ExitingPlayMode`）、`Application.quitting` で次を行う
  - Clipboard: **オーナーのスレッドから** `ntk_clipboard_session_close` を呼び、`ntk_clipboard_session_free` する。`BUSY` ならほかのスレッドの読み書きを終わらせて再試行する。provider の `release` は close の中で呼ばれる
  - Notification: `ntk_notification_manager_close` と `_free` の後、**すべての登録の `release` が呼ばれるのを期限付きで待つ**（`release` の中でイベントを立てる）。活性化のコールバックは受け取ったものをキューに積むだけにし、メインスレッドへ同期で戻らない（戻ると互いに待って止まる）
- **close が成功しないまま `_free` すると、その Editor では以後セッションを作れない**（放棄）。`_free` で止まるのはコールバックだけ。`_free` もしないままリロードすると、コールバックも止まらず、古いドメインを呼んで落ちる
- クリップボードのオーナーにするスレッドは STA で、メッセージループを回し続ける。メインスレッドが STA かどうかは `CoGetApartmentType` で確かめる。通知の `ntk_notification_manager_create` は呼び出しスレッドを MTA にするので、同じスレッドをオーナーにできない（1.3.3）

### 2.5 ほかの言語

- **Go**: オーナーの goroutine で `runtime.LockOSThread()`。`user_data` に Go のポインタは渡せないので、`cgo.Handle` を `C.malloc` した領域に置き、その番地を渡す。`release` でその領域を `C.free` し、ハンドルを `Delete` する
- **Rust**: `bindgen` でヘッダーから生成できる。ハンドルは `NonNull` を包んだ型にして `Drop` で `_free`。コールバックは `extern "C" fn`
- **Python**: `ctypes` で扱える。オーナーのスレッドで `GetMessageW` のループを回す

## 3. 確かめたこと（T-16、2026-09-23）

| 確認 | 結果 |
|---|---|
| `scripts/test_windows.ps1 -IncludeDestructive -Baseline`（全件） | **495 件すべて成功、失敗 0**。9 分 43 秒。内訳は単体 404、スモーク 2、UI 89。Windows の設定は元に戻った |
| 単体テスト（Debug / Release） | どちらも 404 件成功（C++ API 274、C ABI 130） |
| `dumpbin /exports` と `.def` | 105 個で一致。DLL が読み込むのは C ABI の DLL と OS のものだけ |
| 機械照合 | `check_c_abi_contract.py` 8 項目、`check_cpp_api_contract.py` 12 項目、`check_design_consistency.py`。`scripts/tests` の自己テスト 56 件 |
| スモーク（CT-21） | C と C++ の実行ファイルが実際の DLL で成功（テキストの往復を含む） |

### 3.1 ベースラインとの差分

段階 4 のベースライン（390 件、2026-09-21）と比べ、**新規 138 件、消えた 33 件、結果が変わったもの 0 件**。今回の結果（495 件）を新しいベースラインとして記録した。

| 差分 | 件数 | 理由 |
|---|---|---|
| 消えた | 25 | 1.x の C ABI のテスト（`ClipboardBridgeTest` 20、`NotificationBridgeTest` 5）。ABI とともに削除（T-12） |
| 消えた | 1 | `DialogMappingTest` の `extraFlags` の 1 件（E-10） |
| 消えた | 1 | `ClipboardApiTest` の close のテスト 1 件。E-19 で `CANCELED` の再試行が不要になり、書き直した（T-17） |
| 消えた | 6 | Clipboard の UI テスト。E-19 で作れなくなった場面（T-17。利用者の決定で 5 件削除・1 件書き直し） |
| 新規 | 130 | C ABI の単体テスト（`WindowsLibraryCApiTest`） |
| 新規 | 2 | スモークの実行ファイル 2 つ（CT-21） |
| 新規 | 4 | C++ API のテスト（E-19 の close、E-20 のハンドラ。T-17） |
| 新規 | 2 | UI テスト（T-03 の D-14、E-19 に合わせて書き直した 1 件） |

### 3.2 CU-01（computer use、2026-09-23）

Claude のデスクトップアプリ（Code タブ、このリポジトリのフォルダ、ワークツリー無し）から、`windows/WindowsLibraryExampleUITest/ComputerUse/CU-01-hero-image.md` の手順で実行した。段階 3 と段階 4 の分を兼ねる（この 3 つの段階で、サンプルが通知を出す経路は C++ API のまま変わっていない）。

| 項目 | 内容 |
|---|---|
| 判定 | **合格** |
| 理由 | 「Native Toolkit Example」のグループに、タイトル `With Image`、本文 `Toast with hero image` の通知があり、画像が手順書 2 章の見え方と一致した（灰色の枠の上半分と、左上・右上から中央の下で交わる 2 本の斜線）。判定に迷った点は無い |
| サンプルの表示 | `✅ [InitializeManager] initialized. setting=0`、`✅ [RemoveAll] errorCode=0`、`✅ [ShowWithImage] errorCode=0` |
| スクリーンショット | `windows/WindowsLibraryExampleUITest/ComputerUse/evidence/CU-01/2026-09-23-5.png`（325×298。通知 1 件だけ。画面は 1920×1080）。段階 0d の 327×292 とほぼ同じ |
| 後片付け | RemoveAll は `errorCode=0`。通知センターを閉じ、サンプルのウィンドウを閉じた |

手順と違ったことと、手順書への反映:

| 違ったこと | 影響 | 手順書への反映 |
|---|---|---|
| スタートメニューではなく computer use の `open_application` でサンプルを起動した。エクスプローラー（シェル）の権限が「クリックのみ」で、スタートメニューの検索に文字を打てない | 無し（ウィンドウは 1 つだけ開いた） | 手順 1 に起動の方法を足した |
| 通知センターに `Esc` を送らず、サンプルのウィンドウをクリックして閉じた | 無し | 変更無し（手順 11 にすでにある） |
| 集中モード（応答不可）がオンだった | 無し（前提で「どちらでもよい」としている） | 変更無し |
| computer use の撮影では画像をファイルに保存できなかったので、画面の座標を求めたうえで PowerShell で同じ範囲を切り取って保存した | 無し（画面の実際の画素で保存でき、かえって鮮明） | 手順 10 に保存の方法を足した |

### 3.3 残っていること

- NuGet、マニュアル、Doxygen の生成は段階 6
