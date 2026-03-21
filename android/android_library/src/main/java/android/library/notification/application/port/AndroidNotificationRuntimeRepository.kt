package android.library.notification.application.port

import android.app.Notification
import android.app.Service
import android.library.notification.application.model.AndroidNotificationCommand

interface AndroidNotificationRuntimeRepository {
    fun build(command: AndroidNotificationCommand): Notification
    fun startForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int? = null)
    fun updateForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int? = null)
    fun stopForeground(service: Service, removeNotification: Boolean = true)
}

