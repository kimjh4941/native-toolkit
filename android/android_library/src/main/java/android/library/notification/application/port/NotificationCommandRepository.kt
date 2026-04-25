package android.library.notification.application.port

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.ActiveNotification
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationSchedule

/**
 * Repository responsible for notification posting and management operations.
 */
interface NotificationCommandRepository {
    /** Shows a notification. */
    fun send(command: AndroidNotificationCommand)

    /** Updates a notification. */
    fun update(command: AndroidNotificationCommand)

    /**
     * Cancels the specified notification.
     *
     * @param id Notification ID.
     * @param tag Optional notification tag.
     */
    fun cancel(id: Int, tag: String? = null)

    /** Cancels all notifications. */
    fun cancelAll()

    /** Creates a notification channel. */
    fun createChannel(channel: NotificationChannel)

    /** Creates multiple notification channels in a batch. */
    fun createChannels(channels: List<NotificationChannel>)

    /**
     * Deletes a notification channel.
     *
     * @param channelId ID of the channel to delete.
     */
    fun deleteChannel(channelId: String)

    /**
     * Registers a scheduled notification.
     *
     * @return True if registration succeeds.
     */
    fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean

    /**
     * Cancels the schedule for a specific notification.
     *
     * @param id Notification ID.
     * @param tag Optional notification tag.
     */
    fun cancelScheduled(id: Int, tag: String? = null)

    /** Cancels all scheduled notifications. */
    fun cancelAllScheduled()

    /** Restores previously scheduled notifications, mainly after device reboot. */
    fun restoreScheduled()

    /**
     * Returns currently active notifications.
     *
     * @return List of [ActiveNotification].
     */
    fun getActive(): List<ActiveNotification>

    /**
     * Checks whether notification permission is granted.
     *
     * @return True if permission is granted.
     */
    fun hasPermission(): Boolean

    /**
     * Checks whether app notifications are enabled.
     *
     * @return True if notifications are enabled.
     */
    fun areNotificationsEnabled(): Boolean
}

