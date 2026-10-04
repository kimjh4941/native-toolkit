package com.jonghyunkim.nativetoolkit.notification.application.usecase

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.RequestIds
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationPermissionPort
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationSettingsPort
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

/**
 * Requests the notification permission.
 *
 * @param port Requests the permission.
 */
class RequestNotificationPermissionUseCase(private val port: NotificationPermissionPort) {
    /**
     * Requests the permission. [onResult] runs once on the main thread, never inside this call.
     *
     * @param onResult Receives the result.
     * @return The request ID, used to cancel the request.
     */
    operator fun invoke(onResult: (PermissionRequestResult) -> Unit): Long {
        Log.d(TAG, "[invoke] onResult: $onResult")
        val requestId = RequestIds.next()
        port.request(requestId, onResult)
        return requestId
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.application.usecase.RequestNotificationPermissionUseCase"
    }
}

/**
 * Cancels a notification permission request.
 *
 * @param port Requests the permission.
 */
class CancelNotificationPermissionRequestUseCase(private val port: NotificationPermissionPort) {
    /**
     * Cancels [requestId]: its result becomes `Canceled(REQUESTED)` unless it already has one.
     * The system dialog cannot be closed and stays on screen.
     *
     * @param requestId The ID returned by [RequestNotificationPermissionUseCase].
     */
    operator fun invoke(requestId: Long) {
        Log.d(TAG, "[invoke] requestId: $requestId")
        port.cancel(requestId)
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.application.usecase.CancelNotificationPermissionRequestUseCase"
    }
}

/**
 * Returns whether the app may schedule exact alarms.
 *
 * @param port Exact alarm queries and settings screens.
 */
class CanScheduleExactAlarmsUseCase(private val port: NotificationSettingsPort) {
    /** Returns whether the app may schedule exact alarms. */
    operator fun invoke(): Boolean {
        Log.d(TAG, "[invoke]")
        return port.canScheduleExactAlarms()
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.application.usecase.CanScheduleExactAlarmsUseCase"
    }
}

/**
 * Opens a settings screen of the app.
 *
 * @param port Exact alarm queries and settings screens.
 */
class OpenNotificationSettingsUseCase(private val port: NotificationSettingsPort) {
    /**
     * Opens [target], falling back to the app details screen.
     *
     * @param target The screen.
     */
    operator fun invoke(target: NotificationSettingsTarget): NotificationSettingsOpenResult {
        Log.d(TAG, "[invoke] target: $target")
        return port.open(target)
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.application.usecase.OpenNotificationSettingsUseCase"
    }
}
