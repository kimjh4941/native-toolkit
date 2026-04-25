package android.library.notification.application.usecase

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.NotificationCommandRepository
import android.util.Log

/**
 * Use case for showing a notification.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class ShowNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command")
        return runCatching { repository.send(command) }
    }
    companion object { private const val TAG = "ShowNotificationUseCase" }
}

/**
 * Use case for updating a notification.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class UpdateNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command")
        return runCatching { repository.update(command) }
    }
    companion object { private const val TAG = "UpdateNotificationUseCase" }
}

/**
 * Use case for canceling a specific notification.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CancelNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[invoke] id: $id, tag: $tag")
        return runCatching { repository.cancel(id, tag) }
    }
    companion object { private const val TAG = "CancelNotificationUseCase" }
}

/**
 * Use case for canceling all notifications.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CancelAllNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.cancelAll() }
    }
    companion object { private const val TAG = "CancelAllNotificationsUseCase" }
}
