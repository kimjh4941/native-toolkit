package android.unity.notification

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UnityNotificationJsonParserTest {

    @Test
    fun parseChannel_readsOptionalFields() {
        val channel = UnityNotificationJsonParser.parseChannel(
            """
            {
              "id": "updates",
              "name": "Updates",
              "importance": 4,
              "description": "General updates",
              "showBadge": false,
              "enableLights": false,
              "enableVibration": true,
              "vibrationPattern": [100, 200, 300],
              "groupId": "sync",
              "groupName": "Sync"
            }
            """.trimIndent()
        )

        assertEquals("updates", channel.id)
        assertEquals("Updates", channel.name)
        assertEquals(4, channel.importance)
        assertEquals("General updates", channel.description)
        assertFalse(channel.showBadge)
        assertFalse(channel.enableLights)
        assertEquals(listOf(100L, 200L, 300L), channel.vibrationPattern)
        assertEquals("sync", channel.groupId)
        assertEquals("Sync", channel.groupName)
    }

    @Test
    fun parseNotification_readsBigTextStyleAndProgress() {
        val notification = UnityNotificationJsonParser.parseNotification(
            json =
                """
                {
                  "id": 1001,
                  "title": "Download",
                  "message": "Downloading...",
                  "launchAppOnTap": false,
                  "channel": {
                    "id": "downloads",
                    "name": "Downloads"
                  },
                  "progress": {
                    "max": 100,
                    "current": 45,
                    "indeterminate": false
                  },
                  "style": {
                    "type": "bigText",
                    "bigText": "Downloading a larger asset in the background.",
                    "summaryText": "45%",
                    "bigContentTitle": "Background Download"
                  }
                }
                """.trimIndent()
        )

        assertEquals(1001, notification.id)
        assertEquals("Download", notification.title)
        assertEquals("downloads", notification.channel.id)
        assertNotNull(notification.progress)
        assertEquals(100, notification.progress?.max)
        assertEquals(45, notification.progress?.current)
        assertEquals(UnityNotificationStyleSpec.TYPE_BIG_TEXT, notification.style.type)
        assertEquals("45%", notification.style.summaryText)
        assertFalse(notification.launchAppOnTap)
    }

    @Test
    fun parseNotification_defaultsMessagingTimestampWhenMissing() {
        val notification = UnityNotificationJsonParser.parseNotification(
            json =
                """
                {
                  "id": 2001,
                  "title": "Chat",
                  "message": "New message",
                  "channel": {
                    "id": "chat",
                    "name": "Chat"
                  },
                  "style": {
                    "type": "messaging",
                    "userDisplayName": "Me",
                    "messages": [
                      {
                        "text": "Hello"
                      }
                    ]
                  }
                }
                """.trimIndent(),
            nowProvider = { 123456789L }
        )

        assertEquals(UnityNotificationStyleSpec.TYPE_MESSAGING, notification.style.type)
        assertEquals("Me", notification.style.userDisplayName)
        assertEquals(1, notification.style.messages.size)
        assertEquals(123456789L, notification.style.messages.first().timestampMillis)
    }

    @Test
    fun parseScheduledNotification_readsNestedSchedule() {
        val scheduled = UnityNotificationJsonParser.parseScheduledNotification(
            """
            {
              "notification": {
                "id": 3001,
                "title": "Reminder",
                "message": "Scheduled reminder",
                "channel": {
                  "id": "reminders",
                  "name": "Reminders"
                }
              },
              "schedule": {
                "triggerAtMillis": 1893456000000,
                "exact": true,
                "allowWhileIdle": false,
                "persistAcrossBoot": true,
                "alarmType": 1
              }
            }
            """.trimIndent()
        )

        assertEquals(3001, scheduled.notification.id)
        assertEquals(1893456000000L, scheduled.triggerAtMillis)
        assertTrue(scheduled.exact)
        assertFalse(scheduled.allowWhileIdle)
        assertTrue(scheduled.persistAcrossBoot)
        assertEquals(1, scheduled.alarmType)
    }
}

