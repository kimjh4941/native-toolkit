package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.NotificationChannel
import android.util.Log

/**
 * Use case for creating a notification channel.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CreateNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channel: NotificationChannel): Result<Unit> {
        Log.d(TAG, "[invoke] channel: $channel")
        return runCatching { repository.createChannel(channel) }
    }
    companion object { private const val TAG = "CreateNotificationChannelUseCase" }
}

/**
 * Use case for creating multiple notification channels in a batch.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CreateNotificationChannelsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channels: List<NotificationChannel>): Result<Unit> {
        Log.d(TAG, "[invoke] channels: $channels")
        return runCatching { repository.createChannels(channels) }
    }
    companion object { private const val TAG = "CreateNotificationChannelsUseCase" }
}

/**
 * Use case for deleting a notification channel.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class DeleteNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channelId: String): Result<Unit> {
        Log.d(TAG, "[invoke] channelId: $channelId")
        return runCatching { repository.deleteChannel(channelId) }
    }
    companion object { private const val TAG = "DeleteNotificationChannelUseCase" }
}
