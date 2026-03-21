package android.library.notification.application

import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.data.repository.toCommand
import android.library.notification.data.repository.toDomain
import android.library.notification.data.repository.toPayload
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class NotificationPayloadMappersTest {

    @Test
    fun commandPayload_roundTrip_preservesCoreFields() {
        val intent = Intent("sample.action.OPEN")
        val command = AndroidNotificationCommand(
            content = NotificationContent(
                id = 101,
                title = "Native Toolkit",
                message = "Ready",
                tag = "boot",
                channel = NotificationChannel(
                    id = "updates",
                    name = "Updates",
                    description = "General updates"
                ),
                smallIconResId = 123,
                largeIconResId = 456,
                groupKey = "group.updates",
                isGroupSummary = true
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = AndroidPendingIntentRequest(
                    intent = intent,
                    requestCode = 101,
                    type = AndroidPendingIntentType.ACTIVITY
                )
            )
        )

        val restored = command.toPayload().toCommand()

        assertEquals(command.content.id, restored.content.id)
        assertEquals(command.content.title, restored.content.title)
        assertEquals(command.content.channel.id, restored.content.channel.id)
        assertEquals(command.content.groupKey, restored.content.groupKey)
        assertEquals(command.content.isGroupSummary, restored.content.isGroupSummary)
        assertSame(intent, restored.platformOptions.contentIntent?.intent)
    }

    @Test
    fun schedulePayload_roundTrip_preservesFields() {
        val schedule = NotificationSchedule(
            triggerAtMillis = 10_000L,
            exact = false,
            allowWhileIdle = false,
            persistAcrossBoot = false,
            alarmType = 2
        )

        val restored = schedule.toPayload().toDomain()

        assertEquals(schedule.triggerAtMillis, restored.triggerAtMillis)
        assertEquals(schedule.exact, restored.exact)
        assertEquals(schedule.allowWhileIdle, restored.allowWhileIdle)
        assertEquals(schedule.persistAcrossBoot, restored.persistAcrossBoot)
        assertEquals(schedule.alarmType, restored.alarmType)
    }
}

