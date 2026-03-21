package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.NotificationChannel

class CreateNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channel: NotificationChannel) {
        repository.createChannel(channel)
    }
}

class CreateNotificationChannelsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channels: List<NotificationChannel>) {
        repository.createChannels(channels)
    }
}

class DeleteNotificationChannelUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(channelId: String) {
        repository.deleteChannel(channelId)
    }
}

