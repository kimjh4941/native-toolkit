package com.jonghyunkim.android.nativetoolkit.example

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogDomainError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue
import kotlinx.coroutines.launch

private const val DIALOG_TAG = "DialogSampleScreen"

// None of the sample dialogs close on Back or an outside tap (UI test D-16), except the one that
// shows the Dismissed result.
private val NOT_CANCELABLE = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)

private val ALERT = DialogRequest.Alert(
    title = "Hello from Android",
    message = "This is a native Android dialog!",
    buttonText = "OK",
    options = NOT_CANCELABLE
)
private val CONFIRM = DialogRequest.Confirm(
    title = "Confirmation",
    message = "Do you want to proceed with this action?",
    negativeText = "No",
    positiveText = "Yes",
    options = NOT_CANCELABLE
)
private val SINGLE_CHOICE = DialogRequest.SingleChoice(
    title = "Please select one",
    items = listOf("Option 1", "Option 2", "Option 3"),
    checkedIndex = 0,
    negativeText = "Cancel",
    positiveText = "OK",
    options = NOT_CANCELABLE
)
private val MULTI_CHOICE = DialogRequest.MultiChoice(
    title = "Multiple Selection",
    items = listOf("Option 1", "Option 2", "Option 3", "Option 4"),
    checked = listOf(false, true, false, true),
    negativeText = "Cancel",
    positiveText = "OK",
    options = NOT_CANCELABLE
)
private val TEXT_INPUT = DialogRequest.TextInput(
    title = "Text Input",
    message = "Please enter your name",
    hint = "Enter here...",
    negativeText = "Cancel",
    positiveText = "OK",
    enablePositiveWhenEmpty = false,
    options = NOT_CANCELABLE
)
private val LOGIN = DialogRequest.Login(
    title = "Login",
    message = "Please enter your credentials",
    usernameHint = "Username",
    passwordHint = "Password",
    negativeText = "Cancel",
    positiveText = "Login",
    enablePositiveWhenEmpty = false,
    options = NOT_CANCELABLE
)
// The 2-second cancel must survive MainActivity's recreation, so it is not in the composition.
private val mainHandler = Handler(Looper.getMainLooper())

private val CANCELABLE_ALERT = DialogRequest.Alert(
    title = "Cancelable",
    message = "Tap outside or press Back.",
    buttonText = "OK",
    options = DialogOptions()
)

/**
 * Shows dialogs through [AndroidDialogManager] (sample app design 4.5). Results go to
 * [ScreenResults.dialog], which the router holds, so they survive leaving the screen and
 * MainActivity's recreation (a shown dialog is restored by the library).
 *
 * @param modifier The modifier.
 * @param resultText The last result.
 * @param onBack Goes back to the main menu.
 */
@Composable
fun DialogSampleScreen(
    modifier: Modifier = Modifier,
    resultText: String,
    onBack: () -> Unit
) {
    Log.d(DIALOG_TAG, "[DialogSampleScreen] resultText: $resultText, onBack: $onBack")
    val context = LocalContext.current
    val manager = remember(context) { AndroidDialogManager.getInstance(context) }
    val scope = rememberCoroutineScope()

    fun show(kind: String, request: DialogRequest): Long? {
        Log.d(DIALOG_TAG, "[show] kind: $kind, request: $request")
        return try {
            manager.show(request) { result -> ScreenResults.dialog.deliver(describe(kind, result)) }
        } catch (e: IllegalArgumentException) {
            ScreenResults.dialog.deliver("❌\nResult: $kind - Invalid request: ${e.message}")
            null
        }
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Top)
    ) {
        item {
            Button(onClick = onBack, modifier = Modifier.fillMaxWidth().testTag("dialog.back")) {
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
                    .testTag("dialog.status")
                    .fillMaxWidth()
                    .padding(8.dp)
            )
        }
        item { DialogButton("ShowDialog", "dialog.showDialog") { show("alert", ALERT) } }
        item { DialogButton("ShowConfirmDialog", "dialog.showConfirmDialog") { show("confirm", CONFIRM) } }
        item {
            DialogButton("ShowSingleChoiceItemDialog", "dialog.showSingleChoiceItemDialog") {
                show("singleChoice", SINGLE_CHOICE)
            }
        }
        item {
            DialogButton("ShowMultiChoiceItemDialog", "dialog.showMultiChoiceItemDialog") {
                show("multiChoice", MULTI_CHOICE)
            }
        }
        item { DialogButton("ShowTextInputDialog", "dialog.showTextInputDialog") { show("textInput", TEXT_INPUT) } }
        item { DialogButton("ShowLoginDialog", "dialog.showLoginDialog") { show("login", LOGIN) } }
        item {
            DialogButton("ShowConfirmDialog (Coroutine)", "dialog.showConfirmCoroutine") {
                Log.d(DIALOG_TAG, "[onClick] showConfirmCoroutine")
                // Tied to this screen: leaving the screen cancels the coroutine and the dialog.
                scope.launch {
                    val text = try {
                        describe("confirm", manager.show(CONFIRM))
                    } catch (e: DialogDomainError.Canceled) {
                        "❌\nResult: confirm - Canceled: ${e.reason}"
                    } catch (e: DialogDomainError.Unavailable) {
                        "❌\nResult: confirm - Unavailable: ${e.error}"
                    }
                    ScreenResults.dialog.deliver(text)
                }
            }
        }
        item {
            DialogButton("ShowCancelableDialog", "dialog.showCancelableDialog") { show("alert", CANCELABLE_ALERT) }
        }
        item {
            DialogButton("ShowDialog And Cancel (2s)", "dialog.showAndCancel") {
                Log.d(DIALOG_TAG, "[onClick] showAndCancel")
                val requestId = show("alert", ALERT) ?: return@DialogButton
                mainHandler.postDelayed({ manager.cancel(requestId) }, 2_000)
            }
        }
    }
}

@Composable
private fun DialogButton(text: String, tag: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().testTag(tag)) {
        Text(text = text)
    }
}

// One line per result. Input values are not shown, only their lengths (log redaction rule).
private fun describe(kind: String, result: DialogResult): String = when (result) {
    is DialogResult.Button -> "✅\nResult: $kind - button: ${result.which} (${result.text})${describe(result.value)}"
    DialogResult.Dismissed -> "✅\nResult: $kind - Dismissed"
    is DialogResult.Canceled -> "❌\nResult: $kind - Canceled: ${result.reason}"
    is DialogResult.Failed -> "❌\nResult: $kind - Unavailable: ${result.error}"
}

private fun describe(value: DialogValue): String = when (value) {
    DialogValue.None -> ""
    is DialogValue.SingleChoice -> ", index: ${value.index}"
    is DialogValue.MultiChoice -> ", checked: ${value.checked}"
    is DialogValue.Text -> ", textLength: ${value.text.length}"
    is DialogValue.Login -> ", usernameLength: ${value.username.length}, passwordLength: ${value.password.length}"
}
