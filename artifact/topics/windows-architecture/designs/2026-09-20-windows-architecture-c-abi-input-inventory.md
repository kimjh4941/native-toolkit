# 今の C ABI が受け付ける入力の一覧

- 作成日: 2026-09-20
- 対象: `windows/WindowsLibrary/src/**`（段階 2 完了時点）
- 位置づけ: 段階 3 の T-14（C ABI を C++ API の上に載せ替える）の**突き合わせの基準**。設計書 `2026-09-20-windows-architecture-cpp-api-design.md` の 8.2・10 章はこの一覧から導出する
- 作り方: 設計書を見ずに**実装だけから**導出した。行番号は `windows/WindowsLibrary/src/` からの相対パス

**なぜ要るか**: サンプルアプリが使っていない入力は UI テストでは守れない。「baseline と一致」だけを完了条件にすると、今受け付けている入力が黙って落ちても気づけない。

## 1. Notification の JSON ペイロード

入口は `Show()`（`Notification/WindowsNotificationManager.cpp:818`）と `Schedule()`（`:864`）。どちらも `JsonObject::TryParse` で解析し、オブジェクトでなければ `INVALID_PAYLOAD`(3)。実行前に `Setting() != 0` なら `DISABLED`(2)。以降は `BuildPayload`（`:617`）→ `BuildFromJson`（`:530`）→ `ValidatePayload`（`:489`）。

### 1.1 最上位のキー

| キー | 型 | 受け付ける値 | 省略時 | 備考 | 行 |
|---|---|---|---|---|---|
| `title` | 文字列 | 任意 | テキスト行を出さない | 非文字列は WinRT 例外 → `HRESULT_FAILURE`(5) | `:540` |
| `body` | 文字列 | 任意 | 2 行目を出さない | `title` の次に追加される（順序が意味を持つ） | `:542` |
| `tag` | 文字列 | 任意 | 未設定 | builder と `DeliverPayload` の両方で使う | `:544`、`:632` |
| `group` | 文字列 | 任意 | 未設定 | 同上 | `:546`、`:634` |
| `scenario` | 文字列 | `"reminder"` / `"alarm"` / `"urgent"` / `"incomingCall"` のみ | OS の既定 | **それ以外は黙って無視**（エラーにならない） | `:549` |
| `duration` | 文字列 | `"long"` のみ意味を持つ | short | `audio.loop` の検証にも使う | `:493`、`:558` |
| `buttons` | オブジェクトの配列 | 1.2 | 無し | **5 個を超えると `INVALID_PARAMETER`(7)**。順序は保たれる | `:505`、`:660` |
| `textBoxes` | オブジェクトの配列 | 1.3 | 無し | 個数の上限は無い | `:568` |
| `comboBoxes` | オブジェクトの配列 | 1.4 | 無し | 個数の上限は無い | `:587`、`:697` |
| `appLogo` | **オブジェクト** | 1.5 | 無し | `uri` が無いと例外 → 5 | `:734` |
| `heroImage` | 文字列（URI） | `winrt::Uri` が解析できるもの | 無し | 解析失敗は例外 → 5 | `:743` |
| `inlineImage` | 文字列（URI） | 同上 | 無し | 同上 | `:746` |
| `audio` | オブジェクト | 1.6 | 既定音・ループ無し | | `:750` |
| `progress` | オブジェクト | 1.7 | 進捗バー無し | | `:794` |
| `attribution` | 文字列 | 任意 | 無し | `SetAttributionText` | `:604` |
| `timestamp` | 数値 | **絶対時刻・Unix 秒** | 配信時刻 | `scheduleNotification` の引数は**ミリ秒**なので単位が違う | `:607` |
| `expiration` | 数値 | **相対の秒数**（`now() + 秒`） | 無期限 | **`Schedule` の経路では完全に無視される** | `:637`、`:118` |
| `expiresOnReboot` | 真偽 | `true` / `false` | false | packaged のみ。**unpackaged は無視する** | `:642`、`:121` |

**最上位に `arguments` と `invokeUri` は無い。** 引数と URI の排他はボタン単位の規則である。**未知のキーは黙って無視される**（厳密な構造体にすると、今通っている入力が無言で落ちる）。

### 1.2 `buttons[]` の項目

| キー | 型 | 備考 | 行 |
|---|---|---|---|
| `label` | 文字列 | 実質必須（無いと例外 → 5） | `:670` |
| `args` | **オブジェクト（文字列 → 文字列）** | **キー名は呼び出し側が自由に決める**。値が非文字列なら例外 → 5 | `:671`、`:687` |
| `invokeUri` | 文字列（URI） | `args` と**排他**。両方あると `INVALID_PARAMETER`(7) | `:672`、`:674` |

### 1.3 `textBoxes[]` の項目

| キー | 備考 | 行 |
|---|---|---|
| `id` | 必須（無いと例外 → 5） | `:573` |
| `placeholder` | 省略可 | `:574` |
| `title` | 省略可。**両方とも無い場合は 1 引数版の `AddTextBox(id)` を呼ぶ** | `:574` |

### 1.4 `comboBoxes[]` の項目

| キー | 備考 | 行 |
|---|---|---|
| `id` | 必須 | `:707` |
| `title` | 省略可 | `:709` |
| `items` | オブジェクトの配列。各項目は `id` と **`label`**（どちらも必須、順序は保たれる） | `:712` |
| `defaultSelection` | `items[].id` を指すはずだが**照合していない** | `:721` |

### 1.5 `appLogo` オブジェクト

| キー | 値 | 行 |
|---|---|---|
| `uri` | 必須 | `:740` |
| `crop` | `"circle"` のときだけ `ImageCrop::Circle`。それ以外・省略は `Default` | `:737` |

### 1.6 `audio` オブジェクト

| キー | 受け付ける値 | 備考 | 行 |
|---|---|---|---|
| `type` | `"mute"` / `"uri"` / それ以外（イベント音） | 既定は `"event"`。**`"mute"` は即座に戻るので `loop` と `event` を捨てる** | `:757` |
| `uri` | 文字列 | `type == "uri"` のとき必須。無ければ `INVALID_PARAMETER`(7) | `:771` |
| `loop` | 真偽 | `true` のとき `duration == "long"` が必須。違反は 7 | `:497`、`:765` |
| `event` | `"reminder"` / `"alarm"` / `"loopingAlarm"` / `"loopingCall"` | 未知の値は既定音。**`"alarm"` と `"loopingAlarm"` は同じ enum に潰れる**。`"loopingCall"` は `Call` | `:781` |

### 1.7 `progress` オブジェクト

| キー | 備考 | 行 |
|---|---|---|
| `title` | テンプレートにのみ反映 | `:802` |
| `value` | 数値。範囲の検査は無い。省略時 0.0 | `:649`、`:805` |
| `valueStr` | **キーの有無**が `BindValueStringOverride()` の有無を決める | `:651`、`:806` |
| `status` | 同様に `BindStatus()` の有無を決める | `:653`、`:808` |

初期の `ProgressData` の sequence number は **1 固定**（packaged `:126`、classic `Data/WindowsClassicActivator.cpp:492`）。classic 側のデータキーは `progressValue` / `progressValueString` / `progressStatus`。

### 1.8 バッジ（`setBadge`）

| 値 | 意味 | 行 |
|---|---|---|
| 正の数 | 数字バッジ。**上限の検査なし** | `:182` |
| 0 | 消去 | `:179` |
| -1〜-6 | グリフ表 `alert` / `activity` / `newMessage` / `available` / `busy` / `away` | `:188` |
| -6 未満 | `INVALID_PARAMETER`(7) | `:982` |
| 任意 | unpackaged では `NOT_SUPPORTED`(8) | `Data/WindowsClassicActivator.cpp:567` |

### 1.9 ライブラリが**生成する**活性化の JSON

| 経路 | キーの集合 | 備考 | 行 |
|---|---|---|---|
| packaged | `Arguments()` の全キー（呼び出し側が `buttons[].args` に入れたもの + SDK が足すもの）+ `UserInput()` の全キー（`textBoxes[].id` と `comboBoxes[].id`） | 値はすべて文字列。**同名のとき user input が args を上書きする** | `:470` |
| classic（実行中） | `key=value&key2=value2` を解析したもの + 入力データ | **パーセントデコードもエスケープも無い**。`=` の無い対は捨てられる | `Data/WindowsClassicActivator.cpp:92` |
| classic（cold start） | コマンドラインの `-ToastActivated` 以降を同じ規則で解析 | **入力値は取れない**（配列が空） | 同 `:131`、消費は `:388` |

`getAllNotifications` は `[{"id":<数値>,"tag":"...","group":"..."}]` を `_TRUNCATE` でバッファへ書く。**必要サイズは返さない**（`:251`）。

### 1.10 キーが**有って空**のとき（T-17 で追加）

1.1〜1.7 は「渡したとき」と「省略したとき」を書いているが、**3 つ目の場合**を書いていなかった。実装は `HasKey` で分岐するため、**空文字列は値であって不在ではない**。T-14 で `NotificationContent` に載せ替える際、空文字列を「無し」として扱うと次が変わる。

下の表は **`WindowsLibraryTest/NotificationPayloadTest.cpp` が実装から導出**したものであり、読みによる推定ではない。同テストは T-14 の載せ替え後も通らなければならない。

| # | 入力 | 空のときの結果 | 省略したときの結果 | 同じか |
|---|---|---|---|---|
| 1 | `title: ""` | 空の `<text/>` を出す | 何も出さない | **違う** |
| 2 | `body: ""` | 2 行目に空の `<text/>` を出す | 何も出さない | **違う** |
| 3 | `attribution: ""` | 空の attribution 要素を出す | 何も出さない | **違う** |
| 4 | `progress.title: ""` | `title=''` を出す | 属性を出さない | **違う** |
| 5 | `heroImage: ""` | `Uri{""}` が例外 → `HRESULT_FAILURE`(5) | 画像なしで成功 | **違う** |
| 6 | `inlineImage: ""` | 同上 → 5 | 同上 | **違う** |
| 7 | `audio.uri: ""`（`type=uri`） | `Uri{""}` が例外 → **5** | キーが無い場合は `INVALID_PARAMETER`(**7**) | **違う**（しかも 5 と 7 で異なる） |
| 8 | `buttons[].invokeUri: ""` | `Uri{""}` が例外 → 5 | `args` 側として扱う | **違う** |
| 9 | `textBoxes[].placeholder: ""` | 3 引数版 `AddTextBox` → `placeHolderContent` 属性が出る | 1 引数版 → 属性が出ない | **違う** |
| 10 | `buttons[].args: {}` + `invokeUri` | 排他違反 → `INVALID_PARAMETER`(7) | `invokeUri` だけなら成功 | **違う**（排他は**キーの有無**で判定する） |
| 11 | `comboBoxes[].title: ""` | 省略時と同じ（builder が空値を落とす） | 同左 | 同じ |
| 12 | `comboBoxes[].defaultSelection: ""` | 同上 | 同左 | 同じ |
| 13 | `tag: ""` / `group: ""` | 省略時と同じ | 同左 | 同じ |
| 14 | `scenario: ""` / `audio.event: ""` | 未知の値として黙って既定 | 同左 | 同じ |

**11 と 12 は読みでは逆に見える**（`HasKey` が真なので `Title()` と `SelectedItem()` を呼ぶ）。空値を落としているのは App SDK の builder 側であり、呼び出し規約からは分からない。実装から導出する理由がここにある。

**結論**: 1〜10 の 10 件は、空文字列を「無し」とする表現では再現できない。`NotificationContent` の該当フィールドは**不在と空を区別できる型**が要る（4 章の 16 番）。

### 1.11 Clipboard と Dialog に同じ問題が無い理由（T-17 で確認）

| 機能 | 理由 |
|---|---|
| Clipboard `copyMultipleFormats` | 「どのペイロードか」を `FormatPayload` の variant が**明示的に**持つ。JSON 側は `HasKey` で決めるが、その判定はブリッジが行って variant に載せるため、空文字列に意味を推測させない |
| Clipboard `copyFiles` / `reserveDeferredFormats` | 配列の要素に有無の分岐が無い。空の形式名は今も `RegisterClipboardFormatW("")` が 0 を返して `INVALID_PARAMETER` であり、C++ API も同じ検査を通る |
| Clipboard の同期 API | 引数が `wstring_view` で、**空と不在を呼び出し側が区別しない**（どちらも空の内容として扱う）のが元からの契約 |
| Dialog | JSON を使わない。フラグ語とフィルター文字列は S-3 の逃げ道でブリッジが内部層へ素通しする |

## 2. Dialog の Win32 フラグと戻り値

| # | 関数 | フラグ | 呼び出し側が変えられるか | フィルター | タイトル | オーナー | バッファ | 戻り値 |
|---|---|---|---|---|---|---|---|---|
| 1 | `showAlertDialog`（`Dialog/WindowsDialogManager.cpp:498`、実装 `:49`） | `buttons \| icon \| defbutton \| options` を**そのまま** `MessageBoxW` へ | **全面的に可能**。`MB_*` の全域（`MB_HELP`、`MB_SETFOREGROUND`、`MB_RTLREADING` など）。検証なし | - | そのまま渡す | **`nullptr` 固定** | 無し | `MessageBoxW` のボタン ID（`IDOK`=1〜`IDCONTINUE`=11）。**0 が失敗**で `*pError = GetLastError()`。成功時は `*pError = 0` | 
| 2 | `showFileDialog`（`:537`、実装 `:87`） | `OFN_PATHMUSTEXIST \| OFN_FILEMUSTEXIST` 固定 | 不可 | `filter` が null なら `L"All Files\0*.*\0"` | **設定できない** | `nullptr` | 先頭で全体を `ZeroMemory`。キャンセル・失敗は `buffer[0]=L'\0'` | `BOOL`。**キャンセルでも `TRUE`** で `*pError = -1`。失敗は `FALSE` + `CommDlgExtendedError()`。**成功時に `*pError` を 0 にしない**（既存の不具合。段階 3 では再現する） |
| 3 | `showMultiFileDialog`（`:563`、実装 `:138`） | 上に `OFN_ALLOWMULTISELECT \| OFN_EXPLORER` を追加 | 不可 | 同上 | 設定できない | `nullptr` | `dir\0file1\0…\0\0`（複数）、単一選択は `fullpath\0` | `int` = **NUL 区切りの文字列の数**。1 件選択 → **1**、N>1 件 → **N+1**。キャンセル → 0 + `*pError=-1`、失敗 → -1 |
| 4 | `showFolderDialog`（`:612`、実装 `:205`） | `GetOptions() \| FOS_PICKFOLDERS \| FOS_FORCEFILESYSTEM` | 不可 | - | `title` が非 null のときだけ `SetTitle`。**`L"Select Folder"` は C++ の既定引数で、C の入口からは届かない** | `Show(nullptr)`。**毎回 `CoInitializeEx(APARTMENTTHREADED)`** し、成功時のみ解除 | 先頭で零化しない。溢れたら `buffer[0]=0` + `ERROR_INSUFFICIENT_BUFFER`（**必要サイズは返さない**） | `BOOL`。キャンセルでも `TRUE` + `*pError=-1` |
| 5 | `showMultiFolderDialog`（`:637`、実装 `:312`） | 上に `FOS_ALLOWMULTISELECT` を追加 | 不可 | - | 同上 | 同上 | `p1\0p2\0…\0\0`。1 件でも入らなければ**全体を破棄** | `int` = `GetCount()`。キャンセル → 0 + `*pError=-1`。**成功で `count==0` のときもキャンセルと同じ 0**（`*pError` で区別）。失敗 → -1。**成功時と溢れ時に `Release()` を呼んでいない**（既存のリーク） |
| 6 | `showSaveFileDialog`（`:676`、実装 `:438`） | `OFN_PATHMUSTEXIST \| **OFN_OVERWRITEPROMPT**` | 不可（`def_ext` だけが追加の調整点） | 同上 | 設定できない | `nullptr` | 同 #2 | `BOOL`。キャンセルでも `TRUE` + `*pError=-1` |

共通: **6 つともオーナー HWND・初期ディレクトリ・既定ファイル名・フィルター番号を受け取らない**。`pError == nullptr` は許容。**`buffer == nullptr` は検査していない**。

## 3. Clipboard の JSON とバッファ

### 3.1 `copyFiles(pathsJson, options, pError)`

- **文字列の配列**。null は `INVALID_PARAMETER`(1)、解析失敗も同じ（`bad_alloc` だけ `OUT_OF_MEMORY`(8)）
- 空配列・空文字列の要素は `INVALID_PARAMETER`
- パスの存在も書式も検査しない。**配列の順序がドロップの順序になる**
- 書き込むのは `CF_HDROP` のみ（`Clipboard/Domain/WindowsClipboardFormats.cpp:203`、`Data/WindowsClipboardCore.cpp:306`）

### 3.2 `copyMultipleFormats(itemsJson, options, pError)`

**オブジェクトの配列。情報量の多い順に並べ、その順序で `SetClipboardData` を呼ぶ**（順序が意味を持つ）。空配列は `INVALID_PARAMETER`。

| キー | 値 | 備考 | 行 |
|---|---|---|---|
| `format` | `"CF_UNICODETEXT"` / `"CF_TEXT"` / `"CF_HDROP"` / `"CF_DIB"` / `"CF_DIBV5"` / `"CF_BITMAP"` の別名、またはそれ以外の**任意の文字列**（`RegisterClipboardFormatW`） | 空・解決不能は `INVALID_PARAMETER`。**配列内で形式 ID が重複したらエラー** | `Clipboard/WindowsClipboardManager.cpp:499`、`:20` |
| `text` | 任意 | 3 種のうち**ちょうど 1 つ**が必要 | `:505` |
| `html` | HTML の**断片**（`BuildCfHtml` が完全な CF_HTML に包む） | 溢れたら `INVALID_PARAMETER` | `:547` |
| `base64` | 厳密な base64（空白は除去、長さ %4==0） | 解析失敗は `INVALID_PARAMETER`、`CF_DIB` / `CF_DIBV5` / `CF_HDROP` の構造検証の失敗は `INVALID_DATA`(6) | `:557` |

種別と形式の対応（`WindowsClipboardFormats.cpp:368`）

| 形式 | `text` | `html` | `base64` |
|---|---|---|---|
| `CF_UNICODETEXT` / `CF_TEXT` | 可 | 不可 | 不可 |
| **`"HTML Format"`（名前の完全一致で判定）** | 不可 | 可 | 不可 |
| `CF_HDROP` / `CF_DIB` / `CF_DIBV5` | 不可 | 不可 | 可 |
| **`CF_BITMAP`** | 不可 | 不可 | **不可（全種別を拒否）** |
| その他の登録形式 | 不可 | 不可 | 可 |

`CF_TEXT` + `text` は **ANSI（`CP_ACP`）に変換**される（`:31`、`:527`）。

### 3.3 `reserveDeferredFormats(formatNamesJson, provider, context, pError)`

- **文字列の配列**。空・null・解決不能は `INVALID_PARAMETER`
- **重複は黙って上書きされる**（`copyMultipleFormats` がエラーにするのと非対称）
- オーナー UI スレッド限定（`WRONG_THREAD`(14)）
- `context` は不透明な `void*` としてそのままコールバックへ渡る

### 3.4 書き込みオプション（6 つの copy API 共通）

| 定数 | 値 | 効果 |
|---|---|---|
| `NONE` | `0x0` | 無し |
| `EXCLUDE_HISTORY` | `0x1` | `"CanIncludeInClipboardHistory"` に DWORD `0` を置く |
| `EXCLUDE_ROAMING` | `0x2` | `"CanUploadToCloudClipboard"` に DWORD `0` を置く |
| `SENSITIVE` | `0x3` | 上 2 つの別名（独立したビットではない） |
| `0x3` 以外のビット | - | **書き込み前に `INVALID_PARAMETER`** |

マーカーの配置に失敗した場合は best-effort ではなく、`EmptyClipboard` で巻き戻して `UNKNOWN`(19)、巻き戻しも失敗なら `PARTIAL_STATE`(13)。

### 3.5 paste 側のバッファ規約

`WriteStringToBuffer`（`:41`）は **wchar_t 数（NUL を含む）**、`WriteBytesToBuffer`（`:65`）は **バイト数（終端なし）** を返す。どちらも `buffer == nullptr` またはサイズ不足で必要サイズを返し `BUFFER_TOO_SMALL`(7)。**戻り値 0 は常にエラー**で、長さ 0 の意味では使わない。

| 関数 | 単位 | 内容 |
|---|---|---|
| `pastePlainText` / `pasteHtml` / `pasteFiles` / `getClipboardFormats` / `getPreferredClipboardFormat` | wchar_t（NUL 含む） | `pasteFiles` と `getClipboardFormats` は JSON 配列。**該当なしの `getPreferredClipboardFormat` は空文字列で戻り値 1** |
| `pasteImage` / `pasteCustomFormat` | バイト | 生のブロブ |
| `ClipboardRenderCallback` | バイト | 2 相。**2 回目の必要サイズが 1 回目と違うとその形式を黙って捨てる**。0 でも捨てる。例外でも捨てる |

`hasClipboardFormat` は問い合わせるだけで `RegisterClipboardFormatW` を呼ぶため、**形式を登録してしまう**（`:607`）。

## 4. 型で表しきれないもの（逃げ道が要る）

| # | 内容 | 影響する API |
|---|---|---|
| 1 | `buttons[].args` の**自由なキー値の辞書** | `showNotification` / `scheduleNotification` |
| 2 | 活性化 JSON の**開いたキー空間**（呼び出し側の引数 + SDK のキー + 入力欄の id。衝突は後勝ち） | `NotificationInvokedCallback` |
| 3 | 未知のキーを黙って受け入れること | 同上 |
| 4 | classic の `key=value&...` のエスケープ無しの並び | cold start / classic 活性化 |
| 5 | **`MB_*` の生のフラグ語 4 つ** | `showAlertDialog` |
| 6 | **埋め込み NUL を含むフィルター文字列**と、そのペアの順序 | ファイル系 3 API |
| 7 | 戻り値が件数でなく文字列数であること（N 件 → N+1） | `showMultiFileDialog` |
| 8 | 配列の順序 = クリップボードの優先順位 | `copyMultipleFormats` |
| 9 | 任意の形式名（`RegisterClipboardFormatW` の無限の名前空間） | 5 つの API |
| 10 | base64 を経由した任意のバイト列 | `copyMultipleFormats` |
| 11 | 生のバイト列と `void* context` の 2 相プロトコル | `copyImage` / `copyCustomFormat` / 遅延レンダリング |
| 12 | ビット語としての `options` | 6 つの copy API |
| 13 | **符号で意味が変わる badge の `int`** | `setBadge` |
| 14 | **3 種類の時刻表現**（`expiration` = 相対秒、`timestamp` = 絶対 Unix 秒、`scheduleNotification` の引数 = 絶対 Unix ミリ秒） | 通知 |
| 15 | backend による黙った無視（`expiresOnReboot` は unpackaged で、`expiration` と `progress` は `Schedule` で無視。`mute` は `loop` / `event` を捨てる） | 通知 |
| 16 | **キーが有って空**であることと、キーが無いことの区別（1.10 の 10 件） | `showNotification` / `scheduleNotification` |
