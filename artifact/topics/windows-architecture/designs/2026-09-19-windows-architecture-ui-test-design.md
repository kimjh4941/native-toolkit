# UI テスト設計書（段階 0）

- 作成日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 0b 〜 0d
- 入力:
  - `artifact/topics/windows-architecture/README.md`（7 章 検証方法）
  - `artifact/topics/windows-architecture/results/2026-09-19-windows-architecture-stage0a-spike-result.md`（通知とバッジ）
  - 本書の付録 A（Dialog の事前確認。2026-09-19 実施）
  - `artifact/features/notification/designs/2026-05-31-windows-notification-sample-app-design-v2.md` の 7 章（手動確認の観点）
  - `artifact/features/clipboard/designs/2026-07-31-windows-clipboard-sample-app-design-v5.md` の 8 章（手動確認）
- 決定事項: 10 章（U-1 〜 U-7。2026-09-19 決定）

## 1. 目的と範囲

段階 1 〜 6 の各境界で「動作が変わっていないこと」を判定できるよう、Clipboard / Notification / Dialog のすべてに UI テストをそろえる。手動テストは行わない。

| 範囲 | 内容 |
|---|---|
| 対象 | Dialog と Notification の UI テストの新規作成。Clipboard の既存 UI テストに無い観点の追加（付録 B。U-3）。テスト基盤（`Infra`）の拡張。computer use の確認手順書。サンプルアプリへの AutomationId の追加（段階 0b）。検証スクリプト（段階 0d） |
| 対象外 | 音声（どの手段でも確かめられない。ライブラリのユニットテストで確かめる）。2 台目のデバイスが必要な確認（Clipboard の `EXCLUDE_ROAMING`）。環境に依存して再現できない異常系（Notification の `HRESULT_FAILURE` / `BADGE_FAILED` など） |

## 2. 方針

- **FlaUI で自動化する。** FlaUI で扱えない項目（画像の中身）だけを computer use で確かめる（README 7.2、7.3）
- **表示言語に依存しない。** 要素は AutomationId、Win32 のコントロール ID、アプリの表示名で探す。画面の文言（「開く」「受信日時」など）では探さない
- **他のアプリの情報を記録しない。** 通知センターとバナーには他のアプリの通知が、ファイルのダイアログには利用者のファイルやクイックアクセスが表示される。ログにもスクリーンショットにも、サンプルアプリの通知やテスト用に作ったファイルだけを残す
- **固定の待ち時間を使わない。** 条件が満たされるまで待つ（既存の `IUiSession` の方針と同じ）
- **テストは互いに独立させる。** テストごとにアプリを起動して終了する（既存のテストと同じ）

## 3. 操作の技法（確認済み）

### 3.1 ボタンの押し方

| 押すもの | 方法 | 理由 |
|---|---|---|
| 普通のボタン | Invoke パターン（既存の `IUiElement.Invoke()`） | 既存のテストで実績がある |
| **モーダルダイアログを開くボタン**（Dialog 画面の 6 つ） | **マウスクリック** | Invoke で押すと、その呼び出しがアプリの UI スレッドの中で処理中のまま残り、以後のアプリへの UI Automation の呼び出しがすべて `UIA Timeout` になった。クリックは入力を送るだけなので何も残らない |
| バナーのボタン | Invoke | 表示アニメーション中に押すと無視された |

マウスクリックとバナーのボタンは、**要素の位置が動かなくなるのを待ってから**押す。画面の切り替え直後やバナーの表示直後はアニメーションで位置が変わり、途中の位置でクリックすると別のボタンを押してしまった（付録 A）。

### 3.2 モーダルダイアログの見つけ方

1. Win32 の `EnumWindows` で、サンプルアプリのプロセス ID とクラス名 `#32770` が一致し、表示されているウィンドウを探す
2. 見つけたウィンドウハンドルを `FromHandle` で UI Automation の要素にする
3. ボタンと入力欄は Win32 のコントロール ID（AutomationId として見える）で操作する

アプリのウィンドウを UI Automation でたどって探す方法は、モーダルループの間は応答しないので使わない。

| ダイアログ | 入力欄 | 決定ボタン | キャンセル |
|---|---|---|---|
| アラート（`MessageBox`） | — | `1`（OK） | `2` |
| ファイルを開く（単数・複数） | `1148` | `1`（`SplitButton`） | `2` |
| 保存 | `1001` | `1` | `2` |
| フォルダ（単数・複数） | `1152` | `1` | `2` |

ファイルやフォルダは、入力欄にフルパスを入れて決定ボタンを押す。複数選択は、フルパスを引用符で囲んで空白区切りで並べる（`"C:\...\a.txt" "C:\...\b.txt"`）。

### 3.3 通知センター

段階 0a の結果（`results/2026-09-19-windows-architecture-stage0a-spike-result.md` の 4.1）のとおり。要点:

- Win+N で開き、Esc で閉じる。Win+N は開閉の切り替えなので、開く前に閉じていることを確かめる
- ウィンドウはクラス名 `Windows.UI.Core.CoreWindow` とプロセス `ShellExperienceHost` で探す（名前は実行ごとに変わる）
- アプリのグループ → 通知（`ListItem`）→ 展開（`ExpandCollapse`）→ `Title` / `Content` / `VerbButton` / `Edit` / `Picker` / `progressBar` / `Image`

### 3.4 バナー

- 集中モード（応答不可）がオフのときだけ表示される
- 「新しい通知」ウィンドウ → `NormalToastView` → `SenderName` / `Title` / `MessageText`（通知センターでは `Content`。ID が違う）/ `VerbButton`
- 約 7 秒で消える

### 3.5 バッジ

- タスクバー（`Shell_TrayWnd`）→ AutomationId `Appid: <AUMID>` のボタン → 子要素 `BadgeText`
- 数字は名前が数字、グリフは名前がアイコン用フォントの文字 1 つ（alert は `U+EDAD`。画面にもログにも表示されない文字）、クリアすると要素が無い

### 3.6 OS の設定の読み取りと切り替え

| 設定 | 読み方・切り替え方 | 状態 |
|---|---|---|
| 集中モード（応答不可） | 通知センターの `DoNotDisturbButton`（`Toggle` パターン） | 確認済み（段階 0a） |
| クリップボードの履歴 | レジストリ `HKCU\Software\Microsoft\Clipboard` の `EnableClipboardHistory`（DWORD、1 = 有効）。書き換えるとすぐに反映される | 確認済み（付録 C） |
| アプリの通知の有効・無効 | 設定アプリのこのアプリ専用のページにあるスイッチ `SystemSettings_Notifications_AppNotifications_ToggleSwitch`。ページは、通知センターのアプリのグループの `SettingsButton` → メニュー項目 `GoToNotificationSettingsMenuItem` で開く。レジストリ（`Notifications\Settings\<AUMID>` の `Enabled`）は書き換えても反映されない | 確認済み（付録 C） |

アプリの通知を切り替えるときの注意:

- **設定アプリを先に閉じる。** 設定アプリは 1 つしか起動できず、別の仮想デスクトップで開いていると隠された状態（DWM の cloaked）になり、UI Automation から操作できない。テストの前に `SystemSettings` のプロセスを終了する（設定は変更した時点で保存されるので、閉じても失われるものは無い）
- **通知センターにこのアプリの通知が 1 件以上必要。** グループのメニューを出すため。先に `ShowBasic` で 1 件出す
- 無効にすると、このアプリの通知は通知センターから消える。オンに戻すときは、開いたままの同じ設定ページのスイッチを使う
- **設定ページは、読み込みが終わるまでスイッチを「オフ」と表示する。** この表示を「既にオフ」と読み違えると何もせずに終わってしまう（段階 0c で、バナーのテストの後に実行すると再現した）。スイッチが「オン」と表示されるまで待ってから切り替える。オンと表示されないまま時間切れになったら、分かりやすいメッセージで失敗させる
- **切り替えた後、アプリが読む設定値に反映されるまで少し遅れる。** `GetSetting` を 1 回だけ押すと古い値を読むことがあるので、期待する値になるまで押し直す
- 切り替えた状態が保たれることを 2 秒間見届け、戻ってしまったら切り替え直す（最大 3 回）
- 設定ページがまれに開かないことがあるので、そのときは手順を最初から 1 回やり直す

クリップボードの履歴を切り替えるときの注意:

- **履歴を無効にすると、Windows がクリップボードを空にする**（約 0.5 秒後。段階 0c で判明）。切り替えの直後にテストが書き込んだ内容が消されるので、クリップボードの変更の番号（`GetClipboardSequenceNumber`）が変わり、その後 500 ms 変わらなくなるまで待ってから戻る

扱い方は U-2 で決めたとおり、**テストが切り替え、終わったら元に戻す**。

- 切り替える前の値を、実行ごとにファイル（`%TEMP%` 配下）へ記録する
- テストの終わりに元の値へ戻し、戻ったことを読み取りで確かめる
- テストが途中で強制終了されても、`scripts/test_windows.ps1` の最後と、次回の実行の最初に、記録した値へ戻す
- **例外: アプリの通知は自動では戻せない。** オンに戻すための設定ページは、このアプリの通知のグループから開くが、通知がオフの間はそのグループが通知センターに無い。記録が残っていたら、次回の実行の最初に、戻し方（設定 > システム > 通知 > Native Toolkit Example）を示したメッセージで実行を止める

### 3.7 外部アプリの代わり（Clipboard）

外部アプリ（メモ帳、Word、ペイント、エクスプローラー）とのやり取りは、**テストのプロセス自身が外部のアプリとしてクリップボードを読み書きする**ことで確かめる。ライブラリが責任を持つのはクリップボードに入った形式の中身であり、Word での見た目ではないため。

- 読み書きは Win32（`OpenClipboard` / `GetClipboardData` / `SetClipboardData`）で行い、`Infra` に閉じ込める
- `OpenClipboard` には所有ウィンドウ（メッセージ専用ウィンドウでよい）を渡す。所有者が無いと `EmptyClipboard` の後の `SetClipboardData` が失敗する。ほかのプロセスが一瞬クリップボードを開いていることがあるので、開けるまで少し待って再試行する
- 確認済み（付録 C）

### 3.8 利用者の環境への影響

UI テストは、テストを実行している利用者自身のクリップボードと履歴を使う。

| 影響 | 扱い |
|---|---|
| クリップボードの中身が上書きされる | 実行の最初に文字列を保存し、実行の最後に戻す（`TestRunHooks`。文字列以外の形式は戻せない） |
| クリップボードの履歴に項目が増える | 受け入れる。履歴の結果の表示には利用者の履歴の文字列が含まれうるので、テストの失敗のメッセージやログに出さない（`ClipboardPage.WaitForRedacted`） |
| 履歴の `Delete` | テストが自分で作った項目だけを消すので問題ない |
| **履歴の `Clear`（ピン留め以外をすべて消す）** | **利用者のピン留めしていない履歴がすべて消え、元に戻せない。明示したときだけ実行する**（U-6） |

## 4. テスト基盤（`Infra`）の拡張

既存の方針「テストとページオブジェクトは FlaUI の型に依存しない。FlaUI を使うのは `Infra` だけ」を守る。今は FlaUI を使うのが `FlaUiSession.cs` だけだが、拡張後は `Infra` フォルダの中に限る。

| 追加するもの | 役割 |
|---|---|
| `IUiElement.Click()` | 位置が動かなくなるのを待ってからマウスでクリックする（3.1） |
| `IUiSession.WaitForDialog()` → `IUiDialog` | モーダルダイアログを見つける（3.2）。`IUiDialog` はタイトル、`SetText(controlId, text)`、`Press(controlId)` を持つ |
| `INotificationCenter` | 開く、閉じる、タイトルで通知を探す → `INotificationItem`（タイトル、本文、展開、ボタンを押す、入力欄に入れる、選択肢を選ぶ、進捗の値、画像の有無） |
| `IBanners` | タイトルでバナーを探す（`INotificationItem` と同じ形）、消えるのを待つ |
| `ITaskbarBadge` | バッジの状態を読む（無し / 数字 / グリフの文字） |
| `IOsSettings` | 集中モード、クリップボードの履歴、アプリの通知の読み取りと切り替え。切り替える前の値の記録と復元（3.6） |
| `IExternalClipboard` | 外部アプリとしてクリップボードを読み書きする（3.7） |
| `Native.cs` | Win32 の宣言（`EnumWindows` など）を集める |

## 5. サンプルアプリの変更（段階 0b）

### 5.1 AutomationId を付ける

`DialogPage.xaml` と `NotificationPage.xaml` のボタンに AutomationId を付ける。ID は、C++ のクリックのハンドラ名から `_Click`（Dialog は `Button_Click`）を除いたものにする。Clipboard の画面（`InitializeManager` など）と同じ付け方になる。`ResultTextBlock` と `BackButton` は `x:Name` が既に AutomationId として見えているので変えない。

| 画面 | AutomationId |
|---|---|
| Dialog（6） | `ShowAlertDialog`、`ShowFileDialog`、`ShowMultiFileDialog`、`ShowFolderDialog`、`ShowMultiFolderDialog`、`ShowSaveFileDialog` |
| Notification（21） | `InitializeManager`、`Uninitialize`、`GetSetting`、`OpenSettings`、`ShowBasic`、`ShowWithButtons`、`ShowWithImage`、`ShowWithInput`、`ShowWithExpiration`、`ShowWithAudio`、`Schedule`、`CancelScheduled`、`ShowWithProgress`、`UpdateProgress`、`SetBadge`、`SetBadgeGlyph`、`ClearBadge`、`GetAllNotifications`、`RemoveById`、`RemoveByTag`、`RemoveAll` |

見た目も動作も変えない（例外は 5.2 のボタン 1 つ）。

### 5.2 数秒後に予約するボタンを足す（U-1）

`Schedule (+1m)` は 60 秒後に予約するので、確かめるのに 60 秒以上かかる。予約の取り消し（`CancelScheduled`）も「予約した時刻の後に出ないこと」を確かめるので同じだけかかる。そこで、5 秒後に予約するボタンを Notification 画面に 1 つ足す。

| 項目 | 内容 |
|---|---|
| 表示 | `Schedule (+5s)` |
| AutomationId | `ScheduleSoon`（ハンドラ `ScheduleSoon_Click`） |
| 動作 | `Schedule (+1m)` と同じタイトル（`Scheduled`）・同じタグ（`scheduled`）で、5 秒後に予約する。本文だけ `Fires in ~5 seconds` にする。`CancelScheduled` で取り消せる |

既存の `Schedule (+1m)` は残す（人が操作して確かめるときに使う）。

## 6. テストケース

### 6.1 Dialog（新規）

| ID | 操作 | 期待 |
|---|---|---|
| D-01 | アラートで OK | `ShowAlertDialog Result: 1` |
| D-02 | アラートでキャンセル | `ShowAlertDialog Result: 2` |
| D-03 | ファイルを開く → キャンセル | `ShowFileDialog was canceled.` |
| D-04 | ファイルを開く → テスト用のファイルを選ぶ | `filePath` がそのパス |
| D-05 | 複数ファイル → キャンセル | canceled |
| D-06 | 複数ファイル → 2 つ選ぶ | `Result: 2`、`[0]` `[1]` がフルパス。段階 4 でサンプルが C++ API に移り、C++ API がフォルダとファイル名を結合するため（OP-03）。段階 3 までは `Result: 3`、`[0]` がフォルダ、`[1]` `[2]` がファイル名（付録 A の注記、U-4） |
| D-07 | 保存 → キャンセル | canceled |
| D-08 | 保存 → 新しいファイル名 | `savePath` がそのパス。ファイルは作られない |
| D-09 | フォルダ → キャンセル | canceled |
| D-10 | フォルダ → テスト用のフォルダを選ぶ | `folderPath` がそのパス |
| D-11 | 複数フォルダ → キャンセル | canceled |
| D-12 | 複数フォルダ → 2 つ選ぶ | `Result: 2`、`[0]` `[1]` がフルパス |
| D-13 | メニュー → Dialog → Back | メニューに戻る |

テスト用のファイルとフォルダは一時フォルダに作り、テストの終わりに削除する。

Dialog の異常系（`pError` に `GetLastError()` や `CommDlgExtendedError()` の値が返る場合）は、画面の操作では起こせないので対象外とする。Dialog にはユニットテストも無いので、段階 3 の C++ API の設計で扱う。

### 6.2 Notification（新規）

確かめ方は 3.3 〜 3.6 のとおり。表示の確認は、特に書かない限り通知センターで行う。

| ID | 操作 | 期待 |
|---|---|---|
| N-01 | InitializeManager | `setting=0`（有効） |
| N-02 | GetSetting | `Enabled` |
| N-03 | ShowBasic | 通知のタイトル `Hello`、本文 `Basic toast`。`GetAllNotifications` が 1 件 |
| N-04 | ShowWithButtons → 展開 → Open | サンプルに `{"action":"open"}` |
| N-05 | ShowWithInput → 入力欄に文字を入れ、選択肢で Free を選ぶ → Send | サンプルに `action` / `reply` / `opt` を含む JSON |
| N-06 | ShowWithImage | 画像の要素がある（画像の中身は CU-01） |
| N-07 | ShowWithProgress → UpdateProgress | 進捗の値が 30 → 60 |
| N-08 | 進捗の通知が無い状態で UpdateProgress | `No progress notification` の案内（`PROGRESS_NOT_FOUND`） |
| N-09 | ShowWithExpiration | 表示の直後は `GetAllNotifications` に含まれ、期限（10 秒）の後は含まれない |
| N-10 | ShowWithAudio | 通知のタイトル `Reminder`（音声は対象外） |
| N-11 | Schedule (+5s) | 予約した時刻の前は無く、後にある |
| N-12 | Schedule (+5s) → CancelScheduled | 予約した時刻の後も無い |
| N-13 | SetBadge → ClearBadge | バッジが `5` → 無し |
| N-14 | SetBadgeGlyph → ClearBadge | バッジが alert のグリフ（`U+EDAD`）→ 無し |
| N-15 | ShowBasic → GetAllNotifications → RemoveById | その ID の通知が無くなる |
| N-16 | ShowBasic → RemoveByTag | 通知が無くなる |
| N-17 | ShowBasic → RemoveAll | 通知が無くなる |
| N-18 | Uninitialize → ShowBasic | `Not initialized` の案内 |
| N-19 | 初期化せずに ShowBasic | `Not initialized` の案内 |
| N-20 | アプリの通知を OS の設定で無効にして ShowBasic | `GetSetting` が `DisabledForApplication`、ShowBasic で `Notifications are disabled` の案内（`DISABLED`）。最後に有効へ戻し、`GetSetting` が `Enabled` に戻ることを確かめる（3.6） |
| N-21 | ShowBasic（バナー） | バナーにタイトル `Hello`。約 7 秒で消える。集中モードはテストがオフにし、終わったら戻す（3.6） |
| N-22 | ShowWithButtons（バナー）→ Open | サンプルに `{"action":"open"}` |
| N-23 | メニュー → Notification → Back → 再び入る | 画面が作り直され、コールバックの表示先も新しい画面になる |

同じタグの通知は置き換わる（Image / Audio / Expiration などはタグがすべて `sample`）。1 つのテストで確かめる通知は 1 種類にし、テストの前後に `RemoveAll` で片付ける。

対象外:

- 音声
- `HRESULT_FAILURE` / `BADGE_FAILED`（環境に依存して起こせない）
- アプリが起動していない状態で通知を押したときの起動とコールバック（通知のサンプルアプリ計画で「要検証」とされたまま。サンプルの画面が無い状態の動作なので、別のトピックとして扱う）
- `GetAllNotifications` の 4096 文字のバッファの境界（サンプルからは大量の通知を作れない。ユニットテストで扱う）

### 6.3 Clipboard（既存 31 件 + 追加）

既存の 31 件（`ClipboardBusyAndNavigationTests` 10、`ClipboardErrorCaseTests` 10、`ClipboardLifecycleTests` 8、`ClipboardMonitoringTests` 3）はそのまま使う。サンプルアプリ計画の手動確認（8.1 〜 8.4）のうち、既存のテストに無いもの（付録 B）を段階 0 で追加する（U-3）。

追加した 25 件（段階 0c）:

| クラス | 件数 | 付録 B の範囲 |
|---|---|---|
| `ClipboardInteropTests` | 11 | 8.1（外部アプリとのやり取り、GetPreferredFormat の 4 通り） |
| `ClipboardExternalChangeTests` | 5 | 8.2（外部でのコピーと貼り付け、遅延レンダリング） |
| `ClipboardHistoryTests` | 8 | 8.3（`Clear` 以外） |
| `ClipboardHistoryDestructiveTests` | 1 | 8.3 の `Clear`（U-6） |

## 7. computer use の確認手順書

`windows/WindowsLibraryExampleUITest/ComputerUse/` に 1 項目 1 ファイルで置く。

| ID | 対象 | 手順の要点 | 合格の条件 |
|---|---|---|---|
| CU-01 | 画像付き通知の画像（`CU-01-hero-image.md`） | ShowWithImage → 通知センターで通知を展開する | サンプルの `Assets/StoreLogo.png` が表示されている。通知の幅に拡大され上半分だけが見える（灰色の枠の上半分と、中央の下で交わる 2 本の斜線） |

当初はバッジのグリフの種類（CU-02）も computer use で確かめる予定だったが、グリフが文字コード（alert は `U+EDAD`）で読めると分かったので、N-14 で FlaUI が確かめる（U-7）。

各手順書に書くこと: 前提（サンプルを配置済み、集中モードの状態）、操作の手順、期待する結果、合格の条件、証拠として残すスクリーンショットの範囲。

**スクリーンショットは、サンプルアプリの通知またはタスクバーのサンプルアプリのアイコンの範囲だけに切り取る。** 通知センター全体やタスクバー全体は写さない。

スクリーンショットは `ComputerUse/evidence/<ID>/<日付>-<段階>.png` に保存してコミットし、その段階の結果のファイルから参照する。

Clipboard のテストの実行中は computer use を動かさない（Clipboard のサンプルアプリ計画 8 章の注意。画面の撮影がクリップボードに書き込む場合がある）。

## 8. 実行（段階 0d）

`scripts/test_windows.ps1` で次を順に行う。

0. 画面がロックされていたら、分かりやすいメッセージで止める。実行中は `SetThreadExecutionState` で画面の消灯とスリープを抑える（電源の設定は変えない）
1. `WindowsLibrary` と `WindowsLibraryTest` をビルドし（Debug）、`vstest.console.exe` でユニットテストを実行する
2. `WindowsLibraryExample` をビルドし（Release。ソリューションのうち `WindowsLibraryExample` とその参照先だけ。`UnityWindowsPlugin` はビルドの後に regsvr32 で登録する設定があり、管理者権限が無いと失敗するため含めない）、`.appxrecipe` の一覧に従って AppX のレイアウトへコピーしてから `Add-AppxPackage -Register` で登録する（Visual Studio の配置と同じこと。スクリプトで登録しないと、テストが古いビルドを相手にしてしまう）
3. `WindowsLibraryExampleUITest` を実行する。前回の実行で OS の設定の記録が残っていれば、テストの最初（`TestRunHooks`）がその値へ戻す（3.6）
4. OS の設定の記録が残っていないこと（すべて戻ったこと）を確かめる
5. 結果（件数と失敗の一覧）を表示し、基準の結果（`scripts/test_windows.baseline.json`）とテストごとに比べて、結果が変わったテスト、増えたテスト、無くなったテストを表示する。`-Baseline` を付けたときは、この実行の結果を新しい基準として保存する（失敗が無いときだけ）

オプション:

| オプション | 内容 |
|---|---|
| `-IncludeDestructive` | 履歴の `Clear` も実行する（U-6） |
| `-Baseline` | 結果を基準として保存する。`-Filter` や `-SkipUnitTests` とは併用できない |
| `-Filter` | UI テストを `dotnet test` のフィルタで絞る（例: `TestCategory=Dialog`） |
| `-SkipUnitTests` | 1 を飛ばす |

結果のファイル（TRX）は `windows/WindowsLibraryExampleUITest/TestResults/test_windows/<日時>/` に出る（コミットしない）。失敗が 1 件でもあるか、OS の設定が戻っていなければ、終了コードは 1。

テストのカテゴリ:

| カテゴリ | 内容 |
|---|---|
| `Dialog` | 6.1 |
| `Notification` | 6.2 のうちバナー以外 |
| `NotificationBanner` | N-21、N-22（集中モードの切り替えを伴う） |
| `Clipboard` | 既存の 31 件と付録 B の追加分のうち、利用者の履歴を読み書きしないもの（遅延レンダリングのテストは履歴を一時的に無効にする） |
| `ClipboardHistory` | 付録 B のうち、履歴を有効にして利用者の履歴を使うもの（`Clear` を除く） |
| `ClipboardHistoryDestructive` | 履歴の `Clear`。**既定では実行しない。** スクリプトに `-IncludeDestructive` を付けたときだけ実行する（U-6）。スクリプトは環境変数 `NTK_UITEST_DESTRUCTIVE=1` を設定し、テストはそれが無いと `Inconclusive` で終わる。フィルタを付けない `dotnet test` でも消えないようにするため、カテゴリだけに頼らない |

computer use の確認手順書は、スクリプトの後に Claude のデスクトップアプリから実行する。

段階 0d で、今のコードで全件が通ることを確かめ、結果を `artifact/topics/windows-architecture/results/` に記録する。これが段階 1 〜 6 の判定の基準になる。

## 9. 作業の分け方

| 段階 | 内容 | 確かめ方 |
|---|---|---|
| 0b | 5.1 の AutomationId と 5.2 のボタン | 既存の Clipboard の UI テストが通る。5.2 のボタン以外の見た目が変わっていない |
| 0c | 4 章の基盤、6 章のテスト、7 章の手順書（3.6 と 3.7 の見込みは付録 C で確認済み）。調査用のコード（`Spike/`）は削除する | 新しいテストが今のコードで通る |
| 0d | 8 章のスクリプト | 全件が通り、結果を記録した |

## 10. 決定事項（2026-09-19）

| ID | 決めたこと | 決定 | 理由 |
|---|---|---|---|
| U-1 | スケジュール通知の待ち時間 | **サンプルに「5 秒後に予約」するボタンを足す**（5.2） | N-11 と N-12 でそれぞれ 60 秒以上待つことになり、段階ごとに実行するには遅い。段階 0b の「見た目も動作も変えない」の唯一の例外とする |
| U-2 | テストに必要な OS の設定（集中モード、クリップボードの履歴、アプリの通知）の扱い | **テストが切り替え、終わったら元に戻す**（3.6） | Clipboard の履歴は、履歴のテストでは有効、遅延レンダリングの発火のテストでは無効が必要で、1 回の実行の中で切り替えが要る。事前に人が設定する方式では全自動にならない。合わないテストを飛ばす方式は、飛ばしたことに気づきにくい。途中で強制終了すると設定が変わったまま残る弱点は、実行前の値を記録し、スクリプトの最後と次回の実行の最初に戻すことで補う |
| U-3 | Clipboard の追加テスト（付録 B）を段階 0 に含めるか | **含める** | 再編で最も大きく書き換わるのは Clipboard（4,665 行）で、その外部アプリとのやり取りや履歴は今は手動でしか確かめられない |
| U-4 | 複数ファイルの戻り値の形式（付録 A の注記） | **テストは今の形式のまま書く** | 段階 0 のテストは今の動作を固定するためのもの。形式を変えるかは段階 3 の C++ API の設計で決め、変えるならテストもそのとき合わせる |
| U-5 | N-20（アプリの通知を無効にしたときの動作）の確かめ方 | **テストの前に設定アプリを閉じ、通知センターのメニューから設定ページを開いてスイッチを操作する**（3.6） | レジストリでは切り替えられない。設定アプリが別の仮想デスクトップで開いていると操作できないので、先に閉じる |
| U-6 | 履歴の `Clear` のテスト | **明示したときだけ実行する**（`-IncludeDestructive`） | 利用者のピン留めしていない履歴がすべて消え、元に戻せない。そのほかの履歴のテストは毎回実行する |
| U-7 | バッジのグリフの種類（CU-02）の確かめ方 | **computer use をやめ、FlaUI で文字コードを確かめる**（N-14） | グリフはアイコン用フォントの文字として読め、alert は `U+EDAD` だった（段階 0c で判明）。FlaUI なら毎回同じ判定で、実行のコストもかからない。文字コードは Windows のシェルに依存し更新で変わりうるが、変わればテストが見た文字コードを出して失敗するので、気づかないまま通ることはない。そのときは一度だけ目視で alert であることを確かめ、テストの定数を直す |

## 付録 A. Dialog の事前確認（2026-09-19）

調査用のコード `windows/WindowsLibraryExampleUITest/Spike/DialogSpike.cs`（コミットしない）で、Dialog 画面の 6 つのボタンすべてを UI Automation で操作できるかを確かめた。

| ダイアログ | 操作 | 結果 |
|---|---|---|
| アラート | OK / キャンセル | `Result: 1` / `Result: 2` |
| ファイルを開く | キャンセル / `a.txt` を選ぶ | canceled / `filePath` がそのパス |
| 複数ファイル | `a.txt` と `b.txt` を選ぶ | `Result: 3`、`[0]` フォルダ、`[1]` `a.txt`、`[2]` `b.txt` |
| 保存 | `new.txt` | `savePath` がそのパス。ファイルは作られない |
| フォルダ | `f1` を選ぶ | `folderPath` がそのパス |
| 複数フォルダ | `f1` と `f2` を選ぶ | `Result: 2`、`[0]` `[1]` がフルパス |

経緯:

| 回 | やり方 | 結果 |
|---|---|---|
| 1 | サンプルのボタンを別スレッドから Invoke し、アプリのウィンドウをたどってダイアログを探す | 見つからなかった。ダイアログが開いたまま残り、次のボタンも見つからなくなった |
| 2 | ダイアログを Win32 の `EnumWindows` で探す | 0.27 秒で見つかったが、UI Automation の要素にする `FromHandle` が `UIA Timeout` になった |
| 3 | サンプルのボタンをマウスクリックで押す | ダイアログを要素にできた。ただし 1 つ下のボタン（`ShowFileDialog`）を押してしまった |
| 4 | ボタンの位置が動かなくなるまで待ってからクリックする | 正しいボタンを押せた。アラートは成功 |
| 5 | 決定ボタンを種類を問わず ID `1` で探す（「開く」は `SplitButton`）。複数選択はフルパスを引用符で並べる | 6 つすべて成功 |

**注記（段階 3 へ）**: 複数ファイルは「フォルダ + ファイル名」の形で、件数にフォルダを含む（2 ファイルで 3）。複数フォルダは 1 件ずつフルパスで、件数はフォルダの数（2 フォルダで 2）。同じ「複数選択」で戻り値の形式がそろっていない。段階 0 のテストは今の形式のまま書き（U-4）、この形式を引き継ぐか統一するかは段階 3 の C++ API の設計で決める。

## 付録 B. Clipboard の手動確認のうち、既存の UI テストに無いもの

出典は Clipboard のサンプルアプリ計画 v5 の 8 章。「外部」はテストのプロセスが外部のアプリとして読み書きすることを指す（3.7）。

| 出典 | 手動確認 | 自動化の方法 | 必要な設定 |
|---|---|---|---|
| 8.1 | CopyPlainText → メモ帳 | 外部で `CF_UNICODETEXT` を読み、同じ文字列 | — |
| 8.1 | CopyHtml → Word / ブラウザ（太字を保つ） | 外部で HTML 形式を読み、`<b>` を含む | — |
| 8.1 | CopyHtml → メモ帳（代わりの文字列） | 外部で `CF_UNICODETEXT` を読む | — |
| 8.1 | CopyFiles ⇔ エクスプローラー | 外部で `CF_HDROP` を読む。外部で `CF_HDROP` を書いて PasteFiles | — |
| 8.1 | CopyImage ⇔ ペイント | 外部で `CF_DIB` を読み、8x8 のヘッダーを確かめる。外部で書いて PasteImage | — |
| 8.1 | CopyMultipleFormats → Word / メモ帳 | 外部で形式を列挙し、それぞれを読む | — |
| 8.1 | GetPreferredFormat（4 通り） | 外部で各組み合わせを書いてから GetPreferredFormat | — |
| 8.2 | Init → 外部でコピー | 変更のログが出る | — |
| 8.2 | Uninit → 外部でコピー | 変更のログが出ない | — |
| 8.2 | Reserve → 外部で貼り付け | provider の問い合わせと書き込みのログ | 履歴を無効 |
| 8.2 | Reserve → アプリを正常終了 → 外部で貼り付け | 内容が残っている | 履歴を無効 |
| 8.2 | Reserve → 外部でコピー | 予約が破棄される | — |
| 8.3 | Availability | OS の設定と一致する | 履歴を有効 / 無効 |
| 8.3 | 履歴が無効で GetHistory | `HISTORY_DISABLED` | 履歴を無効 |
| 8.3 | GetHistory | 新しい順、時刻の文字列 | 履歴を有効 |
| 8.3 | Restore → 貼り付け | 復元した内容 | 履歴を有効 |
| 8.3 | Delete → GetHistory | 項目が無くなる | 履歴を有効 |
| 8.3 | Clear → GetHistory | ピン留めした項目だけが残る。サンプルからはピン留めできないので、テストが追加した項目が消えることを確かめる。**明示したときだけ実行**（U-6） | 履歴を有効 |
| 8.3 | コールバックを設定 → コピー | 履歴追加のログ | 履歴を有効 |
| 8.3 | SENSITIVE でコピー → Win+V | 履歴に追加されない。**Win+V の画面ではなく、履歴の追加のログと GetHistory で確かめる**（Win+V の画面は履歴の API と同じ一覧を表示する。段階 0c で変更） | 履歴を有効 |
| 8.3 | GetHistory → Cancel | `CANCELED` か先に成功のどちらか 1 回 | 履歴を有効 |

対象外:

- 8.3 `EXCLUDE_ROAMING` → 別のデバイス（2 台目のデバイスが必要）
- 8.3 設定変更のコールバック（`onHistoryEnabledChanged`。サンプルアプリ計画 8.3 の注記のとおり、OS 側の動作が信頼できない）
- 8.1 の Word・ブラウザ・ペイントでの見た目（形式の中身の確認で代える）

## 付録 C. 段階 0c の事前確認（2026-09-19）

3.6 と 3.7 の見込みを、段階 0c の本体に入る前に確かめた。調査用のコード（`windows/WindowsLibraryExampleUITest/Spike/`）はコミットしない。

| # | 確かめたこと | 方法 | 結果 |
|---|---|---|---|
| 1 | クリップボードの履歴の有効・無効を切り替えられるか | `EnableClipboardHistory` を書き換え、`Clipboard.IsHistoryEnabled()` で読む | 書き換えた直後に反映された。元の値（有効）に戻したことも API で確認した。**追記（段階 0c の本体）**: 無効にすると約 0.5 秒後にクリップボードが空になる（3.6） |
| 2 | アプリの通知の有効・無効を切り替えられるか | 下の経緯のとおり | 設定ページのスイッチで切り替えられた。無効のとき `GetSetting` は `DisabledForApplication`、ShowBasic は `Notifications are disabled` の案内（N-20 の期待どおり）。有効に戻すと `Enabled` に戻った |
| 3 | テストのプロセスが外部のアプリとしてクリップボードを読み書きできるか | サンプルの CopyPlainText をテストが読む。テストが書き込み、サンプルの監視と PastePlainText で確かめる | 読めた（`Hello from native-toolkit`）。書き込むとサンプルが変更のログ（`[Monitor] clipboard content changed`）を出し、PastePlainText で同じ文字列が返った |

2 の経緯:

| 回 | やり方 | 結果 |
|---|---|---|
| 1 | レジストリ `Notifications\Settings\<AUMID>` に `Enabled=0` を書く | OS の API は `Enabled` のまま。書いた値は削除して元に戻した |
| 2 | 通知センターのアプリのグループの設定ボタンを押し、開いた設定ページを探す | 見つからなかった。設定アプリは開いていたが、別の仮想デスクトップにあり隠された状態（cloaked）だった |
| 3 | 設定アプリを閉じてからやり直す | 設定アプリが開かなかった。グループの設定ボタンは設定アプリを開くのではなく、メニューを出すボタンだった |
| 4 | メニューの項目を調べる | `TurnOffNotificationsMenuItem`（すべての通知をオフ）、`GoToNotificationSettingsMenuItem`（通知の設定を開く）、`ChangePriorityMenuItem` があった |
| 5 | 設定アプリを閉じてから、`GoToNotificationSettingsMenuItem` で設定ページを開き、同じページのスイッチでオフ → オンにする | 成功。ページは約 5 秒で開いた |

`TurnOffNotificationsMenuItem` でもオフにはできるが、オフにするとこのアプリの通知が通知センターから消え、同じ経路でオンに戻せない。オフとオンを同じ設定ページで行うため、`GoToNotificationSettingsMenuItem` を使う。
