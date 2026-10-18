package com.jonghyunkim.nativetoolkit.notification.domain.model

import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason

/**
 * The result of a notification permission request. Exactly one result is delivered per request.
 */
sealed interface PermissionRequestResult {
    /** The permission is granted (or not needed: API 32 and lower). */
    data object Granted : PermissionRequestResult

    /** The permission is denied. */
    data object Denied : PermissionRequestResult

    /**
     * The request ended without an answer.
     *
     * @property reason Why.
     */
    data class Canceled(val reason: CancelReason) : PermissionRequestResult

    /**
     * The permission dialog could not be shown.
     *
     * @property reason Why.
     */
    data class Failed(val reason: UiUnavailableReason) : PermissionRequestResult
}

/**
 * A settings screen of the app.
 */
enum class NotificationSettingsTarget {
    /** The app's notification settings. */
    NOTIFICATIONS,

    /** The app details screen. */
    APP_DETAILS,

    /** The "Alarms & reminders" (exact alarm) screen. */
    EXACT_ALARM
}

/**
 * The result of opening a settings screen.
 */
enum class NotificationSettingsOpenResult {
    /** The requested screen opened. */
    OPENED,

    /** The requested screen was unavailable, and the app details screen opened instead. */
    OPENED_FALLBACK,

    /** No screen could be opened. */
    FAILED
}
