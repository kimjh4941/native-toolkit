# ダイアログ機能

言語:

- 日本語（このページ）
- English: [dialog.md](dialog.md)
- 한국어: [dialog.ko.md](dialog.ko.md)

← [マニュアルトップに戻る](index.ja.md)

---

## 目次

- [Android](#android)
  - [AndroidDialogFragment](#androiddialogfragment)
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
  - [C ABI](#c-abi)
    - [メッセージボックス](#メッセージボックス)
    - [ファイルの選択](#ファイルの選択)
    - [フォルダーの選択](#フォルダーの選択)
- [macOS](#macos)
  - [MacDialogManager](#macdialogmanager)

---

## Android

### AndroidDialogFragment

#### 基本ダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Hello from Android";
// メッセージを設定します。必須項目です。
val message = "This is a native Android dialog!";
// ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
val buttonText = "OK";
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false;
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false;

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    buttonText = buttonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // ダイアログの結果を受け取るリスナーを設定します。
    setDialogListener(object : AndroidDialogFragment.DialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // 第1引数は FragmentManager を指定します。
    // 第2引数はダイアログのタグ名を指定します。
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowDialog.png" alt="Example_AndroidDialogFragment_ShowDialog" width="400" />
</p>

#### 確認ダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Confirmation"
// メッセージを設定します。必須項目です。
val message = "Do you want to proceed with this action?"
// 否定ボタンのテキストを設定します。未設定の場合、"No" が使用されます。
val negativeButtonText = "No"
// 肯定ボタンのテキストを設定します。未設定の場合、"Yes" が使用されます。
val positiveButtonText = "Yes"
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // 確認ダイアログの結果を受け取るリスナーを設定します。
    setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onConfirmDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onConfirmDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // 第1引数は FragmentManager を指定します。
    // 第2引数はダイアログのタグ名を指定します。
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowConfirmDialog.png" alt="Example_AndroidDialogFragment_ShowConfirmDialog" width="400" />
</p>

#### シングル選択ダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Please select one"
// 選択肢を設定します。必須項目です。
val singleChoiceItems = arrayOf("Option 1", "Option 2", "Option 3")
// デフォルト選択項目のindex番号を設定します。未設定の場合、0 が使用されます。
val checkedItem = 0
// 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
val negativeButtonText = "Cancel"
// 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
val positiveButtonText = "OK"
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    singleChoiceItems = singleChoiceItems,
    checkedItem = checkedItem,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // シングル選択ダイアログの結果を受け取るリスナーを設定します。
    setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // checkedItem: 選択された項目のindex番号を取得します。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onSingleChoiceItemDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            checkedItem: Int?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // 第1引数は FragmentManager を指定します。
    // 第2引数はダイアログのタグ名を指定します。
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowSingleChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowSingleChoiceItemDialog" width="400" />
</p>

#### マルチ選択ダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Multiple Selection"
// 選択肢を設定します。必須項目です。
val multiChoiceItems = arrayOf("Option 1", "Option 2", "Option 3", "Option 4")
// デフォルト選択項目の選択状態を設定します。未設定の場合、すべて false が使用されます。
val checkedItems = booleanArrayOf(false, true, false, true)
// 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
val negativeButtonText = "Cancel"
// 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
val positiveButtonText = "OK"
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    multiChoiceItems = multiChoiceItems,
    checkedItems = checkedItems,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // マルチ選択ダイアログの結果を受け取るリスナーを設定します。
    setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // checkedItems: 選択された項目の選択状態を取得します。選択はtrue, 未選択はfalse。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onMultiChoiceItemDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            checkedItems: BooleanArray?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // 第1引数は FragmentManager を指定します。
    // 第2引数はダイアログのタグ名を指定します。
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowMultiChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowMultiChoiceItemDialog" width="400" />
</p>

#### 入力ダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Text Input"
// メッセージを設定します。必須項目です。
val message = "Please enter your name"
// プレースホルダーを設定します。未設定の場合、空文字列が使用されます。
val hint = "Enter here..."
// 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
val negativeButtonText = "Cancel"
// 肯定ボタンのテキストを設定します。未設定の場合、"OK" が使用されます。
val positiveButtonText = "OK"
// 入力値が空の場合、肯定ボタンが有効になるかを設定します。未設定の場合、false が使用されます。
val enablePositiveButtonWhenEmpty = false
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    hint = hint,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    enablePositiveButtonWhenEmpty = enablePositiveButtonWhenEmpty,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // 入力ダイアログの結果を受け取るリスナーを設定します。
    setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // inputText: 入力されたテキストを取得します。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onTextInputDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            inputText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // 第1引数は FragmentManager を指定します。
    // 第2引数はダイアログのタグ名を指定します。
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowTextInputDialog.png" alt="Example_AndroidDialogFragment_ShowTextInputDialog" width="400" />
</p>

#### ログインダイアログ

- ダイアログを表示します。

```kotlin
import android.library.dialog.AndroidDialogFragment

// タイトルを設定します。必須項目です。
val title = "Login"
// メッセージを設定します。必須項目です。
val message = "Please enter your credentials"
// ユーザ名のプレースホルダーを設定します。未設定の場合、"Username" が使用されます。
val usernameHint = "Username"
// パスワードのプレースホルダーを設定します。未設定の場合、"Password" が使用されます。
val passwordHint = "Password"
// 否定ボタンのテキストを設定します。未設定の場合、"Cancel" が使用されます。
val negativeButtonText = "Cancel"
// 肯定ボタンのテキストを設定します。未設定の場合、"Login" が使用されます。
val positiveButtonText = "Login"
// 入力値が空の場合、肯定ボタンが有効になるかを設定します。未設定の場合、false が使用されます。
val enablePositiveButtonWhenEmpty = false
// ダイアログの外をタップした場合、キャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelableOnTouchOutside = false
// バックキーなどでダイアログがキャンセル可能かを設定します。未設定の場合、true が使用されます。
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    usernameHint = usernameHint,
    passwordHint = passwordHint,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    enablePositiveButtonWhenEmpty = enablePositiveButtonWhenEmpty,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // ログインダイアログの結果を受け取るリスナーを設定します。
    setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
        // dialog: ダイアログインスタンス
        // buttonText:　押下したボタンのテキストを取得します。エラーの場合、null を返します。
        // username: 入力されたユーザ名を取得します。エラーの場合、null を返します。
        // password: 入力されたパスワードを取得します。エラーの場合、null を返します。
        // isSuccessful: ダイアログ表示成功のプラグを取得します。成功の場合、true を返します。
        // errorMessage: エラーが発生した場合、エラー内容を取得します。成功の場合、null を返します。
        override fun onLoginDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            username: String?,
            password: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowLoginDialog.png" alt="Example_AndroidDialogFragment_ShowLoginDialog" width="400" />
</p>

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
