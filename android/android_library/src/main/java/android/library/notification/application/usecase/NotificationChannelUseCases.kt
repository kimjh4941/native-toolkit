package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.NotificationChannel
import android.util.Log

class CreateNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channel: NotificationChannel): Result<Unit> {
        Log.d(TAG, "[invoke] channel: $channel")
        return runCatching { repository.createChannel(channel) }
    }
    companion object { private const val TAG = "CreateNotificationChannelUseCase" }
}

class CreateNotificationChannelsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channels: List<NotificationChannel>): Result<Unit> {
        Log.d(TAG, "[invoke] channels: $channels")
        return runCatching { repository.createChannels(channels) }
    }
    companion object { private const val TAG = "CreateNotificationChannelsUseCase" }
}

class DeleteNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channelId: String): Result<Unit> {
        Log.d(TAG, "[invoke] channelId: $channelId")
        return runCatching { repository.deleteChannel(channelId) }
    }
    companion object { private const val TAG = "DeleteNotificationChannelUseCase" }
}
