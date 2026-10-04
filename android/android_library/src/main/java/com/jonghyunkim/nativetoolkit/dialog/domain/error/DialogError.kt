package com.jonghyunkim.nativetoolkit.dialog.domain.error

import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason

/**
 * Why a dialog could not be shown.
 */
enum class DialogError {
    /** The library is not initialized. */
    NOT_INITIALIZED,

    /** No Activity of the app is in the foreground, or it could not show UI any more. */
    NOT_FOREGROUND,

    /** Starting the transparent host Activity failed. */
    HOST_START_FAILED,

    /** Showing the dialog failed for another reason. */
    SHOW_FAILED;

    companion object {
        /**
         * Returns the value with the same name as [reason].
         *
         * @param reason Why UI could not be shown.
         */
        fun from(reason: UiUnavailableReason): DialogError =
            when (reason) {
                UiUnavailableReason.NOT_INITIALIZED -> NOT_INITIALIZED
                UiUnavailableReason.NOT_FOREGROUND -> NOT_FOREGROUND
                UiUnavailableReason.HOST_START_FAILED -> HOST_START_FAILED
            }
    }
}

/**
 * Thrown by the suspend version of `AndroidDialogManager.show` when there is no answer.
 */
sealed class DialogDomainError : Exception() {
    /**
     * The request ended without an answer.
     *
     * @property reason Why.
     */
    data class Canceled(val reason: CancelReason) : DialogDomainError()

    /**
     * The dialog could not be shown.
     *
     * @property error Why.
     */
    data class Unavailable(val error: DialogError) : DialogDomainError()
}
