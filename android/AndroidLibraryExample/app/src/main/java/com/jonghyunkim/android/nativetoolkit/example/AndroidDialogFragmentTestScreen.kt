package com.jonghyunkim.android.nativetoolkit.example

import android.library.dialog.AndroidDialogFragment
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class ButtonType {
    SHOW_DIALOG,
    SHOW_CONFIRM_DIALOG,
    SHOW_SINGLE_CHOICE_ITEM_DIALOG,
    SHOW_MULTI_CHOICE_ITEM_DIALOG,
    SHOW_TEXT_INPUT_DIALOG,
    SHOW_LOGIN_DIALOG
}

@Composable
fun AndroidDialogFragmentTestScreen(
    modifier: Modifier = Modifier,
    resultText: String,
    onBack: () -> Unit,
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
            Button(
                onClick = onBack,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = "← Back to Main")
            }
        }
        item {
            Text(
                text = "Dialog Example",
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

fun AppCompatActivity.handleAndroidDialogTestButtonClick(
    buttonType: ButtonType,
    onResultUpdated: (String) -> Unit
) {
    when (buttonType) {
        ButtonType.SHOW_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowDialog")
            AndroidDialogFragment.newInstance(
                title = "Hello from Android",
                message = "This is a native Android dialog!",
                buttonText = "OK",
                cancelableOnTouchOutside = false,
                cancelable = false
            ).apply {
                setDialogListener(object : AndroidDialogFragment.DialogListener {
                    override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                        Log.d(DIALOG_TEST_TAG, "onDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onDialog - buttonText: $buttonText, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }

        ButtonType.SHOW_CONFIRM_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowConfirmDialog")
            AndroidDialogFragment.newInstance(
                title = "Confirmation",
                message = "Do you want to proceed with this action?",
                negativeButtonText = "No",
                positiveButtonText = "Yes",
                cancelableOnTouchOutside = false,
                cancelable = false
            ).apply {
                setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
                    override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
                        Log.d(DIALOG_TEST_TAG, "onConfirmDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onConfirmDialog - buttonText: $buttonText, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }

        ButtonType.SHOW_SINGLE_CHOICE_ITEM_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowSingleChoiceItemDialog")
            AndroidDialogFragment.newInstance(
                title = "Please select one",
                singleChoiceItems = arrayOf("Option 1", "Option 2", "Option 3"),
                checkedItem = 0,
                negativeButtonText = "Cancel",
                positiveButtonText = "OK",
                cancelableOnTouchOutside = false,
                cancelable = false
            ).apply {
                setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
                    override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
                        Log.d(DIALOG_TEST_TAG, "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }

        ButtonType.SHOW_MULTI_CHOICE_ITEM_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowMultiChoiceItemDialog")
            AndroidDialogFragment.newInstance(
                title = "Multiple Selection",
                multiChoiceItems = arrayOf("Option 1", "Option 2", "Option 3", "Option 4"),
                checkedItems = booleanArrayOf(false, true, false, true),
                negativeButtonText = "Cancel",
                positiveButtonText = "OK",
                cancelableOnTouchOutside = false,
                cancelable = false
            ).apply {
                setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
                    override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {
                        Log.d(DIALOG_TEST_TAG, "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }

        ButtonType.SHOW_TEXT_INPUT_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowTextInputDialog")
            AndroidDialogFragment.newInstance(
                title = "Text Input",
                message = "Please enter your name",
                hint = "Enter here...",
                negativeButtonText = "Cancel",
                positiveButtonText = "OK",
                enablePositiveButtonWhenEmpty = false,
                cancelableOnTouchOutside = false,
                cancelable = false
            ).apply {
                setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
                    override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {
                        Log.d(DIALOG_TEST_TAG, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }

        ButtonType.SHOW_LOGIN_DIALOG -> {
            Log.d(DIALOG_TEST_TAG, "ShowLoginDialog")
            AndroidDialogFragment.newInstance(
                title = "Login",
                message = "Please enter your credentials",
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
                        Log.d(DIALOG_TEST_TAG, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
                        onResultUpdated(
                            buildDialogResultText(
                                isSuccessful,
                                "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, errorMessage: $errorMessage"
                            )
                        )
                    }
                })
                show(supportFragmentManager, DIALOG_FRAGMENT_TAG)
            }
        }
    }
}

private fun buildDialogResultText(isSuccess: Boolean, result: String?): String {
    return if (isSuccess) {
        "✅\nResult: ${result ?: "null"}"
    } else {
        "❌\nResult: ${result ?: "null"}"
    }
}

private const val DIALOG_TEST_TAG = "AndroidDialogTest"
private const val DIALOG_FRAGMENT_TAG = "AndroidDialogFragment"

