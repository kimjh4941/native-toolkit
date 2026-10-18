package com.jonghyunkim.nativetoolkit.notification.application.port

import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

/**
 * Requests the notification permission. Both functions may be called from any thread; [onResult]
 * runs once on the main thread.
 */
interface NotificationPermissionPort {
    /**
     * Requests the permission and reports the result once.
     *
     * @param requestId The request ID.
     * @param onResult Receives the result on the main thread.
     */
    fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit)

    /**
     * Cancels [requestId]. Unknown or completed IDs are ignored.
     *
     * @param requestId The request ID.
     */
    fun cancel(requestId: Long)
}

/**
 * Exact alarm queries and settings screens.
 */
interface NotificationSettingsPort {
    /** Returns whether the app may schedule exact alarms. */
    fun canScheduleExactAlarms(): Boolean

    /**
     * Opens [target], falling back to the app details screen.
     *
     * @param target The screen.
     */
    fun open(target: NotificationSettingsTarget): NotificationSettingsOpenResult
}
