package android.library.notification

import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationDomainModelsTest {

    @Test
    fun notificationContent_keepsProvidedChannel() {
        val channel = NotificationChannel(
            id = "updates",
            name = "Updates",
            description = "Update notifications"
        )
        val content = NotificationContent(
            id = 10,
            title = "Title",
            message = "Message",
            channel = channel
        )

        assertEquals(channel, content.channel)
        assertEquals("updates", content.channel.id)
    }

    @Test
    fun androidNotificationCommand_keepsProvidedContentIntent() {
        val intent = Intent("android.intent.action.VIEW")
        val command = AndroidNotificationCommand(
            content = NotificationContent(
                id = 42,
                title = "Title",
                message = "Message"
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = AndroidPendingIntentRequest(
                    intent = intent,
                    requestCode = 42,
                    type = AndroidPendingIntentType.ACTIVITY
                )
            )
        )

        val pendingIntentRequest = command.platformOptions.contentIntent

        assertEquals(42, pendingIntentRequest?.requestCode)
        assertEquals(AndroidPendingIntentType.ACTIVITY, pendingIntentRequest?.type)
        assertSame(intent, pendingIntentRequest?.intent)
    }

    @Test
    fun notificationSchedule_requiresPositiveTriggerTime() {
        val result = runCatching {
            NotificationSchedule(triggerAtMillis = 0L)
        }

        assertTrue(result.isFailure)
    }
}

