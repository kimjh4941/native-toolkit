package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository

class NotificationUseCases(repository: NotificationCommandRepository) {

    val show = ShowNotificationUseCase(repository)
    val update = UpdateNotificationUseCase(repository)
    val cancel = CancelNotificationUseCase(repository)
    val cancelAll = CancelAllNotificationsUseCase(repository)

    val schedule = ScheduleNotificationUseCase(repository)
    val cancelScheduled = CancelScheduledNotificationUseCase(repository)
    val cancelAllScheduled = CancelAllScheduledNotificationsUseCase(repository)
    val restoreScheduled = RestoreScheduledNotificationsUseCase(repository)

    val createChannel = CreateNotificationChannelUseCase(repository)
    val createChannels = CreateNotificationChannelsUseCase(repository)
    val deleteChannel = DeleteNotificationChannelUseCase(repository)

    val hasPermission = HasNotificationPermissionUseCase(repository)
    val areNotificationsEnabled = AreNotificationsEnabledUseCase(repository)
    val getActive = GetActiveNotificationsUseCase(repository)
}
