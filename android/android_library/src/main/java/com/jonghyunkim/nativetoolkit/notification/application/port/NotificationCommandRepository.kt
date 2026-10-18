package com.jonghyunkim.nativetoolkit.notification.application.port

import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.domain.model.ActiveNotification
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule

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
     * A schedule with `persistAcrossBoot` is saved so that it can be restored after a reboot. When
     * the save fails, the Alarm stays set but is not restored after a reboot.
     *
     * @return True if registration succeeds.
     * @throws java.io.IOException When the saved schedules cannot be written.
     */
    fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean

    /**
     * Cancels the schedule for a specific notification.
     *
     * When removing the saved schedule fails, the Alarm stays canceled but the schedule may come
     * back after a reboot.
     *
     * @param id Notification ID.
     * @param tag Optional notification tag.
     * @throws java.io.IOException When the saved schedules cannot be written.
     */
    fun cancelScheduled(id: Int, tag: String? = null)

    /**
     * Cancels all scheduled notifications.
     *
     * When clearing the saved schedules fails, the Alarms stay canceled but the schedules may come
     * back after a reboot.
     *
     * @throws java.io.IOException When the saved schedules cannot be written.
     */
    fun cancelAllScheduled()

    /**
     * Restores previously scheduled notifications, mainly after device reboot.
     *
     * A failure to write one saved schedule is logged and the others are still restored.
     *
     * @throws java.io.IOException After every schedule was handled, when a write failed.
     */
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

