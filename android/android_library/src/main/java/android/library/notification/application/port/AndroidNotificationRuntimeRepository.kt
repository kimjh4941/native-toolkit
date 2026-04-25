package android.library.notification.application.port

import android.app.Notification
import android.app.Service
import android.library.notification.application.model.AndroidNotificationCommand

/**
 * Repository that builds and controls notifications inside foreground services.
 */
interface AndroidNotificationRuntimeRepository {
    /**
     * Builds a notification object.
     *
     * @return Built [Notification] instance.
     */
    fun build(command: AndroidNotificationCommand): Notification

    /**
     * Starts foreground mode and displays a notification.
     *
     * @param foregroundServiceType Foreground service type. If null, no explicit type is passed.
     */
    fun startForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int? = null)

    /**
     * Updates the current foreground notification.
     *
     * @param foregroundServiceType Foreground service type. If null, no explicit type is passed.
     */
    fun updateForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int? = null)

    /**
     * Stops foreground mode.
     *
     * @param removeNotification If true, also removes the foreground notification.
     */
    fun stopForeground(service: Service, removeNotification: Boolean = true)
}

