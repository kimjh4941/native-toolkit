package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogButton
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

/**
 * The C ABI's entry to dialogs (C ABI design part 2, 5.1, 5.3, 6.2). Every dialog is
 * asynchronous: the insertion, the foreground check and [AndroidDialogManager.show] run in one
 * main-thread message; the result completes the C registration with the C request id. The C id
 * and the Kotlin request id are paired in [kotlinIds], on the main thread only.
 */
internal object DialogBridge {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.DialogBridge"

    /** The ledger kind of dialog requests. */
    const val KIND_REQUEST = 200

    // ntk_dialog_error 6 to 10 (part 2, 11.1).
    private const val CANCELED = 6
    private const val CANCELED_BY_SYSTEM = 7
    private const val NOT_FOREGROUND = 8
    private const val HOST_START_FAILED = 9
    private const val SHOW_FAILED = 10

    // ntk_dialog_answer and ntk_dialog_button.
    private const val ANSWER_BUTTON = 0
    private const val ANSWER_DISMISSED = 1

    /** C request id to Kotlin request id, while the dialog is up. Main thread only. */
    private val kotlinIds = HashMap<Long, Long>()

    private fun manager(): AndroidDialogManager {
        Log.d(TAG, "[manager]")
        return AndroidDialogManager.getInstance(NtkRuntime.context())
    }

    private fun options(cancelable: Boolean, cancelableOnTouchOutside: Boolean): DialogOptions {
        Log.d(TAG, "[options] cancelable: $cancelable, cancelableOnTouchOutside: $cancelableOnTouchOutside")
        return DialogOptions(cancelable, cancelableOnTouchOutside)
    }

    // --- the six dialogs (OP-13 to OP-18). Text defaults are applied here: a null title,
    // message or input hint is "", a null button text or login hint is Kotlin's default. ---

    @JvmStatic
    fun showAlert(id: Long, title: ByteArray?, message: ByteArray?, buttonText: ByteArray?,
                  cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showAlert] id: $id, cancelable: $cancelable, cancelableOnTouchOutside: $cancelableOnTouchOutside")
        return post(id) {
            val defaults = DialogRequest.Alert("", "")
            DialogRequest.Alert(
                text(title), text(message), Utf8.decodeOrNull(buttonText) ?: defaults.buttonText,
                options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    @JvmStatic
    fun showConfirm(id: Long, title: ByteArray?, message: ByteArray?, negativeText: ByteArray?,
                    positiveText: ByteArray?, cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showConfirm] id: $id, cancelable: $cancelable, cancelableOnTouchOutside: $cancelableOnTouchOutside")
        return post(id) {
            val defaults = DialogRequest.Confirm("", "")
            DialogRequest.Confirm(
                text(title), text(message),
                Utf8.decodeOrNull(negativeText) ?: defaults.negativeText,
                Utf8.decodeOrNull(positiveText) ?: defaults.positiveText,
                options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    @JvmStatic
    fun showSingleChoice(id: Long, title: ByteArray?, items: Array<ByteArray>, checkedIndex: Int,
                         negativeText: ByteArray?, positiveText: ByteArray?,
                         cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showSingleChoice] id: $id, itemCount: ${items.size}, checkedIndex: $checkedIndex")
        return post(id) {
            val defaults = DialogRequest.SingleChoice("", listOf(""))
            DialogRequest.SingleChoice(
                text(title), items.map(Utf8::decode), checkedIndex.takeIf { it >= 0 },
                Utf8.decodeOrNull(negativeText) ?: defaults.negativeText,
                Utf8.decodeOrNull(positiveText) ?: defaults.positiveText,
                options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    @JvmStatic
    fun showMultiChoice(id: Long, title: ByteArray?, items: Array<ByteArray>, checked: BooleanArray,
                        negativeText: ByteArray?, positiveText: ByteArray?,
                        cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showMultiChoice] id: $id, itemCount: ${items.size}")
        return post(id) {
            val defaults = DialogRequest.MultiChoice("", listOf(""), listOf(false))
            DialogRequest.MultiChoice(
                text(title), items.map(Utf8::decode), checked.toList(),
                Utf8.decodeOrNull(negativeText) ?: defaults.negativeText,
                Utf8.decodeOrNull(positiveText) ?: defaults.positiveText,
                options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    @JvmStatic
    fun showTextInput(id: Long, title: ByteArray?, message: ByteArray?, hint: ByteArray?,
                      negativeText: ByteArray?, positiveText: ByteArray?, enablePositiveWhenEmpty: Boolean,
                      cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showTextInput] id: $id, enablePositiveWhenEmpty: $enablePositiveWhenEmpty")
        return post(id) {
            val defaults = DialogRequest.TextInput("", "")
            DialogRequest.TextInput(
                text(title), text(message), text(hint),
                Utf8.decodeOrNull(negativeText) ?: defaults.negativeText,
                Utf8.decodeOrNull(positiveText) ?: defaults.positiveText,
                enablePositiveWhenEmpty, options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    @JvmStatic
    fun showLogin(id: Long, title: ByteArray?, message: ByteArray?, usernameHint: ByteArray?,
                  passwordHint: ByteArray?, negativeText: ByteArray?, positiveText: ByteArray?,
                  enablePositiveWhenEmpty: Boolean, cancelable: Boolean, cancelableOnTouchOutside: Boolean): Boolean {
        Log.d(TAG, "[showLogin] id: $id, enablePositiveWhenEmpty: $enablePositiveWhenEmpty")
        return post(id) {
            val defaults = DialogRequest.Login("", "")
            DialogRequest.Login(
                text(title), text(message),
                Utf8.decodeOrNull(usernameHint) ?: defaults.usernameHint,
                Utf8.decodeOrNull(passwordHint) ?: defaults.passwordHint,
                Utf8.decodeOrNull(negativeText) ?: defaults.negativeText,
                Utf8.decodeOrNull(positiveText) ?: defaults.positiveText,
                enablePositiveWhenEmpty, options(cancelable, cancelableOnTouchOutside)
            )
        }
    }

    /**
     * Closes the Kotlin dialog of a C request that C has moved to CANCEL_REQUESTED (OP-19). The
     * removal C posted before this completes the request with CANCELED; the dialog's own result,
     * arriving later, finds the registration gone.
     */
    @JvmStatic
    fun cancel(id: Long): Boolean {
        Log.d(TAG, "[cancel] id: $id")
        return MainTasks.post("DialogBridge.cancel") {
            kotlinIds.remove(id)?.let { manager().cancel(it) }
        }
    }

    private fun text(bytes: ByteArray?): String {
        Log.d(TAG, "[text] size: ${bytes?.size}")
        return Utf8.decodeOrNull(bytes) ?: ""
    }

    // The insertion and the start in one main message (design part 1, 5.7). A request cancelled
    // before it is inserted is not shown at all.
    private fun post(id: Long, build: () -> DialogRequest): Boolean {
        Log.d(TAG, "[post] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_REQUEST)) return@post
            if (!Foreground.isForeground()) {
                finish(id) { nativeFailed(id, NOT_FOREGROUND) }
                return@post
            }
            try {
                val kotlinId = manager().show(build()) { result -> onResult(id, result) }
                // onResult never runs inside show, so the pair is in place before it does.
                kotlinIds[id] = kotlinId
            } catch (e: Throwable) {
                Log.e(TAG, "[post] the dialog was not shown: ${e.javaClass.name}")
                finish(id) { nativeFailed(id, Errors.common(e)) }
            }
        }
    }

    private fun finish(id: Long, complete: () -> Unit) {
        Log.d(TAG, "[finish] id: $id")
        kotlinIds.remove(id)
        Ledger.remove(id)
        complete()
    }

    private fun onResult(id: Long, result: DialogResult) {
        Log.d(TAG, "[onResult] id: $id, result: ${result.javaClass.simpleName}")
        finish(id) {
            when (result) {
                is DialogResult.Button -> complete(id, result)
                DialogResult.Dismissed -> nativeAnswered(id, ANSWER_DISMISSED, 0, null, -1, null, null, null, null)
                is DialogResult.Canceled -> nativeFailed(
                    id, if (result.reason == CancelReason.REQUESTED) CANCELED else CANCELED_BY_SYSTEM
                )
                is DialogResult.Failed -> nativeFailed(id, errorOf(result.error))
            }
        }
    }

    // The values of a button press (part 2, 6.2). Text input and passwords are secrets: not logged.
    private fun complete(id: Long, result: DialogResult.Button) {
        Log.d(TAG, "[complete] id: $id, which: ${result.which}, value: ${result.value}")
        val button = if (result.which == DialogButton.POSITIVE) 0 else 1
        val buttonText = Utf8.encode(result.text)
        when (val value = result.value) {
            DialogValue.None -> nativeAnswered(id, ANSWER_BUTTON, button, buttonText, -1, null, null, null, null)
            is DialogValue.SingleChoice ->
                nativeAnswered(id, ANSWER_BUTTON, button, buttonText, value.index ?: -1, null, null, null, null)
            is DialogValue.MultiChoice ->
                nativeAnswered(id, ANSWER_BUTTON, button, buttonText, -1, value.checked.toBooleanArray(), null, null, null)
            is DialogValue.Text ->
                nativeAnswered(id, ANSWER_BUTTON, button, buttonText, -1, null, Utf8.encode(value.text), null, null)
            is DialogValue.Login -> nativeAnswered(
                id, ANSWER_BUTTON, button, buttonText, -1, null, null, Utf8.encode(value.username), Utf8.encode(value.password)
            )
        }
    }

    /** The value of ntk_dialog_error for a Kotlin failure (part 2, 11.1). */
    fun errorOf(error: DialogError): Int {
        Log.d(TAG, "[errorOf] error: $error")
        return when (error) {
            DialogError.NOT_INITIALIZED -> Errors.NOT_INITIALIZED
            DialogError.NOT_FOREGROUND -> NOT_FOREGROUND
            DialogError.HOST_START_FAILED -> HOST_START_FAILED
            DialogError.SHOW_FAILED -> SHOW_FAILED
        }
    }

    /** Completes a C request with an answer. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeAnswered(
        id: Long, answer: Int, button: Int, buttonText: ByteArray?, checkedIndex: Int, checked: BooleanArray?,
        text: ByteArray?, username: ByteArray?, password: ByteArray?
    )

    /** Completes a C request with an error and no result. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeFailed(id: Long, error: Int)
}
