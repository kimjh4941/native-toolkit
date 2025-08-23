package example.android

import android.library.dialog.AndroidDialogFragment
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

    private var resultText by mutableStateOf("Result will be displayed here")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "Android Library Example"
        enableEdgeToEdge()
        setContent {
            AndroidTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    MainContent(
                        modifier = Modifier.padding(innerPadding),
                        resultText = resultText,
                        onButtonClick = { buttonType ->
                            handleButtonClick(buttonType)
                        }
                    )
                }
            }
        }
    }

    private fun updateResult(isSuccess: Boolean, result: String?) {
        resultText = if (isSuccess) {
            "✅\nResult: ${result ?: "null"}"
        } else {
            "❌\nResult: ${result ?: "null"}"
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
                        override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onDialog - buttonText: $buttonText, errorMessage: $errorMessage")
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
                        override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onConfirmDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onConfirmDialog - buttonText: $buttonText, errorMessage: $errorMessage")
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
                        override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, errorMessage: $errorMessage")
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
                        override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, errorMessage: $errorMessage")
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
                        override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, errorMessage: $errorMessage")
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
                        override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {
                            Log.d(TAG, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                            updateResult(isSuccessful, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, errorMessage: $errorMessage")
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
    resultText: String,
    onButtonClick: (ButtonType) -> Unit = {}
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Top)
    ) {
        item {
            Text(
                text = "AndroidDialogFragment Test",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                lineHeight = 36.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
            )
        }
        item {
            Text(
                text = resultText,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            )
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowDialog")
            }
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_CONFIRM_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowConfirmDialog")
            }
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_SINGLE_CHOICE_ITEM_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowSingleChoiceItemDialog")
            }
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_MULTI_CHOICE_ITEM_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowMultiChoiceItemDialog")
            }
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_TEXT_INPUT_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowTextInputDialog")
            }
        }
        item {
            Button(
                onClick = { onButtonClick(ButtonType.SHOW_LOGIN_DIALOG) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "ShowLoginDialog")
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
fun MainContentPreview() {
    AndroidTheme {
        MainContent(resultText = "Result will be displayed here")
    }
}
