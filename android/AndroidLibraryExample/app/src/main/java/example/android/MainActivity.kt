package example.android

import android.library.dialog.AndroidDialogFragment
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import example.android.ui.theme.AndroidTheme

enum class ButtonType {
    SHOW_DIALOG,
    SHOW_CONFIRM_DIALOG,
    SHOW_SINGLE_CHOICE_ITEM_DIALOG,
    SHOW_MULTI_CHOICE_ITEM_DIALOG,
    SHOW_TEXT_INPUT_DIALOG,
    SHOW_LOGIN_DIALOG
}

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroidTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    MainContent(
                        modifier = Modifier.padding(innerPadding),
                        onButtonClick = { buttonType ->
                            handleButtonClick(buttonType)
                        }
                    )
                }
            }
        }
    }

    private fun handleButtonClick(buttonType: ButtonType) {
        when (buttonType) {
            ButtonType.SHOW_DIALOG -> {
                Log.d(TAG, "ShowDialog")
                AndroidDialogFragment.newInstance(
                    title = "Title",
                    message = "Thank you for your cooperation.",
                    buttonText = "OK",
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setDialogListener(object : AndroidDialogFragment.DialogListener {
                        override fun onDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }

            ButtonType.SHOW_CONFIRM_DIALOG -> {
                Log.d(TAG, "ShowConfirmDialog")
                AndroidDialogFragment.newInstance(
                    title = "Confirmation",
                    message = "Do you want to execute this operation?",
                    negativeButtonText = "Cancel",
                    positiveButtonText = "OK",
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
                        override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onConfirmDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }

            ButtonType.SHOW_SINGLE_CHOICE_ITEM_DIALOG -> {
                Log.d(TAG, "ShowSingleChoiceItemDialog")
                val items = arrayOf("Option 1", "Option 2", "Option 3")
                AndroidDialogFragment.newInstance(
                    title = "Please select one",
                    singleChoiceItems = items,
                    checkedItem = 0,
                    negativeButtonText = "Cancel",
                    positiveButtonText = "OK",
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
                        override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItem: Int, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onSingleChoiceItemDialog - selected: ${items[checkedItem]}, buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }

            ButtonType.SHOW_MULTI_CHOICE_ITEM_DIALOG -> {
                Log.d(TAG, "ShowMultiChoiceItemDialog")
                val items = arrayOf("Option 1", "Option 2", "Option 3", "Option 4")
                val checkedItems = booleanArrayOf(false, true, false, true)
                AndroidDialogFragment.newInstance(
                    title = "Please select multiple items",
                    multiChoiceItems = items,
                    checkedItems = checkedItems,
                    negativeButtonText = "Cancel",
                    positiveButtonText = "OK",
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
                        override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String, checkedItems: BooleanArray, isSuccessful: Boolean, errorMessage: String) {
                            val selectedItems = items.filterIndexed { index, _ -> checkedItems[index] }
                            Log.d(TAG, "onMultiChoiceItemDialog - selected: $selectedItems, buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }

            ButtonType.SHOW_TEXT_INPUT_DIALOG -> {
                Log.d(TAG, "ShowTextInputDialog")
                AndroidDialogFragment.newInstance(
                    title = "Input",
                    message = "Please enter your name",
                    hint = "Your name",
                    negativeButtonText = "Cancel",
                    positiveButtonText = "OK",
                    enablePositiveButtonWhenEmpty = false,
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
                        override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String, inputText: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }

            ButtonType.SHOW_LOGIN_DIALOG -> {
                Log.d(TAG, "ShowLoginDialog")
                AndroidDialogFragment.newInstance(
                    title = "Login",
                    message = "Please enter your account information",
                    usernameHint = "Username",
                    passwordHint = "Password",
                    negativeButtonText = "Cancel",
                    positiveButtonText = "Login",
                    enablePositiveButtonWhenEmpty = false,
                    cancelableOnTouchOutside = false,
                    cancelable = false
                ).apply {
                    setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
                        override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String, username: String, password: String, isSuccessful: Boolean, errorMessage: String) {
                            Log.d(TAG, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        }
                    })
                    show(supportFragmentManager, "AndroidDialogFragment")
                }
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}

@Composable
fun MainContent(
    modifier: Modifier = Modifier,
    onButtonClick: (ButtonType) -> Unit = {}
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)
    ) {
        Button(
            onClick = { onButtonClick(ButtonType.SHOW_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowDialog")
        }

        Button(
            onClick = { onButtonClick(ButtonType.SHOW_CONFIRM_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowConfirmDialog")
        }

        Button(
            onClick = { onButtonClick(ButtonType.SHOW_SINGLE_CHOICE_ITEM_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowSingleChoiceItemDialog")
        }

        Button(
            onClick = { onButtonClick(ButtonType.SHOW_MULTI_CHOICE_ITEM_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowMultiChoiceItemDialog")
        }

        Button(
            onClick = { onButtonClick(ButtonType.SHOW_TEXT_INPUT_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowTextInputDialog")
        }

        Button(
            onClick = { onButtonClick(ButtonType.SHOW_LOGIN_DIALOG) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "ShowLoginDialog")
        }
    }
}

@Preview(showBackground = true)
@Composable
fun MainContentPreview() {
    AndroidTheme {
        MainContent()
    }
}
