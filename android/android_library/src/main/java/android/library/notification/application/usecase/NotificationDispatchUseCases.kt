package android.library.notification.application.usecase

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.NotificationCommandRepository
import android.util.Log

class ShowNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command")
        return runCatching { repository.send(command) }
    }
    companion object { private const val TAG = "ShowNotificationUseCase" }
}

class UpdateNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command")
        return runCatching { repository.update(command) }
    }
    companion object { private const val TAG = "UpdateNotificationUseCase" }
}

class CancelNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[invoke] id: $id, tag: $tag")
        return runCatching { repository.cancel(id, tag) }
    }
    companion object { private const val TAG = "CancelNotificationUseCase" }
}

class CancelAllNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.cancelAll() }
    }
    companion object { private const val TAG = "CancelAllNotificationsUseCase" }
}
