package com.jonghyunkim.nativetoolkit.dialog.application.port

import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

/**
 * Shows dialogs. The implementation posts to the main thread, so both functions may be called from
 * any thread. [onResult] runs once on the main thread.
 */
interface DialogPresenter {
    /**
     * Shows [request] and reports its result once.
     *
     * @param requestId The request ID.
     * @param request The dialog.
     * @param onResult Receives the result on the main thread.
     */
    fun show(requestId: Long, request: DialogRequest, onResult: (DialogResult) -> Unit)

    /**
     * Cancels [requestId]. Unknown or completed IDs are ignored.
     *
     * @param requestId The request ID.
     */
    fun cancel(requestId: Long)
}
