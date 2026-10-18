package com.jonghyunkim.nativetoolkit.notification.presentation.event

import com.jonghyunkim.nativetoolkit.common.event.EventHub

/**
 * What the user did with a notification (Kotlin API design 8.5).
 *
 * @property kind What happened.
 * @property notificationId The notification ID.
 * @property tag The notification tag, or `null`.
 * @property actionId The action ID for [Kind.ACTION], otherwise `null`.
 * @property data The data given to `NotificationEventIntents`. [toString] hides the values.
 */
class NotificationInteraction(
    val kind: Kind,
    val notificationId: Int,
    val tag: String?,
    val actionId: String?,
    val data: Map<String, String>
) {
    /** What happened. */
    enum class Kind {
        /** The notification body was tapped. */
        BODY_TAP,

        /** An action button or a custom-view click target was tapped. */
        ACTION,

        /** The notification was dismissed. */
        DISMISS
    }

    override fun equals(other: Any?): Boolean =
        other is NotificationInteraction && other.kind == kind && other.notificationId == notificationId &&
            other.tag == tag && other.actionId == actionId && other.data == data

    override fun hashCode(): Int =
        listOf(kind, notificationId, tag, actionId, data).hashCode()

    override fun toString(): String =
        "NotificationInteraction(kind=$kind, notificationId=$notificationId, tag=$tag, actionId=$actionId, dataKeys=${data.keys})"
}

/**
 * A scheduled notification was shown.
 *
 * @property notificationId The notification ID.
 * @property tag The notification tag, or `null`.
 * @property channelId The channel ID.
 */
data class NotificationShown(val notificationId: Int, val tag: String?, val channelId: String)

/**
 * The notification event hubs (Kotlin API design 8.4). `AndroidNotificationManager` exposes them.
 */
internal object NotificationEvents {

    /** Taps, actions and dismissals. Up to 32 events are kept while no listener is registered. */
    val interactions: EventHub<NotificationInteraction> =
        EventHub(EventHub.Retention.UntilFirstListener(capacity = 32))

    /** Scheduled notifications that were shown. Not kept. */
    val shown: EventHub<NotificationShown> = EventHub(EventHub.Retention.None)
}
