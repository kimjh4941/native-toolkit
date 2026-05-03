package android.unity.notification

import android.content.Intent
import android.content.ContextWrapper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UnityAndroidNotificationManagerTest {

    @After
    fun tearDown() {
        UnityAndroidNotificationManager.clearNotificationOperationListener()
    }

    @Test
    fun createChannel_notifiesInvalidArgumentFailure() {
        val listener = CapturingListener()
        UnityAndroidNotificationManager.setNotificationOperationListener(listener)

        UnityAndroidNotificationManager.createChannel(
            context = RecordingContext(),
            channelJson = """
                {
                  "name": "Updates"
                }
            """.trimIndent()
        )

        assertEquals(UnityAndroidNotificationManager.OPERATION_CREATE_CHANNEL, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("Invalid argument"))
        assertTrue(listener.errorMessage.orEmpty().contains("id is required"))
    }

    @Test
    fun startProgressForegroundService_notifiesFailureWhenProgressIsMissing() {
        val listener = CapturingListener()
        UnityAndroidNotificationManager.setNotificationOperationListener(listener)

        UnityAndroidNotificationManager.startProgressForegroundService(
            context = RecordingContext(),
            notificationJson = """
                {
                  "id": 3001,
                  "title": "Background Sync",
                  "message": "Syncing...",
                  "channel": {
                    "id": "progress",
                    "name": "Progress"
                  }
                }
            """.trimIndent()
        )

        assertEquals(
            UnityAndroidNotificationManager.OPERATION_START_PROGRESS_FOREGROUND_SERVICE,
            listener.operation
        )
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("progress is required"))
    }

    @Test
    fun showNotification_notifiesInvalidArgumentFailureWhenTitleIsMissing() {
        val listener = CapturingListener()
        UnityAndroidNotificationManager.setNotificationOperationListener(listener)

        UnityAndroidNotificationManager.showNotification(
            context = RecordingContext(),
            notificationJson = """
                {
                  "id": 4001,
                  "message": "Missing title",
                  "channel": {
                    "id": "general",
                    "name": "General"
                  }
                }
            """.trimIndent()
        )

        assertEquals(UnityAndroidNotificationManager.OPERATION_SHOW_NOTIFICATION, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("title is required"))
    }

    @Test
    fun scheduleNotification_notifiesInvalidArgumentFailureWhenTriggerIsMissing() {
        val listener = CapturingListener()
        UnityAndroidNotificationManager.setNotificationOperationListener(listener)

        UnityAndroidNotificationManager.scheduleNotification(
            context = RecordingContext(),
            scheduleJson = """
                {
                  "notification": {
                    "id": 5001,
                    "title": "Reminder",
                    "message": "Scheduled reminder",
                    "channel": {
                      "id": "reminders",
                      "name": "Reminders"
                    }
                  },
                  "schedule": {
                    "exact": true
                  }
                }
            """.trimIndent()
        )

        assertEquals(UnityAndroidNotificationManager.OPERATION_SCHEDULE_NOTIFICATION, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("schedule.triggerAtMillis"))
    }

    @Test
    fun createChannel_withoutListener_doesNotThrow() {
        UnityAndroidNotificationManager.clearNotificationOperationListener()

        UnityAndroidNotificationManager.createChannel(
            context = RecordingContext(),
            channelJson = """
                {
                  "name": "Updates"
                }
            """.trimIndent()
        )
    }

    private class CapturingListener : UnityAndroidNotificationManager.NotificationOperationListener {
        var operation: String? = null
        var isSuccessful: Boolean? = null
        var errorMessage: String? = null

        override fun onNotificationOperation(operation: String, isSuccessful: Boolean, errorMessage: String?) {
            this.operation = operation
            this.isSuccessful = isSuccessful
            this.errorMessage = errorMessage
        }
    }

    private open class RecordingContext(
    ) : ContextWrapper(null) {

        override fun getPackageName(): String {
            return "com.example.notification.test"
        }

        override fun startActivity(intent: Intent) {
            // no-op for local JVM tests
        }
    }
}


