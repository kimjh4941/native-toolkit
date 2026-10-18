package com.jonghyunkim.nativetoolkit.share.application.usecase

import com.jonghyunkim.nativetoolkit.share.application.port.RichPreviewShareRepository
import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import android.util.Log

/**
 * Use case for cancelling the pending share-callback BroadcastReceiver.
 *
 * @param repository Share repository.
 */
class CancelPendingShareCallbackUseCase(private val repository: ShareRepository) {
    /**
     * Cancels any registered share-callback receiver, preventing further notifications.
     */
    operator fun invoke() {
        Log.d(TAG, "[invoke]")
        (repository as? RichPreviewShareRepository)?.cancelPendingCallback()
    }
    companion object { private const val TAG = "CancelPendingShareCallbackUseCase" }
}
