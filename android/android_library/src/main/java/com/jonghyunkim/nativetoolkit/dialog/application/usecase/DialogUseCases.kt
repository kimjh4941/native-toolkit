package com.jonghyunkim.nativetoolkit.dialog.application.usecase

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.RequestIds
import com.jonghyunkim.nativetoolkit.dialog.application.port.DialogPresenter
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

/**
 * Checks a dialog request and shows it.
 *
 * @param presenter Shows dialogs.
 */
class ShowDialogUseCase(private val presenter: DialogPresenter) {
    /**
     * Checks [request], assigns a request ID and shows the dialog. [onResult] runs once on the main
     * thread, never inside this call.
     *
     * @param request The dialog.
     * @param onResult Receives the result.
     * @return The request ID, used to cancel the dialog.
     * @throws IllegalArgumentException When [request] is invalid (an empty list, a selection of the
     *   wrong size, or an initial index out of range).
     */
    operator fun invoke(request: DialogRequest, onResult: (DialogResult) -> Unit): Long {
        Log.d(TAG, "[invoke] request: $request, onResult: $onResult")
        validate(request)
        val requestId = RequestIds.next()
        presenter.show(requestId, request, onResult)
        return requestId
    }

    private fun validate(request: DialogRequest) {
        when (request) {
            is DialogRequest.SingleChoice -> {
                require(request.items.isNotEmpty()) { "items must not be empty" }
                val index = request.checkedIndex
                require(index == null || index in request.items.indices) {
                    "checkedIndex $index is out of range for ${request.items.size} items"
                }
            }
            is DialogRequest.MultiChoice -> {
                require(request.items.isNotEmpty()) { "items must not be empty" }
                require(request.checked.size == request.items.size) {
                    "checked has ${request.checked.size} values for ${request.items.size} items"
                }
            }
            else -> Unit
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.dialog.application.usecase.ShowDialogUseCase"
    }
}

/**
 * Cancels a dialog.
 *
 * @param presenter Shows dialogs.
 */
class CancelDialogUseCase(private val presenter: DialogPresenter) {
    /**
     * Cancels [requestId]. The dialog's result becomes `Canceled(REQUESTED)` unless it already has
     * a result. Unknown IDs are ignored.
     *
     * @param requestId The ID returned by [ShowDialogUseCase].
     */
    operator fun invoke(requestId: Long) {
        Log.d(TAG, "[invoke] requestId: $requestId")
        presenter.cancel(requestId)
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.dialog.application.usecase.CancelDialogUseCase"
    }
}
