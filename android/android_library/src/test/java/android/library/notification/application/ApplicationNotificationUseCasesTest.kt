package android.library.notification.application

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.port.AndroidNotificationRuntimeRepository
import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.application.usecase.AreNotificationsEnabledUseCase
import android.library.notification.application.usecase.BuildNotificationUseCase
import android.library.notification.application.usecase.CancelNotificationUseCase
import android.library.notification.application.usecase.CreateNotificationChannelUseCase
import android.library.notification.application.usecase.ScheduleNotificationUseCase
import android.library.notification.application.usecase.ShowNotificationUseCase
import android.library.notification.domain.model.ActiveNotification
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ApplicationNotificationUseCasesTest {

    @Test
    fun showNotification_delegatesCommandToRepository() {
        val repository = FakeCommandRepository()
        val command = sampleCommand()

        ShowNotificationUseCase(repository)(command)

        assertSame(command, repository.lastSentCommand)
    }

    @Test
    fun createChannel_delegatesDomainChannelToRepository() {
        val repository = FakeCommandRepository()
        val channel = NotificationChannel(id = "updates", name = "Updates")

        CreateNotificationChannelUseCase(repository)(channel)

        assertEquals(channel, repository.lastCreatedChannel)
    }

    @Test
    fun scheduleNotification_returnsRepositoryResult() {
        val repository = FakeCommandRepository(scheduleResult = true)
        val command = sampleCommand()
        val schedule = NotificationSchedule(triggerAtMillis = 15_000L)

        val result = ScheduleNotificationUseCase(repository)(command, schedule)

        assertTrue(result)
        assertSame(command, repository.lastScheduledCommand)
        assertEquals(schedule, repository.lastSchedule)
    }

    @Test
    fun cancelNotification_passesIdAndTag() {
        val repository = FakeCommandRepository()

        CancelNotificationUseCase(repository)(10, "boot")

        assertEquals(10, repository.lastCanceledId)
        assertEquals("boot", repository.lastCanceledTag)
    }

    @Test
    fun areNotificationsEnabled_returnsRepositoryValue() {
        val repository = FakeCommandRepository(areEnabled = true)

        val result = AreNotificationsEnabledUseCase(repository)()

        assertTrue(result)
    }

    @Test
    fun buildNotification_returnsRuntimeNotification() {
        val notification = Notification()
        val runtimeRepository = FakeRuntimeRepository(notification)
        val command = sampleCommand()

        val result = BuildNotificationUseCase(runtimeRepository)(command)

        assertSame(notification, result)
        assertSame(command, runtimeRepository.lastBuiltCommand)
    }

    private fun sampleCommand(): AndroidNotificationCommand {
        return AndroidNotificationCommand(
            content = NotificationContent(
                id = 1,
                title = "Title",
                message = "Message"
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = AndroidPendingIntentRequest(
                    intent = Intent("sample.action.OPEN"),
                    requestCode = 1
                )
            )
        )
    }

    private class FakeCommandRepository(
        private val scheduleResult: Boolean = false,
        private val areEnabled: Boolean = false
    ) : NotificationCommandRepository {
        var lastSentCommand: AndroidNotificationCommand? = null
        var lastScheduledCommand: AndroidNotificationCommand? = null
        var lastSchedule: NotificationSchedule? = null
        var lastCreatedChannel: NotificationChannel? = null
        var lastCanceledId: Int? = null
        var lastCanceledTag: String? = null

        override fun send(command: AndroidNotificationCommand) {
            lastSentCommand = command
        }

        override fun update(command: AndroidNotificationCommand) = Unit

        override fun cancel(id: Int, tag: String?) {
            lastCanceledId = id
            lastCanceledTag = tag
        }

        override fun cancelAll() = Unit

        override fun createChannel(channel: NotificationChannel) {
            lastCreatedChannel = channel
        }

        override fun createChannels(channels: List<NotificationChannel>) = Unit

        override fun deleteChannel(channelId: String) = Unit

        override fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean {
            lastScheduledCommand = command
            lastSchedule = schedule
            return scheduleResult
        }

        override fun cancelScheduled(id: Int, tag: String?) = Unit

        override fun cancelAllScheduled() = Unit

        override fun restoreScheduled() = Unit

        override fun getActive(): List<ActiveNotification> = emptyList()

        override fun hasPermission(): Boolean = true

        override fun areNotificationsEnabled(): Boolean = areEnabled
    }

    private class FakeRuntimeRepository(
        private val notification: Notification
    ) : AndroidNotificationRuntimeRepository {
        var lastBuiltCommand: AndroidNotificationCommand? = null

        override fun build(command: AndroidNotificationCommand): Notification {
            lastBuiltCommand = command
            return notification
        }

        override fun startForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int?) = Unit

        override fun updateForeground(service: Service, command: AndroidNotificationCommand, foregroundServiceType: Int?) = Unit

        override fun stopForeground(service: Service, removeNotification: Boolean) = Unit
    }
}

