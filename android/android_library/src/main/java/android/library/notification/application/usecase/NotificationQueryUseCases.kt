package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.ActiveNotification
import android.util.Log

class GetActiveNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): List<ActiveNotification> {
        Log.d(TAG, "[invoke]")
        return repository.getActive()
    }
    companion object { private const val TAG = "GetActiveNotificationsUseCase" }
}

class HasNotificationPermissionUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Boolean {
        Log.d(TAG, "[invoke]")
        return repository.hasPermission()
    }
    companion object { private const val TAG = "HasNotificationPermissionUseCase" }
}

class AreNotificationsEnabledUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Boolean {
        Log.d(TAG, "[invoke]")
        return repository.areNotificationsEnabled()
    }
    companion object { private const val TAG = "AreNotificationsEnabledUseCase" }
}
