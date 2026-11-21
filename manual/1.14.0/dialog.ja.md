# ダイアログ機能

言語:

- 日本語（このページ）
- English: [dialog.md](dialog.md)
- 한국어: [dialog.ko.md](dialog.ko.md)

← [マニュアルトップに戻る](index.ja.md)

---

## 目次

- [Android](#android)
  - [AndroidDialogManager](#androiddialogmanager)
    - [基本ダイアログ](#基本ダイアログ)
    - [確認ダイアログ](#確認ダイアログ)
    - [シングル選択ダイアログ](#シングル選択ダイアログ)
    - [マルチ選択ダイアログ](#マルチ選択ダイアログ)
    - [入力ダイアログ](#入力ダイアログ)
    - [ログインダイアログ](#ログインダイアログ)
    - [コルーチンで待つ](#コルーチンで待つ)
    - [戻る操作や外側のタップで閉じる](#戻る操作や外側のタップで閉じる)
    - [ダイアログをキャンセルする](#ダイアログをキャンセルする)
  - [C ABI](#c-abi)
    - [アラートダイアログと確認ダイアログ](#アラートダイアログと確認ダイアログ)
    - [選択リストのダイアログ](#選択リストのダイアログ)
    - [入力ダイアログとログインダイアログ](#入力ダイアログとログインダイアログ)
- [iOS](#ios)
  - [iOSDialogManager](#iosdialogmanager)
- [Windows](#windows)
  - [NativeToolkit::Dialog](#nativetoolkitdialog)
    - [ShowAlert - 基本ダイアログ](#showalert---基本ダイアログ-1)
    - [ShowOpenFile - ファイル選択ダイアログ](#showopenfile---ファイル選択ダイアログ)
    - [ShowOpenFiles - 複数ファイル選択ダイアログ](#showopenfiles---複数ファイル選択ダイアログ)
    - [ShowPickFolder - フォルダー選択ダイアログ](#showpickfolder---フォルダー選択ダイアログ)
    - [ShowPickFolders - 複数フォルダー選択ダイアログ](#showpickfolders---複数フォルダー選択ダイアログ)
    - [ShowSaveFile - 保存ダイアログ](#showsavefile---保存ダイアログ)
  - [C ABI](#c-abi-1)
    - [メッセージボックス](#メッセージボックス)
    - [ファイルの選択](#ファイルの選択)
    - [フォルダーの選択](#フォルダーの選択)
- [macOS](#macos)
  - [MacDialogManager](#macdialogmanager)

---

## Android

Android ライブラリは、同じダイアログを 2 つの公開 API から提供します。どちらも実装は 1 つで、サンプルアプリは Kotlin API を使用しています。

| API | 名前 | パッケージ / ヘッダー | AAR（Maven 座標） |
|---|---|---|---|
| Kotlin API | `AndroidDialogManager` | `com.jonghyunkim.nativetoolkit.dialog` | `android-native-toolkit-2.0.0.aar`（`io.github.kimjh4941:android-native-toolkit:2.0.0`） |
| C ABI | `ntk_dialog_*` | `<NativeToolkitC/Dialog.h>` | `android-native-toolkit-capi-2.0.0.aar`（`io.github.kimjh4941:android-native-toolkit-capi:2.0.0`） |

- ライブラリには minSdk 31 と compileSdk 36 が必要です。Kotlin のアプリには Kotlin 2.1 以降が必要です。
- 1.x のライブラリ向けに書いたコードは、パッケージ名と API が変わったため更新が必要です。[Android ライブラリを 2.0.0 へ移行する](index.ja.md#android-ライブラリを-200-へ移行する) を参照してください。`AndroidDialogFragment` とそのリスナーは引き続き `com.jonghyunkim.nativetoolkit.dialog` で公開されていますが、新しいコードでは `AndroidDialogManager` を使用してください。

### AndroidDialogManager

- `AndroidDialogManager.getInstance(context)` は、プロセス全体で 1 つのインスタンスを返します。`Context` は何でも構わず、保持されません。
- Activity や `FragmentManager` は渡しません。ダイアログは、アプリの前面にある Activity に表示されます。その Activity が `FragmentActivity` でない場合（例えば素の `ComponentActivity` やゲームの Activity）は、ライブラリがダイアログを載せるための透明な Activity を自前で開きます。
- アプリが前面にある必要があります。バックグラウンドから呼び出すと、リクエストは `DialogResult.Failed(DialogError.NOT_FOREGROUND)` で終わります。
- ライブラリはアプリの起動時に androidx.startup で自身を初期化するため、先に呼び出すものはありません。Startup のイニシャライザーを外したアプリは、最初の Activity の `onCreate` から、その Activity を渡して `LibraryRuntime.ensureInitialized(activity)`（`com.jonghyunkim.nativetoolkit.common.runtime`）を呼び出します。それまでのリクエストは `DialogResult.Failed(DialogError.NOT_INITIALIZED)` で終わります。アプリケーションコンテキストだけを渡すと、ライブラリはすでに画面にある Activity を把握できず、次の Activity が開始するまでダイアログは `DialogError.NOT_FOREGROUND` で終わります。
- `show(request, onResult)` はどのスレッドからでも呼び出せます。戻り値は `cancel` に渡すリクエスト ID（`Long`）です。`onResult` はメインスレッドでちょうど 1 回呼ばれ、`show` の中で呼ばれることはありません。
- ダイアログは、回転などの構成変更の後も残ります。ライブラリがダイアログを復元し、結果は同じ `onResult` に届きます。
- 不正なリクエスト（空の項目リスト、項目数と要素数が異なる `checked` リスト、範囲外の `checkedIndex`）を渡すと、`show` は `IllegalArgumentException` をスローします。

結果は、次の 4 つの `DialogResult` のいずれかです。

| 結果 | 返る場面 |
|---|---|
| `DialogResult.Button(which, text, value)` | 利用者がボタンを押した場合です。`which` は `DialogButton.POSITIVE` または `DialogButton.NEGATIVE` で、`text` はそのラベルです |
| `DialogResult.Dismissed` | 利用者が戻る操作または外側のタップでダイアログを閉じた場合です（`DialogOptions` が許可している場合のみ） |
| `DialogResult.Canceled(reason)` | 応答がないままリクエストが終わった場合です。`cancel` の後は `CancelReason.REQUESTED`、ダイアログを表示していた Activity が完全に破棄された場合は `CancelReason.HOST_DESTROYED` です |
| `DialogResult.Failed(error)` | ダイアログを表示できなかった場合です。`DialogError.NOT_INITIALIZED`、`NOT_FOREGROUND`、`HOST_START_FAILED`（透明な Activity が開始しなかった）、`SHOW_FAILED` のいずれかです |

`Button.value` は、利用者が入力した内容を持ちます。否定ボタンでは常に `DialogValue.None` です。`DialogValue.Text` と `DialogValue.Login` は `toString()` で中身を隠すため、結果を出力しても利用者の入力はログに残りません。

| リクエスト | 肯定ボタンの `value` |
|---|---|
| `DialogRequest.Alert`, `DialogRequest.Confirm` | `DialogValue.None` |
| `DialogRequest.SingleChoice` | `DialogValue.SingleChoice(index)`。何も選択されていない場合、`index` は `null` です |
| `DialogRequest.MultiChoice` | `DialogValue.MultiChoice(checked)`。項目ごとに 1 つの `Boolean` です |
| `DialogRequest.TextInput` | `DialogValue.Text(text)` |
| `DialogRequest.Login` | `DialogValue.Login(username, password)` |

#### 基本ダイアログ

- メッセージとボタン 1 つを表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

// Context は何でも構いません。保持されません。
val manager = AndroidDialogManager.getInstance(context)

val request = DialogRequest.Alert(
    // タイトルを設定します。必須項目です。
    title = "Hello from Android",
    // メッセージを設定します。必須項目です。
    message = "This is a native Android dialog!",
    // ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    buttonText = "OK",
    // 戻る操作と外側のタップでダイアログを閉じるかを設定します。未設定の場合、どちらでも閉じます。
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

// cancel() に渡すリクエスト ID を返します。
// リクエストが不正な場合は IllegalArgumentException をスローします。
val requestId = manager.show(request) { result ->
    // メインスレッドで 1 回だけ呼ばれます。
    when (result) {
        is DialogResult.Button -> Log.d(TAG, "button: ${result.which} (${result.text})")
        DialogResult.Dismissed -> Log.d(TAG, "Dismissed")
        is DialogResult.Canceled -> Log.d(TAG, "Canceled: ${result.reason}")
        is DialogResult.Failed -> Log.d(TAG, "Unavailable: ${result.error}")
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowDialog.png" alt="Example_AndroidDialogFragment_ShowDialog" width="400" />
</p>

#### 確認ダイアログ

- メッセージと、否定ボタン・肯定ボタンを表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogButton
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

val request = DialogRequest.Confirm(
    // タイトルを設定します。必須項目です。
    title = "Confirmation",
    // メッセージを設定します。必須項目です。
    message = "Do you want to proceed with this action?",
    // 否定ボタンのテキストを設定します。未設定の場合、"No" が使用されます。
    negativeText = "No",
    // 肯定ボタンのテキストを設定します。未設定の場合、"Yes" が使用されます。
    positiveText = "Yes",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    when (result) {
        is DialogResult.Button -> {
            if (result.which == DialogButton.POSITIVE) {
                // 利用者が "Yes" を押しました。
            }
        }
        else -> Log.d(TAG, "result: $result")
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowConfirmDialog.png" alt="Example_AndroidDialogFragment_ShowConfirmDialog" width="400" />
</p>

#### シングル選択ダイアログ

- 1 つの項目を選択できるリストを表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.SingleChoice(
    // タイトルを設定します。必須項目です。
    title = "Please select one",
    // 選択肢を設定します。必須項目で、空にはできません。
    items = listOf("Option 1", "Option 2", "Option 3"),
    // 最初に選択しておく項目を設定します。選択しない場合は null です。未設定の場合、0 が使用されます。
    checkedIndex = 0,
    // 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    negativeText = "Cancel",
    // 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    positiveText = "OK",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        // 肯定ボタンでは DialogValue.SingleChoice、否定ボタンでは DialogValue.None です。
        val value = result.value
        if (value is DialogValue.SingleChoice) {
            // 選択された項目の index です。何も選択されていない場合は null です。
            Log.d(TAG, "button: ${result.which}, index: ${value.index}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowSingleChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowSingleChoiceItemDialog" width="400" />
</p>

#### マルチ選択ダイアログ

- 任意の数の項目を選択できるリストを表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.MultiChoice(
    // タイトルを設定します。必須項目です。
    title = "Multiple Selection",
    // 選択肢を設定します。必須項目で、空にはできません。
    items = listOf("Option 1", "Option 2", "Option 3", "Option 4"),
    // 最初の選択状態を設定します。必須項目で、項目ごとに 1 つの値を指定します。
    checked = listOf(false, true, false, true),
    // 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    negativeText = "Cancel",
    // 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    positiveText = "OK",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.MultiChoice) {
            // 項目ごとに 1 つの値です。選択されている項目は true です。
            Log.d(TAG, "button: ${result.which}, checked: ${value.checked}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowMultiChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowMultiChoiceItemDialog" width="400" />
</p>

#### 入力ダイアログ

- メッセージと入力欄 1 つを表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.TextInput(
    // タイトルを設定します。必須項目です。
    title = "Text Input",
    // メッセージを設定します。必須項目です。
    message = "Please enter your name",
    // ヒントを設定します。未設定の場合、空文字列が使用されます。
    hint = "Enter here...",
    // 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    negativeText = "Cancel",
    // 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    positiveText = "OK",
    // 入力欄が空のときに肯定ボタンを押せるかを設定します。未設定の場合、false が使用されます。
    enablePositiveWhenEmpty = false,
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.Text) {
            // value.text は利用者が入力した文字列です。文字列そのものではなく長さをログに出します。
            Log.d(TAG, "button: ${result.which}, textLength: ${value.text.length}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowTextInputDialog.png" alt="Example_AndroidDialogFragment_ShowTextInputDialog" width="400" />
</p>

#### ログインダイアログ

- メッセージと、ユーザー名・パスワードの入力欄を表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.Login(
    // タイトルを設定します。必須項目です。
    title = "Login",
    // メッセージを設定します。必須項目です。
    message = "Please enter your credentials",
    // ユーザー名のヒントを設定します。未設定の場合、"Username" が使用されます。
    usernameHint = "Username",
    // パスワードのヒントを設定します。未設定の場合、"Password" が使用されます。
    passwordHint = "Password",
    // 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    negativeText = "Cancel",
    // 肯定ボタンのテキストを設定します。未設定の場合、"Login" が使用されます。
    positiveText = "Login",
    // いずれかの入力欄が空のときに肯定ボタンを押せるかを設定します。未設定の場合、false が使用されます。
    enablePositiveWhenEmpty = false,
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.Login) {
            // value.username と value.password は利用者が入力した値です。パスワードは決してログに出さないでください。
            Log.d(TAG, "usernameLength: ${value.username.length}, passwordLength: ${value.password.length}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowLoginDialog.png" alt="Example_AndroidDialogFragment_ShowLoginDialog" width="400" />
</p>

#### コルーチンで待つ

- コールバックを渡さない `show(request)` は `suspend` 関数です。応答として `DialogResult.Button` または `DialogResult.Dismissed`（どちらも `DialogResult.Answer`）を返します。
- 応答がないまま終わったリクエストは `DialogDomainError.Canceled(reason)` を、表示できなかったダイアログは `DialogDomainError.Unavailable(error)` をスローします。
- コルーチンをキャンセルすると、ダイアログが閉じます。コルーチンを画面に結び付けておくと（Compose では `rememberCoroutineScope()`）、画面を離れたときにダイアログも閉じます。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogDomainError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import kotlinx.coroutines.launch

val manager = AndroidDialogManager.getInstance(context)
val request = DialogRequest.Confirm(
    title = "Confirmation",
    message = "Do you want to proceed with this action?",
    negativeText = "No",
    positiveText = "Yes",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

scope.launch {
    try {
        when (val answer = manager.show(request)) {
            is DialogResult.Button -> Log.d(TAG, "button: ${answer.which} (${answer.text})")
            DialogResult.Dismissed -> Log.d(TAG, "Dismissed")
        }
    } catch (e: DialogDomainError.Canceled) {
        // e.reason は CancelReason.REQUESTED または CancelReason.HOST_DESTROYED です。
        Log.d(TAG, "Canceled: ${e.reason}")
    } catch (e: DialogDomainError.Unavailable) {
        // e.error は DialogError です。例えば NOT_FOREGROUND です。
        Log.d(TAG, "Unavailable: ${e.error}")
    }
}
```

#### 戻る操作や外側のタップで閉じる

- 引数なしの `DialogOptions()` では、戻る操作と外側のタップでダイアログを閉じられます。このときの結果は `DialogResult.Dismissed` で、値は持ちません。

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

val request = DialogRequest.Alert(
    title = "Cancelable",
    message = "Tap outside or press Back.",
    buttonText = "OK",
    // cancelable = true、cancelableOnTouchOutside = true です。
    options = DialogOptions()
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result == DialogResult.Dismissed) {
        // 利用者が戻る操作をしたか、ダイアログの外側をタップしました。
    }
}
```

#### ダイアログをキャンセルする

- `cancel(requestId)` は、コードからダイアログを閉じます。まだ結果が出ていなければ、結果は `DialogResult.Canceled(CancelReason.REQUESTED)` になります。
- `cancel` はどのスレッドからでも呼び出せます。不明な ID や、すでに結果が出たダイアログの ID は無視されます。

```kotlin
import android.os.Handler
import android.os.Looper
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager

val manager = AndroidDialogManager.getInstance(context)
// request: 任意の DialogRequest です。例えば基本ダイアログのものを使います。
val requestId = manager.show(request) { result ->
    // cancel() が先に呼ばれた場合は DialogResult.Canceled(CancelReason.REQUESTED) です。
    Log.d(TAG, "result: $result")
}

// 2 秒後にダイアログを閉じます。
Handler(Looper.getMainLooper()).postDelayed({ manager.cancel(requestId) }, 2_000)
```

### C ABI

- 同じダイアログを、C と、C の関数を呼べる言語（C#、Dart、Rust など）から使うための API です。Kotlin や Java のアプリは、代わりに `AndroidDialogManager` を呼び出してください。C ABI は JNI を通じてそれを呼ぶため、往復が増えるだけです。
- アプリには両方の AAR を追加します。`android-native-toolkit-capi-2.0.0.aar` は `libntk.so` とヘッダーを含み、隣に `android-native-toolkit-2.0.0.aar` が必要です。`libntk.so` は 64 ビット ABI（`arm64-v8a`、`x86_64`）向けにしかありません。32 ビットとしてインストールされたアプリも起動はしますが、`libntk.so` がないため読み込みに失敗します。
- ヘッダーと `libntk.so` は Prefab で提供されます。Prefab を有効にし、アプリの ABI と CMake ビルドの両方を 64 ビット ABI に限定してください。理由は [セットアップ](index.ja.md#c-abi) で説明しています（`CMakeLists.txt` の `if()` では `CXX1210` のビルドエラーを避けられません。独自の 32 ビットのネイティブコードは、Prefab を使わない別のモジュールに置きます）。

```kotlin
android {
    buildFeatures { prefab = true }
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
}
```

```cmake
find_package(ntk REQUIRED CONFIG)
target_link_libraries(your_library PRIVATE ntk::ntk)
```

- androidx.startup が、アプリの起動時にライブラリを初期化します。Startup を無効にしたアプリ、既定以外のプロセスから呼び出すアプリ、`libntk.so` を `dlopen` だけで読み込むアプリは、先に `ntk_android_init(env, context)`（`<NativeToolkitC/Android.h>`）を呼び出します。ライブラリが初期化されるまで、`ntk_dialog_show_*_async` 関数は `NTK_DIALOG_ERROR_NOT_INITIALIZED` を返します。引数の検査が先に行われるため、不正な引数にはその場合も `NTK_DIALOG_ERROR_INVALID_PARAMETER` が返り、`ntk_dialog_cancel` は何もせずに `NTK_DIALOG_ERROR_NONE` を返します。結果を読む関数と `ntk_dialog_result_free` は、初期化の有無に関係なく動作します。
- ヘッダーは素の C99 で、`<stddef.h>` と `<stdint.h>` 以外を include しません。文字列は NUL 終端の UTF-8 です。ボタンやヒントのテキストが `NULL` の場合は Kotlin の既定値（`"OK"`、`"Cancel"` など）が使われ、タイトルやメッセージの `NULL` は空文字列になります。
- 要求の構造体は 0 で埋め、`struct_size` に自身の `sizeof` を入れます。0 が既定値です。既定値を 0 に保つため、2 つのフラグは Kotlin API と名前の向きが逆になっています。`not_cancelable` は `cancelable` の逆、`not_cancelable_on_touch_outside` は `cancelableOnTouchOutside` の逆です。
- どの関数もどのスレッドからでも呼び出せ、メインスレッドを待つことはありません。戻り値は、リクエストが受け付けられたかどうかだけを示します。呼び出しの時点で拒否された場合（不正な引数、`NOT_INITIALIZED`）、コールバックは呼ばれず、`release` は呼び出しが戻る前に呼び出し元のスレッドで呼ばれます。
- 受け付けられたリクエストは Android のメインスレッドでちょうど 1 回完了し、その後に `release` が呼ばれます。どちらも、リクエストを開始した呼び出しの中では実行されません。メインスレッド以外から呼び出した場合は、その呼び出しが戻る前に完了が届くことがあるため、完了とリクエストは `user_data` で対応付けてください。アプリがバックグラウンドにあるときに呼び出すと、リクエストは `NTK_DIALOG_ERROR_NOT_FOREGROUND` で完了します。
- コールバックに渡される `ntk_dialog_result` は受け取った側が所有し、コールバックの中またはその後に `ntk_dialog_result_free` で解放します。エラーが `NTK_DIALOG_ERROR_NONE` でない場合は `NULL` です。Android では、`system_code` と `ntk_last_system_code()` は常に 0 です。
- リクエスト ID は `uint64_t` で、再利用されません。`ntk_dialog_cancel` はどのスレッドからでも ID を受け取り、不明な ID やすでに完了したリクエストは無視します。
- コールバックでメインスレッドをブロックしたり、例外を外に漏らしたりしないでください。ライブラリは例外を捕捉しないため、プロセスが終了します。

#### アラートダイアログと確認ダイアログ

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_dialog_result(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                      uint32_t system_code, ntk_dialog_result* result)
{
    /* Android のメインスレッドで、受け付けたリクエストごとに 1 回呼ばれます。system_code は常に 0 です。 */
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        /* result は NULL です。ntk_dialog_cancel の後は CANCELED、Activity がなくなった場合は
           CANCELED_BY_SYSTEM、アプリがバックグラウンドにあった場合は NOT_FOREGROUND です。 */
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON) {
        ntk_dialog_button button = ntk_dialog_result_button(result);
        size_t size = 0;
        const char* label = ntk_dialog_result_button_text(result, &size);
        (void)button; (void)label;
    } else {
        /* NTK_DIALOG_ANSWER_DISMISSED: 戻る操作または外側のタップです。値は持ちません。 */
    }
    /* 結果は受け取った側のものです。ここで解放するか、後でどのスレッドからでも解放します。 */
    ntk_dialog_result_free(result);
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* ちょうど 1 回呼ばれます。完了の後にメインスレッドで呼ばれるか、呼び出しが拒否された
       場合は、その呼び出しが戻る前に呼び出し元のスレッドで呼ばれます。 */
    (void)user_data;
}

/* ヘッダーと libntk.so は同じ版である必要があります。 */
if (ntk_version() != NTK_VERSION) {
    return;
}
/* androidx.startup がアプリの起動時にライブラリを初期化します。Startup を無効にした
   アプリは、先に ntk_android_init(env, context) を呼び出します。 */
if (!ntk_android_is_initialized()) {
    return;
}

/* --- 基本ダイアログ ------------------------------------------------- */
ntk_dialog_alert_request alert;
memset(&alert, 0, sizeof(alert));
alert.struct_size = (uint32_t)sizeof(alert);
alert.title = "Hello from Android";
alert.message = "This is a native Android dialog!";
alert.button_text = "OK";                    /* NULL の場合: "OK" */
alert.not_cancelable = 1;                    /* 戻る操作では閉じません */
alert.not_cancelable_on_touch_outside = 1;   /* 外側のタップでも閉じません */

uint64_t request_id = 0;
ntk_dialog_error error = ntk_dialog_show_alert_async(&alert, &on_dialog_result, NULL,
                                                     &release_user_data, &request_id);
if (error != NTK_DIALOG_ERROR_NONE) {
    /* 拒否されました。コールバックは呼ばれず、release_user_data はすでに実行されています。 */
    return;
}

/* 後で、例えば画面を閉じるとき: ダイアログが閉じ、NTK_DIALOG_ERROR_CANCELED で
   完了します。完了済みの ID や不明な ID では何も起きません。 */
ntk_dialog_cancel(request_id);

/* --- 確認ダイアログ ------------------------------------------------- */
ntk_dialog_confirm_request confirm;
memset(&confirm, 0, sizeof(confirm));
confirm.struct_size = (uint32_t)sizeof(confirm);
confirm.title = "Confirmation";
confirm.message = "Do you want to proceed with this action?";
confirm.negative_text = "No";                /* NULL の場合: "No" */
confirm.positive_text = "Yes";               /* NULL の場合: "Yes" */
confirm.not_cancelable = 1;
confirm.not_cancelable_on_touch_outside = 1;

/* ダイアログをキャンセルしない場合、out_request_id は NULL で構いません。 */
error = ntk_dialog_show_confirm_async(&confirm, &on_dialog_result, NULL, &release_user_data, NULL);
```

#### 選択リストのダイアログ

`ntk_dialog_result_checked_index` はシングル選択の応答を読み、何も選択されていない場合は -1 です。`ntk_dialog_result_checked_count` と `ntk_dialog_result_checked_at` はマルチ選択の応答を読み、選択されている項目では 0 以外です。否定ボタンは選択を持ちません。

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_single_choice(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                      uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        int32_t index = ntk_dialog_result_checked_index(result);   /* -1: 選択なし */
        (void)index;
    }
    ntk_dialog_result_free(result);
}

static void NTK_CALL on_multi_choice(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                     uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        size_t count = ntk_dialog_result_checked_count(result);
        size_t i;
        for (i = 0; i < count; ++i) {
            int32_t checked = ntk_dialog_result_checked_at(result, i);   /* 0 以外: 選択あり */
            (void)checked;
        }
    }
    ntk_dialog_result_free(result);
}

/* --- 1 つの項目 ----------------------------------------------------- */
const char* const single_items[] = { "Option 1", "Option 2", "Option 3" };

ntk_dialog_single_choice_request single;
memset(&single, 0, sizeof(single));
single.struct_size = (uint32_t)sizeof(single);
single.title = "Please select one";
single.items = single_items;
single.item_count = 3;                       /* 0 にはできません */
single.checked_index = 0;                    /* -1: 選択なし */
single.negative_text = "Cancel";             /* NULL の場合: "Cancel" */
single.positive_text = "OK";                 /* NULL の場合: "OK" */
single.not_cancelable = 1;
single.not_cancelable_on_touch_outside = 1;

/* 解放するものがない場合、user_data と release は NULL で構いません。 */
ntk_dialog_error error = ntk_dialog_show_single_choice_async(&single, &on_single_choice, NULL, NULL, NULL);

/* --- 任意の数の項目 ------------------------------------------------- */
const char* const multi_items[] = { "Option 1", "Option 2", "Option 3", "Option 4" };
const int32_t multi_checked[] = { 0, 1, 0, 1 };

ntk_dialog_multi_choice_request multi;
memset(&multi, 0, sizeof(multi));
multi.struct_size = (uint32_t)sizeof(multi);
multi.title = "Multiple Selection";
multi.items = multi_items;
multi.item_count = 4;
multi.checked = multi_checked;               /* NULL: 選択なし。それ以外は item_count 個の値 */
multi.negative_text = "Cancel";
multi.positive_text = "OK";
multi.not_cancelable = 1;
multi.not_cancelable_on_touch_outside = 1;

error = ntk_dialog_show_multi_choice_async(&multi, &on_multi_choice, NULL, NULL, NULL);
```

#### 入力ダイアログとログインダイアログ

テキスト、ユーザー名、パスワードは結果の中を指しており、結果を解放するまで有効です。

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_text_input(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                   uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        size_t size = 0;
        const char* text = ntk_dialog_result_text(result, &size);   /* UTF-8 */
        (void)text;
    }
    ntk_dialog_result_free(result);
}

static void NTK_CALL on_login(void* user_data, uint64_t request_id, ntk_dialog_error error,
                              uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        const char* username = ntk_dialog_result_username(result, NULL);
        const char* password = ntk_dialog_result_password(result, NULL);   /* 決してログに出さないでください */
        (void)username; (void)password;
    }
    ntk_dialog_result_free(result);
}

/* --- 入力 ----------------------------------------------------------- */
ntk_dialog_text_input_request input;
memset(&input, 0, sizeof(input));
input.struct_size = (uint32_t)sizeof(input);
input.title = "Text Input";
input.message = "Please enter your name";
input.hint = "Enter here...";                /* NULL の場合: ヒントなし */
input.negative_text = "Cancel";              /* NULL の場合: "Cancel" */
input.positive_text = "OK";                  /* NULL の場合: "OK" */
input.enable_positive_when_empty = 0;
input.not_cancelable = 1;
input.not_cancelable_on_touch_outside = 1;

ntk_dialog_error error = ntk_dialog_show_text_input_async(&input, &on_text_input, NULL, NULL, NULL);

/* --- ログイン ------------------------------------------------------- */
ntk_dialog_login_request login;
memset(&login, 0, sizeof(login));
login.struct_size = (uint32_t)sizeof(login);
login.title = "Login";
login.message = "Please enter your credentials";
login.username_hint = "Username";            /* NULL の場合: "Username" */
login.password_hint = "Password";            /* NULL の場合: "Password" */
login.negative_text = "Cancel";              /* NULL の場合: "Cancel" */
login.positive_text = "Login";               /* NULL の場合: "Login" */
login.enable_positive_when_empty = 0;
login.not_cancelable = 1;
login.not_cancelable_on_touch_outside = 1;

error = ntk_dialog_show_login_async(&login, &on_login, NULL, NULL, NULL);
```

| エラー | 返り値 / 完了 | 意味 |
|---|---|---|
| `NTK_DIALOG_ERROR_NONE` | 両方 | 受け付けた、または応答があった |
| `NTK_DIALOG_ERROR_INVALID_PARAMETER` | 返り値（まれに完了） | `NULL` のコールバックやリクエスト、不正な UTF-8、項目なし、範囲外の index、2.0.0 のサイズ未満または 4096 を超える `struct_size`、0 でない予約フィールドです。受け付けた後に Kotlin API が `IllegalArgumentException` で拒否したリクエストも、このエラーで完了することがあります |
| `NTK_DIALOG_ERROR_NOT_INITIALIZED` | 返り値 | 初期化の前に呼び出しました。引数の検査が先に行われ、`ntk_dialog_cancel` は `NONE` を返します |
| `NTK_DIALOG_ERROR_NOT_SUPPORTED` | 返り値 | このライブラリが知らない 0 以外のフィールドを持つ、新しい `struct_size` です |
| `NTK_DIALOG_ERROR_UNKNOWN` | 両方 | その他のエラーです（詳細は logcat にあります） |
| `NTK_DIALOG_ERROR_OUT_OF_MEMORY` | 両方 | メモリ不足です |
| `NTK_DIALOG_ERROR_CANCELED` | 完了 | `ntk_dialog_cancel`（`CancelReason.REQUESTED`） |
| `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM` | 完了 | ダイアログを表示していた Activity が破棄されました（`CancelReason.HOST_DESTROYED`） |
| `NTK_DIALOG_ERROR_NOT_FOREGROUND` | 完了 | アプリが前面にありませんでした（`DialogError.NOT_FOREGROUND`） |
| `NTK_DIALOG_ERROR_HOST_START_FAILED` | 完了 | 透明な Activity が開始しませんでした（`DialogError.HOST_START_FAILED`） |
| `NTK_DIALOG_ERROR_SHOW_FAILED` | 完了 | ダイアログの表示に失敗しました（`DialogError.SHOW_FAILED`） |

| Kotlin API | C ABI |
|---|---|
| `show(DialogRequest.Alert(...))` | `ntk_dialog_show_alert_async` |
| `show(DialogRequest.Confirm(...))` | `ntk_dialog_show_confirm_async` |
| `show(DialogRequest.SingleChoice(...))` | `ntk_dialog_show_single_choice_async` |
| `show(DialogRequest.MultiChoice(...))` | `ntk_dialog_show_multi_choice_async` |
| `show(DialogRequest.TextInput(...))` | `ntk_dialog_show_text_input_async` |
| `show(DialogRequest.Login(...))` | `ntk_dialog_show_login_async` |
| `cancel(requestId)` | `ntk_dialog_cancel` |
| `DialogResult.Button` / `DialogResult.Dismissed` | `ntk_dialog_result_answer` |
| `DialogResult.Button.which` / `text` | `ntk_dialog_result_button`, `ntk_dialog_result_button_text` |
| `DialogValue` | `ntk_dialog_result_checked_index`, `ntk_dialog_result_checked_count`, `ntk_dialog_result_checked_at`, `ntk_dialog_result_text`, `ntk_dialog_result_username`, `ntk_dialog_result_password` |
| - | `ntk_dialog_result_free` |

---

## iOS

### iOSDialogManager

#### ShowAlert - 基本ダイアログ

- ダイアログを表示します。

```swift
IosDialogManager.shared.showAlert(
    // タイトルを設定します。
    title: "Hello from iOS",
    // メッセージを設定します。
    message: "This is a native iOS dialog!",
    // ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    buttonText: "OK",
    // ボタン押下時のイベントを設定します。
    onButton: { buttonText, isSuccess, errorMessage in
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // ダイアログ表示完了時のイベントを設定します。
    completion: { isSuccess, errorMessage in
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowAlert.png" alt="Example_IosDialogManager_ShowAlert" width="400" />
</p>

#### ShowConfirmDialog - 確認ダイアログ

- ダイアログを表示します。

```swift
IosDialogManager.shared.showConfirmDialog(
    // タイトルを設定します。
    title: "Confirm Action",
    // メッセージを設定します。
    message: "Are you sure you want to proceed?",
    // 確認ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    confirmTitle: "Yes",
    // キャンセルボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    cancelTitle: "No",
    // 確認ボタン押下時のイベントを設定します。
    onConfirm: { confirmButtonText, isSuccess, errorMessage in
        // confirmButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // キャンセルボタン押下時のイベントを設定します。
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // ダイアログ表示完了時のイベントを設定します。
    completion: { isSuccess, errorMessage in
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowConfirmDialog.png" alt="Example_IosDialogManager_ShowConfirmDialog" width="400" />
</p>

#### ShowDestructiveDialog - ディストラクティブなダイアログ

- ダイアログを表示します。

```swift
IosDialogManager.shared.showDestructiveDialog(
    // タイトルを設定します。
    title: "Delete File",
    // メッセージを設定します。
    message: "This action cannot be undone. Are you sure?",
    // 破壊的操作の確認ボタンのテキストを設定します。未設定の場合、"Delete" が使用されます。
    destructiveTitle: "Delete",
    // キャンセルボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    cancelTitle: "Cancel",
    // 破壊的操作の確認ボタン押下時のイベントを設定します。
    onDestructive: { destructiveButtonText, isSuccess, errorMessage in
        // destructiveButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // キャンセルボタン押下時のイベントを設定します。
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // ダイアログ表示完了時のイベントを設定します。
    completion: { isSuccess, errorMessage in
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowDestructiveDialog.png" alt="Example_IosDialogManager_ShowDestructiveDialog" width="400" />
</p>

#### ShowActionSheet - アクションシート

- アクションシートを表示します。

```swift
if let rootVC = IosDialogManager.shared.getRootViewController() {
    IosDialogManager.shared.showActionSheet(
        // タイトルを設定します。
        title: "Please select",
        // メッセージを設定します。
        message: "Please choose an option",
        // 選択肢を設定します。必須項目です。
        options: ["Camera", "Photo Library", "Documents"],
        // キャンセルボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
        cancelTitle: "Cancel",
        // アクションシートを表示するビューを設定します。必須項目です。
        sourceView: rootVC.view,
        // アクションシートを表示するビューの矩形領域を設定します。
        sourceRect: nil,
        // アニメーション表示するかを設定します。未設定の場合、true が使用されます。
        animated: true,
        // Actionボタン押下時のイベントを設定します。
        onAction: { action, isSuccess, errorMessage in
            // action: 選択された項目を取得します。エラーの場合、nil を返します。
            // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
            // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
        },
        completion: { isSuccess, errorMessage in
            // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
            // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
        }
    )
}
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowActionSheet.png" alt="Example_IosDialogManager_ShowActionSheet" width="400" />
</p>

#### ShowTextInputDialog - 入力ダイアログ

- ダイアログを表示します。

```swift
IosDialogManager.shared.showTextInputDialog(
    // タイトルを設定します。
    title: "Enter Name",
    // メッセージを設定します。
    message: "Please enter your name",
    // プレースホルダーを設定します。
    placeholder: "Your name here",
    // 確認ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
    confirmTitle: "OK",
    // キャンセルボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    cancelTitle: "Cancel",
    // 入力値が空の場合、確認ボタンが有効になるかを設定します。未設定の場合、true が使用されます。
    enableConfirmWhenEmpty: false,
    // 確認ボタン押下時のイベントを設定します。
    onConfirm: { confirmButtonText, inputText, isSuccess, errorMessage in
        // confirmButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // inputText: 入力されたテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // キャンセルボタン押下時のイベントを設定します。
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // inputText: 入力されたテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // ダイアログ表示完了時のイベントを設定します。
    completion: { isSuccess, errorMessage in
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowTextInputDialog.png" alt="Example_IosDialogManager_ShowTextInputDialog" width="400" />
</p>

#### ShowLoginDialog - ログインダイアログ

- ダイアログを表示します。

```swift
IosDialogManager.shared.showLoginDialog(
    // タイトルを設定します。
    title: "Login Required",
    // メッセージを設定します。
    message: "Please enter your credentials",
    // ユーザ名のプレースホルダーを設定します。未設定の場合、"Username" が使用されます。
    usernamePlaceholder: "Username",
    // パスワードのプレースホルダーを設定します。未設定の場合、"Password" が使用されます。
    passwordPlaceholder: "Password",
    // ログインボタンのテキストを設定します。未設定の場合、"Login" が使用されます。
    loginTitle: "Login",
    // キャンセルボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
    cancelTitle: "Cancel",
    // 入力値が空の場合、ログインボタンが有効になるかを設定します。未設定の場合、true が使用されます。
    enableLoginWhenEmpty: false,
    // ログインボタン押下時のイベントを設定します。
    onLogin: { loginButtonText, username, password, isSuccess, errorMessage in
        // loginButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // username: 入力されたユーザ名を取得します。エラーの場合、nil を返します。
        // password: 入力されたパスワードを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // キャンセルボタン押下時のイベントを設定します。
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText:　押下したボタンのテキストを取得します。エラーの場合、nil を返します。
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    },
    // ダイアログ表示完了時のイベントを設定します。
    completion: { isSuccess, errorMessage in
        // isSuccess: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、nil を返します。
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowLoginDialog.png" alt="Example_IosDialogManager_ShowLoginDialog" width="400" />
</p>

---

## Windows

Windows ライブラリは、同じダイアログを 2 つの公開 API から提供します。どちらも実装は 1 つで、サンプルアプリは C++ API を使用しています。

| API | 名前 | ヘッダー | NuGet パッケージ |
|---|---|---|---|
| C++ API | `NativeToolkit::Dialog` | `<NativeToolkit/Dialog.h>` | `NativeToolkit` |
| C ABI | `ntk_dialog_*` | `<NativeToolkitC/Dialog.h>` | `NativeToolkit.CApi` |

### NativeToolkit::Dialog

- ダイアログはすべてモーダルで、呼び出したスレッドをブロックします。UI スレッドから呼び出してください。
- 戻り値は `Dialog::Result<T>` です。`has_value()` で成否を判定し、成功なら `value()`、失敗なら `error()`（`Dialog::Error`）を参照します。`Dialog::Error` は、定義済みの `code` と、OS が報告した生の値 `systemCode` を持ちます。
- 利用者がダイアログを閉じた場合は、呼び出しの失敗ではありませんが値でもないため、`Dialog::ErrorCode::Canceled` として返ります。
- 公開ヘッダーは `<windows.h>` を include しません。`request.owner` は `NativeToolkit::WindowHandle`（`HWND` と同じ型）を受け取ります。

#### ShowAlert - 基本ダイアログ

- メッセージボックスを表示し、押されたボタンを返します。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::AlertRequest request;
// タイトルを設定します。
request.title = L"Native Windows Dialog";
// メッセージを設定します。
request.message = L"This is a native Windows dialog!";
// 表示するボタンを設定します。ここでは OK と キャンセル です。
request.buttons = Dialog::AlertButtons::OkCancel;
// アイコンを設定します。ここでは情報アイコンです。
request.icon = Dialog::AlertIcon::Information;
// 最初にフォーカスが当たるボタンを設定します。ここでは 2 番目です。
request.defaultButton = Dialog::AlertDefaultButton::Second;
// 任意: 所有者ウィンドウ、MB_TOPMOST、MB_HELP も指定できます。
// request.owner = hwnd;
// request.topMost = true;
// request.showHelpButton = true;

const auto result = Dialog::ShowAlert(request);
if (result.has_value())
{
    // キャンセルも 1 つのボタンなので、失敗ではなく
    // AlertResult::Cancel として返ります。
    const Dialog::AlertResult pressed = result.value();
    if (pressed == Dialog::AlertResult::Ok)
    {
        // OK が押されたときの処理です。
    }
}
else
{
    // code が定義済みの区分、systemCode が OS の生の値です。
    const Dialog::ErrorCode code = result.error().code;
    const uint32_t systemCode = result.error().systemCode;
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowAlertDialog.png" alt="Example_WindowsDialogManager_ShowAlertDialog" width="300" />
</p>

#### ShowOpenFile - ファイル選択ダイアログ

- 既存のファイルを 1 つ選ばせ、そのフルパスを返します。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FileRequest request;
// タイトルを設定します。
request.title = L"Open File";
// 種類の一覧を設定します。1 項目は説明とパターンの組です。
// フィルターを 1 つも設定しない場合は、すべてのファイルが対象になります。
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };
// 選択するファイルが実在することを求めます（OFN_FILEMUSTEXIST）。既定値です。
request.fileMustExist = true;

const auto result = Dialog::ShowOpenFile(request);
if (result.has_value())
{
    // フルパスです。
    const std::wstring& filePath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // 利用者がダイアログを閉じました。
}
else
{
    const uint32_t systemCode = result.error().systemCode;
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowFileDialog.png" alt="Example_WindowsDialogManager_ShowFileDialog" width="1000" />
</p>

#### ShowOpenFiles - 複数ファイル選択ダイアログ

- 既存のファイルを 1 つ以上、ダイアログが返した順に取得します。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FileRequest request;
// タイトルを設定します。
request.title = L"Open Files";
// 種類の一覧を設定します。
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };

const auto result = Dialog::ShowOpenFiles(request);
if (result.has_value())
{
    // 各要素はフルパスで、フォルダー自体は要素に含まれません。
    const std::vector<std::wstring>& paths = result.value();
    for (const std::wstring& path : paths)
    {
        // 選択されたファイル 1 件です。
    }
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // 利用者がダイアログを閉じました。
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowMultiFileDialog.png" alt="Example_WindowsDialogManager_ShowMultiFileDialog" width="1000" />
</p>

#### ShowPickFolder - フォルダー選択ダイアログ

- フォルダーを 1 つ選ばせます。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FolderRequest request;
// タイトルを設定します。空にすると OS の既定のタイトルになります。
request.title = L"Select Folder";

const auto result = Dialog::ShowPickFolder(request);
if (result.has_value())
{
    const std::wstring& folderPath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // 利用者がダイアログを閉じました。
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowFolderDialog.png" alt="Example_WindowsDialogManager_ShowFolderDialog" width="1000" />
</p>

#### ShowPickFolders - 複数フォルダー選択ダイアログ

- フォルダーを 1 つ以上選ばせます。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FolderRequest request;
// タイトルを設定します。
request.title = L"Select Folders";

const auto result = Dialog::ShowPickFolders(request);
if (result.has_value())
{
    // 各要素はフルパスです。
    const std::vector<std::wstring>& paths = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // 利用者がダイアログを閉じました。
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowMultiFolderDialog.png" alt="Example_WindowsDialogManager_ShowMultiFolderDialog" width="1000" />
</p>

#### ShowSaveFile - 保存ダイアログ

- 保存先を選ばせます。ファイル自体は作成されません。

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::SaveFileRequest request;
// タイトルを設定します。
request.title = L"Save File";
// 種類の一覧を設定します。
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };
// 拡張子が入力されなかったときに付ける拡張子を設定します。
request.defaultExtension = L"txt";
// 既存のファイルを選んだときに確認します（OFN_OVERWRITEPROMPT）。既定値です。
request.overwritePrompt = true;

const auto result = Dialog::ShowSaveFile(request);
if (result.has_value())
{
    const std::wstring& savePath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // 利用者がダイアログを閉じました。
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowSaveFileDialog.png" alt="Example_WindowsDialogManager_ShowSaveFileDialog" width="1000" />
</p>

### C ABI

- C から、そして C の DLL を呼べる言語から使うための API です。ヘッダーは C99 で、`<stddef.h>` と `<stdint.h>` 以外を include しません。
- 文字列は入出力とも NUL 終端の UTF-8 です。`NULL` は空文字列を意味します。
- 要求の構造体は 0 で埋め、`struct_size` に自身の `sizeof` を入れます。0 が既定値です。既定値を 0 に保つため、2 つのフラグは C++ API と名前の向きが逆になっています。`allow_missing_file` は `fileMustExist` の逆、`skip_overwrite_prompt` は `overwritePrompt` の逆です。
- エラーは戻り値で報告されます。OS が返した生の値は、同じスレッドで失敗の直後に `ntk_last_system_code()` で読みます。
- ライブラリが返すものはハンドルで、対応する `_free` で解放します。ハンドルから取り出したポインターは、そのハンドルを解放するまで有効です。

#### メッセージボックス

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

/* ヘッダーと DLL は同じ版である必要があります。 */
if (ntk_version() != NTK_VERSION) {
    return;
}

/* 0 で埋めた状態が既定値です。struct_size は、この構造体がどの版かを
   DLL に伝えます。 */
ntk_dialog_alert_request request;
memset(&request, 0, sizeof(request));
request.struct_size = (uint32_t)sizeof(request);
request.title = "Native Windows Dialog";
request.message = "This is a native Windows dialog!";
request.buttons = NTK_DIALOG_ALERT_BUTTONS_OK_CANCEL;
request.icon = NTK_DIALOG_ALERT_ICON_INFORMATION;
request.default_button = NTK_DIALOG_ALERT_DEFAULT_BUTTON_SECOND;
/* 任意: request.top_most = 1; request.show_help_button = 1;
   request.owner = hwnd; */

ntk_dialog_alert_result pressed = 0;
ntk_dialog_error error = ntk_dialog_show_alert(&request, &pressed);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* キャンセルもボタンなので、ここでは NTK_DIALOG_ALERT_RESULT_CANCEL です。 */
} else if (error == NTK_DIALOG_ERROR_SYSTEM_ERROR) {
    uint32_t system_code = ntk_last_system_code();
    (void)system_code;
}
```

#### ファイルの選択

`ntk_dialog_show_open_file` と `ntk_dialog_show_save_file` はパスを 1 つ `ntk_string` で返します。`ntk_dialog_show_open_files` は `ntk_string_list` を返し、各項目は添字で読み、リストを解放するまで有効です。

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

/* 種類の一覧です。パターンは ';' で区切ります。すべてのファイルを対象に
   するときは NULL と 0 件を渡します。 */
ntk_dialog_filter filters[1];
filters[0].name = "All Files";
filters[0].patterns = "*.*";

/* --- 既存のファイルを 1 つ ----------------------------------------- */
ntk_dialog_file_request open_request;
memset(&open_request, 0, sizeof(open_request));
open_request.struct_size = (uint32_t)sizeof(open_request);
open_request.title = "Open File";
/* 0 は「選ぶファイルが実在すること」を求めます（OFN_FILEMUSTEXIST）。 */
open_request.allow_missing_file = 0;

ntk_string* path = NULL;
ntk_dialog_error error = ntk_dialog_show_open_file(&open_request, filters, 1, &path);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* 借りたポインターです。ntk_string_free までは有効です。 */
    const char* utf8 = ntk_string_data(path);
    size_t size = ntk_string_size(path);
    (void)utf8; (void)size;
    ntk_string_free(path);
} else if (error == NTK_DIALOG_ERROR_CANCELED) {
    /* 利用者がダイアログを閉じました。path は NULL のままです。 */
}

/* --- 既存のファイルを 1 つ以上 ------------------------------------- */
ntk_string_list* paths = NULL;
error = ntk_dialog_show_open_files(&open_request, filters, 1, &paths);
if (error == NTK_DIALOG_ERROR_NONE) {
    size_t count = ntk_string_list_count(paths);
    size_t i;
    for (i = 0; i < count; ++i) {
        size_t size = 0;
        const char* entry = ntk_string_list_at(paths, i, &size);  /* フルパス */
        (void)entry; (void)size;
    }
    ntk_string_list_free(paths);
}

/* --- 保存先 --------------------------------------------------------- */
ntk_dialog_save_file_request save_request;
memset(&save_request, 0, sizeof(save_request));
save_request.struct_size = (uint32_t)sizeof(save_request);
save_request.title = "Save File";
save_request.default_extension = "txt";
/* 0 は「既存のファイルを選んだときに確認する」です。 */
save_request.skip_overwrite_prompt = 0;

ntk_string* save_path = NULL;
error = ntk_dialog_show_save_file(&save_request, filters, 1, &save_path);
if (error == NTK_DIALOG_ERROR_NONE) {
    ntk_string_free(save_path);
}
```

#### フォルダーの選択

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

ntk_dialog_folder_request request;
memset(&request, 0, sizeof(request));
request.struct_size = (uint32_t)sizeof(request);
/* NULL か "" にすると OS の既定のタイトルになります。 */
request.title = "Select Folder";

/* --- フォルダーを 1 つ ---------------------------------------------- */
ntk_string* folder = NULL;
ntk_dialog_error error = ntk_dialog_show_pick_folder(&request, &folder);
if (error == NTK_DIALOG_ERROR_NONE) {
    const char* utf8 = ntk_string_data(folder);
    (void)utf8;
    ntk_string_free(folder);
}

/* --- フォルダーを 1 つ以上 ------------------------------------------ */
request.title = "Select Folders";

ntk_string_list* folders = NULL;
error = ntk_dialog_show_pick_folders(&request, &folders);
if (error == NTK_DIALOG_ERROR_NONE) {
    size_t count = ntk_string_list_count(folders);
    size_t i;
    for (i = 0; i < count; ++i) {
        size_t size = 0;
        const char* entry = ntk_string_list_at(folders, i, &size);
        (void)entry; (void)size;
    }
    ntk_string_list_free(folders);
}
```

| C++ API | C ABI |
|---|---|
| `Dialog::ShowAlert` | `ntk_dialog_show_alert` |
| `Dialog::ShowOpenFile` | `ntk_dialog_show_open_file` |
| `Dialog::ShowOpenFiles` | `ntk_dialog_show_open_files` |
| `Dialog::ShowSaveFile` | `ntk_dialog_show_save_file` |
| `Dialog::ShowPickFolder` | `ntk_dialog_show_pick_folder` |
| `Dialog::ShowPickFolders` | `ntk_dialog_show_pick_folders` |
## macOS

### MacDialogManager

#### ShowDialog - 基本ダイアログ

- ダイアログを表示します。

```swift
// タイトルを設定します。必須項目です。
let title = "Hello from macOS"
// メッセージを設定します。未設定の場合、表示されません。
let message = "This is a native macOS dialog!"
// ボタンを設定します。最低1個のボタンが必要です。
let buttons = [
    // title: ボタンのタイトルを設定します。必須項目です。
    // isDefault: デフォルトボタンに設定する場合、true を指定します。省略時は false です。1個のダイアログにつき、1つのデフォルトボタンのみ設定可能です。
    // keyEquivalent: ボタンのキーショートカットを設定します。省略時は null です。isDefault が true の場合、自動的に Enter キーが割り当てられます。
    DialogButton(title: "OK", isDefault: true),
    DialogButton(title: "Cancel", keyEquivalent: "\u{1b}"),
    DialogButton(title: "Delete", keyEquivalent: "d")
]
// オプションを設定します。必須項目です。
let options = DialogOptions(
    // alertStyle: ダイアログのスタイルを設定します。必須項目です。
    alertStyle: .informational,
    // buttons: ダイアログに表示するボタンの配列を設定します。必須項目です。
    buttons: buttons,
    // showsHelp: ヘルプボタンを表示する場合、true を指定します。省略時は false です。
    showsHelp: true,
    // showsSuppressionButton: サプレッションチェックボックスを表示する場合、true を指定します。省略時は false です。
    showsSuppressionButton: true,
    // suppressionButtonTitle: サプレッションチェックボックスのタイトルを設定します。省略時は OSデフォルトのタイトルが使用されます。showsSuppressionButton が false の場合、無視されます。
    suppressionButtonTitle: "Don't show this again",
    // icon: ダイアログに表示するアイコンを設定します。
    icon: IconConfiguration(
        // 以下はアイコンのタイプごとの設定方法例です。必要に応じて設定してください。
        ...
    ),
    // accessoryView: ダイアログに表示するアクセサリービューを設定します。省略時は nil です。
    accessoryView: nil
)

// アイコンのタイプがシステムシンボルアイコンの例です。
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: アイコンのタイプがシステムシンボルです。必須項目です。
        type: .systemSymbol,
        // value: システムシンボルの名前を設定します。必須項目です。
        value: "info.square.fill",
        // renderingMode: アイコンのレンダリングモードを設定します。必須項目です。
        renderingMode: .palette,
        // colors: アイコンのカラー配列を設定します。レンダリングモードが Palette の場合、1～3色を指定可能で必須です。レンダリングモードが Hierarchical の場合、1色が指定可能です。色は #RRGGBB または colorname 形式で指定します。
        colors: ["white", "systemblue", "systemblue"],
        // size: アイコンのサイズをポイント単位で設定します。省略時は OSデフォルト値が使用されます。ダイアログでは制限により設定しても無効です。
        size: 64,
        // weight: アイコンのウェイトを設定します。省略時は OSデフォルト値が使用されます。
        weight: .regular,
        // scale: アイコンのスケールを設定します。省略時は OSデフォルト値が使用されます。ダイアログでは制限により設定しても無効です。
        scale: .medium
    )
)

// アイコンのタイプがファイルパスの場合の例です。
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: アイコンのタイプがファイルパスです。必須項目です。
        type: .filePath,
        // value: ファイルパスを設定します。必須項目です。
        value: "/Users/user/Downloads/test.png"
    )
);

// アイコンのタイプが名前付き画像の場合の例です。
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: アイコンのタイプが名前付き画像です。必須項目です。
        type: .namedImage,
        // value: 名前付き画像の名前を設定します。必須項目です。
        value: "test-image"
    )
);

// アイコンのタイプがアプリアイコンの場合の例です。
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: アイコンのタイプがアプリアイコンです。必須項目です。
        type: .appIcon
    )
);

// アイコンのタイプがシステム画像の場合の例です。
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: アイコンのタイプがシステム画像です。必須項目です。
        type: .systemImage,
        // value: システム画像の名前を設定します。必須項目です。
        value: "cautionName"
    )
)

MacDialogManager.shared.showDialog(
    title: title,
    message: message,
    options: options
    // ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: ダイアログの結果を取得します。
    switch result {
    // buttonIndex: 押下したボタンの index を取得します。
    // buttonTitle: 押下したボタンのタイトルを取得します。
    // suppressionButtonState: サプレッションチェックボックスの状態を取得します。
    // helpButtonPressed: ヘルプボタンが押下されたかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let dialogResult):
        Log.d(TAG, "[ShowDialog] success: \(dialogResult)")
    // error: エラー内容を取得します。
    case .failure(let error):
        Log.e(TAG, "[ShowDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowDialog.png" alt="Example_MacDialogManager_ShowDialog" width="400" />
</p>

#### ShowFileDialog - ファイル選択ダイアログ

- ダイアログを表示します。

```swift
MacDialogManager.shared.showFileDialog(
    // タイトルを設定します。必須項目です。
    title: "Select a file",
    // メッセージを設定します。未設定の場合、表示されません。
    message: "Please select a file to open.",
    // 許可するファイルの拡張子を設定します。未設定の場合、OS規定の値が使用されます。
    allowedContentTypes: ["txt", "png"],
    // 初期ディレクトリを設定します。未設定の場合、OS規定の値が使用されます。
    directoryURL: nil
    // ファイル選択ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: ファイル選択ダイアログの結果を取得します。
    switch result {
    // filePaths: 選択されたファイルパスの配列を取得します。キャンセルされた場合、空配列([]) を返します。
    // fileCount: 返却されたファイル数を取得します。キャンセルされた場合は 0 です。
    // directoryURL: 選択が行われたディレクトリ URL を取得します。キャンセルの場合は 空文字列("") を返します。
    // isCancelled: ユーザがダイアログをキャンセルしたかどうかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let openResult):
        Log.d(TAG, "[ShowFileDialog] success: \(openResult)")
    // error: エラー内容を取得します。
    case .failure(let error):
        Log.e(TAG, "[ShowFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowFileDialog.png" alt="Example_MacDialogManager_ShowFileDialog" width="1000" />
</p>

#### ShowMultiFileDialog - 複数ファイル選択ダイアログ

- ダイアログを表示します。

```swift
MacDialogManager.shared.showMultiFileDialog(
    // タイトルを設定します。必須項目です。
    title: "Select files",
    // メッセージを設定します。未設定の場合、表示されません。
    message: "Please select files to open.",
    // 許可するファイルの拡張子を設定します。未設定の場合、OS規定の値が使用されます。
    allowedContentTypes: ["txt", "png"],
    // 初期ディレクトリを設定します。未設定の場合、OS規定の値が使用されます。
    directoryURL: nil
    // 複数ファイル選択ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: 複数ファイル選択ダイアログの結果を取得します。
    switch result {
    // filePaths: 選択されたファイルパスの配列を取得します。キャンせルの場合、空配列([]) を返します。
    // fileCount: 返却されたファイル数を取得します。キャンセルされた場合は 0 です。
    // directoryURL: 選択が行われたディレクトリ URL を取得します。キャンセルの場合は 空文字列("") を返します。
    // isCancelled: ユーザがダイアログをキャンセルしたかどうかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let openResult):
        Log.d(TAG, "[ShowMultiFileDialog] success: \(openResult)")
    // error: エラー内容を取得します。
    case .failure(let error):
        Log.e(TAG, "[ShowMultiFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowMultiFileDialog.png" alt="Example_MacDialogManager_ShowMultiFileDialog" width="1000" />
</p>

#### ShowFolderDialog - フォルダ選択ダイアログ

- ダイアログを表示します。

```swift
MacDialogManager.shared.showFolderDialog(
    // タイトルを設定します。必須項目です。
    title: "Select a folder",
    // メッセージを設定します。未設定の場合、表示されません。
    message: "Please select a folder to open.",
    // 初期ディレクトリを設定します。未設定の場合、OS規定の値が使用されます。
    directoryURL: nil
    // フォルダ選択ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: フォルダ選択ダイアログの結果を取得します。
    switch result {
    // filePaths: 選択されたフォルダパスの配列を取得します。キャンせルの場合、空配列([]) を返します。
    // fileCount: 返却されたフォルダ数を取得します。キャンセルされた場合は 0 です。
    // directoryURL: 選択が行われたディレクトリ URL を取得します。キャンセルの場合は 空文字列("") を返します。
    // isCancelled: ユーザがダイアログをキャンセルしたかどうかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let openResult):
        Log.d(TAG, "[ShowFolderDialog] success: \(openResult)")
    case .failure(let error):
        Log.e(TAG, "[ShowFolderDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowFolderDialog.png" alt="Example_MacDialogManager_ShowFolderDialog" width="1000" />
</p>

#### ShowMultiFolderDialog - 複数フォルダ選択ダイアログ

- ダイアログを表示します。

```swift
MacDialogManager.shared.showMultiFolderDialog(
    // タイトルを設定します。必須項目です。
    title: "Select folders",
    // メッセージを設定します。未設定の場合、表示されません。
    message: "Please select folders to open.",
    // 初期ディレクトリを設定します。未設定の場合、OS規定の値が使用されます。
    directoryURL: nil
    // 複数フォルダ選択ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: 複数フォルダ選択ダイアログの結果を取得します。
    switch result {
    // filePaths: 選択されたフォルダパスの配列を取得します。キャンせルの場合、空配列([]) を返します。
    // fileCount: 返却されたフォルダ数を取得します。キャンセルされた場合は 0 です。
    // directoryURL: 選択が行われたディレクトリ URL を取得します。キャンセルの場合は 空文字列("") を返します。
    // isCancelled: ユーザがダイアログをキャンセルしたかどうかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let openResult):
        Log.d(TAG, "[ShowMultiFolderDialog] success: \(openResult)")
    // error: エラー内容を取得します。
    case .failure(let error):
        Log.e(TAG, "[ShowMultiFolderDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowMultiFolderDialog.png" alt="Example_MacDialogManager_ShowMultiFolderDialog" width="1000" />
</p>

#### ShowSaveFileDialog - ファイル保存ダイアログ

- ダイアログを表示します。

```swift
MacDialogManager.shared.showSaveFileDialog(
    // タイトルを設定します。必須項目です。
    title: "Save File",
    // メッセージを設定します。未設定の場合、表示されません。
    message: "Choose a destination",
    // デフォルトのファイル名を設定します。未設定の場合、OS規定の値が使用されます。
    nameFieldStringValue: "default",
    // 許可するファイルの拡張子を設定します。未設定の場合、OS規定の値が使用されます。
    allowedContentTypes: ["txt"],
    // 初期ディレクトリを設定します。未設定の場合、OS規定の値が使用されます。
    directoryURL: nil
    // ファイル保存ダイアログの結果を受け取るイベントを設定します。
) { result in
    // result: ファイル保存ダイアログの結果を取得します。
    switch result {
    // filePath: 保存先のファイルパスを取得します。キャンセルの場合は 空文字列("") を返します。
    // fileCount: 返却されたパス数を取得します。成功時は 1、キャンセル時は 0 です。
    // directoryURL: 保存が行われたディレクトリ URL を取得します。キャンセルの場合は 空文字列("") を返します。
    // isCancelled: ユーザがダイアログをキャンセルしたかどうかを取得します。
    // isSuccess: ダイアログ表示成功のフラグを取得します。成功の場合、true を返します。
    case .success(let saveResult):
        Log.d(TAG, "[ShowSaveFileDialog] success: \(saveResult)")
    // error: エラー内容を取得します。
    case .failure(let error):
        Log.e(TAG, "[ShowSaveFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowSaveFileDialog.png" alt="Example_MacDialogManager_ShowSaveFileDialog" width="600" />
</p>
