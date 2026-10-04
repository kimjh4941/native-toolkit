package com.jonghyunkim.nativetoolkit.share.application.usecase

import android.util.Log
import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository

/**
 * Use case for no longer waiting for the selection of one Sharesheet.
 *
 * @param repository Share repository.
 */
class CancelShareSelectionUseCase(private val repository: ShareRepository) {
    /**
     * Stops waiting when [token] is the current wait; otherwise does nothing.
     *
     * @param token A value returned by [ShareForSelectionUseCase].
     */
    operator fun invoke(token: Long) {
        Log.d(TAG, "[invoke] token: $token")
        repository.cancelShareSelection(token)
    }

    private companion object {
        private const val TAG = "CancelShareSelectionUseCase"
    }
}
