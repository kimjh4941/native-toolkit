package com.jonghyunkim.nativetoolkit.dialog.presentation

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.dialog.application.usecase.CancelDialogUseCase
import com.jonghyunkim.nativetoolkit.dialog.application.usecase.ShowDialogUseCase
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogDomainError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * The entry point for dialogs (Kotlin API design 6.3, 8.8).
 *
 * A dialog is shown on the foreground FragmentActivity, or on a transparent host Activity when the
 * foreground Activity is not a FragmentActivity. The result is delivered once on the main thread.
 * This class only delegates to the use cases.
 */
class AndroidDialogManager internal constructor(
    private val showDialog: ShowDialogUseCase,
    private val cancelDialog: CancelDialogUseCase
) {

    /**
     * Shows [request]. Callable from any thread; [onResult] runs once on the main thread, never
     * inside this call.
     *
     * @param request The dialog.
     * @param onResult Receives the result.
     * @return The request ID, used with [cancel].
     * @throws IllegalArgumentException When [request] is invalid.
     */
    fun show(request: DialogRequest, onResult: (DialogResult) -> Unit): Long {
        Log.d(TAG, "[show] request: $request, onResult: $onResult")
        return showDialog(request, onResult)
    }

    /**
     * Shows [request] and waits for the user's answer. Cancelling the coroutine cancels the dialog.
     *
     * @param request The dialog.
     * @return The answer: a button press or a dismissal.
     * @throws DialogDomainError.Canceled When the request ended without an answer.
     * @throws DialogDomainError.Unavailable When the dialog could not be shown.
     * @throws IllegalArgumentException When [request] is invalid.
     */
    suspend fun show(request: DialogRequest): DialogResult.Answer {
        Log.d(TAG, "[show] request: $request")
        return suspendCancellableCoroutine { continuation ->
            val requestId = showDialog(request) { result ->
                when (result) {
                    is DialogResult.Answer -> continuation.resume(result)
                    is DialogResult.Canceled ->
                        continuation.resumeWithException(DialogDomainError.Canceled(result.reason))
                    is DialogResult.Failed ->
                        continuation.resumeWithException(DialogDomainError.Unavailable(result.error))
                }
            }
            continuation.invokeOnCancellation { cancelDialog(requestId) }
        }
    }

    /**
     * Cancels a dialog. Its result becomes `Canceled(REQUESTED)` unless it already has one.
     * Unknown IDs are ignored. Callable from any thread.
     *
     * @param requestId The ID returned by [show].
     */
    fun cancel(requestId: Long) {
        Log.d(TAG, "[cancel] requestId: $requestId")
        cancelDialog(requestId)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.dialog.presentation.AndroidDialogManager"

        private val instance: AndroidDialogManager by lazy {
            AndroidDialogManager(
                ShowDialogUseCase(FragmentDialogPresenter),
                CancelDialogUseCase(FragmentDialogPresenter)
            )
        }

        /**
         * Returns the process-wide instance.
         *
         * @param context Any Context. Dialogs use the library runtime, so the Context is not kept.
         */
        @JvmStatic
        fun getInstance(context: Context): AndroidDialogManager {
            Log.d(TAG, "[getInstance] context: $context")
            return instance
        }
    }
}
