package com.jonghyunkim.nativetoolkit.notification.domain.error

import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason

/**
 * Thrown by the suspend version of `AndroidNotificationManager.requestPermission` when there is
 * no answer.
 */
sealed class PermissionRequestDomainError : Exception() {
    /**
     * The request ended without an answer.
     *
     * @property reason Why.
     */
    data class Canceled(val reason: CancelReason) : PermissionRequestDomainError()

    /**
     * The permission dialog could not be shown.
     *
     * @property reason Why.
     */
    data class Unavailable(val reason: UiUnavailableReason) : PermissionRequestDomainError()
}
