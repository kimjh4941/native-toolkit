package com.jonghyunkim.nativetoolkit.capitest

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import androidx.test.platform.app.InstrumentationRegistry

/**
 * Reads what the system shows, for the notification cases (through TestSupport.h): a field of an
 * active notification or of a channel, as a string, or null when there is none. Also grants the
 * permissions a case needs (granting does not stop the process; revoking would).
 */
object NotificationInspector {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val manager: NotificationManager
        get() = context.getSystemService(NotificationManager::class.java)

    @JvmStatic
    fun grantNotifications() {
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .grantRuntimePermission(context.packageName, android.Manifest.permission.POST_NOTIFICATIONS)
    }

    @JvmStatic
    fun allowExactAlarms() {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.executeShellCommand("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow").close()
        // The change reaches AlarmManager shortly after.
        waitUntil { context.getSystemService(android.app.AlarmManager::class.java).canScheduleExactAlarms() }
    }

    /** Waits until notification [id] (and [tag]) is shown, or [timeoutMs] passes. */
    @JvmStatic
    fun waitShown(id: Int, tag: String?, timeoutMs: Long): Boolean = waitUntil(timeoutMs) { find(id, tag) != null }

    @JvmStatic
    fun waitGone(id: Int, tag: String?, timeoutMs: Long): Boolean = waitUntil(timeoutMs) { find(id, tag) == null }

    /** The resource id of [name] of [type] in the test app, as a string, for comparisons. */
    @JvmStatic
    fun resourceId(name: String, type: String): String =
        context.resources.getIdentifier(name, type, context.packageName).toString()

    /**
     * Sends a PendingIntent of notification [id] as the system would on a tap: [which] is
     * "content", "delete" or "action:<index>". A broadcast is sent ordered, so this returns once
     * the library's receiver has handled it (and the event is in its EventHub); false when the
     * notification or the intent is not there, or after the timeout.
     */
    @JvmStatic
    fun fire(id: Int, tag: String?, which: String): Boolean {
        val notification = find(id, tag)?.notification ?: return false
        val intent = when {
            which == "content" -> notification.contentIntent
            which == "delete" -> notification.deleteIntent
            which.startsWith("action:") -> notification.actions?.getOrNull(which.substringAfter(':').toInt())?.actionIntent
            else -> error("unknown intent $which")
        } ?: return false
        val done = CountDownLatch(1)
        intent.send(context, 0, null, { _, _, _, _, _ -> done.countDown() }, null)
        return done.await(10, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun field(id: Int, tag: String?, name: String): String? {
        val notification = find(id, tag)?.notification ?: return null
        val extras = notification.extras
        return when (name) {
            "title" -> extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            "text" -> extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            "subText" -> extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
            "channel" -> notification.channelId
            "category" -> notification.category
            "number" -> notification.number.toString()
            "color" -> Integer.toHexString(notification.color)
            "group" -> notification.group
            "sortKey" -> notification.sortKey
            "visibility" -> notification.visibility.toString()
            "ongoing" -> (notification.flags and Notification.FLAG_ONGOING_EVENT != 0).toString()
            "autoCancel" -> (notification.flags and Notification.FLAG_AUTO_CANCEL != 0).toString()
            "onlyAlertOnce" -> (notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0).toString()
            "contentIntent" -> (notification.contentIntent != null).toString()
            "deleteIntent" -> (notification.deleteIntent != null).toString()
            "fullScreenIntent" -> (notification.fullScreenIntent != null).toString()
            "smallIcon" -> notification.smallIcon?.resId?.toString()
            "largeIcon" -> (notification.getLargeIcon() != null).toString()
            "template" -> extras.getString(Notification.EXTRA_TEMPLATE)?.substringAfterLast('$')
            "bigText" -> extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            "lines" -> extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.joinToString("|")
            "messages" -> extras.getParcelableArray(Notification.EXTRA_MESSAGES, android.os.Parcelable::class.java)?.size?.toString()
            "picture" -> (extras.containsKey(Notification.EXTRA_PICTURE) || extras.containsKey(Notification.EXTRA_PICTURE_ICON)).toString()
            "customView" -> (notification.contentView != null || notification.bigContentView != null).toString()
            "actions" -> notification.actions?.joinToString("|") { it.title.toString() } ?: ""
            "actionIcon" -> notification.actions?.firstOrNull()?.getIcon()?.resId?.toString()
            "progress" -> "${extras.getInt(Notification.EXTRA_PROGRESS)}/${extras.getInt(Notification.EXTRA_PROGRESS_MAX)}"
            "timeoutAfter" -> notification.timeoutAfter.toString()
            "usesChronometer" -> extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER).toString()
            "showWhen" -> extras.getBoolean(Notification.EXTRA_SHOW_WHEN).toString()
            "ticker" -> notification.tickerText?.toString()
            "localOnly" -> (notification.flags and Notification.FLAG_LOCAL_ONLY != 0).toString()
            "groupSummary" -> (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0).toString()
            "groupAlertBehavior" -> notification.groupAlertBehavior.toString()
            else -> error("unknown field $name")
        }
    }

    @JvmStatic
    fun channelField(channelId: String, name: String): String? {
        val channel = manager.getNotificationChannel(channelId) ?: return null
        return when (name) {
            "name" -> channel.name.toString()
            "importance" -> channel.importance.toString()
            "description" -> channel.description
            "lockscreenVisibility" -> channel.lockscreenVisibility.toString()
            "showBadge" -> channel.canShowBadge().toString()
            "vibration" -> channel.vibrationPattern?.joinToString(",")
            "group" -> channel.group
            "lights" -> channel.shouldShowLights().toString()
            "lightColor" -> Integer.toHexString(channel.lightColor)
            "vibrates" -> channel.shouldVibrate().toString()
            "sound" -> channel.sound?.toString()
            else -> error("unknown field $name")
        }
    }

    private fun find(id: Int, tag: String?) =
        manager.activeNotifications.firstOrNull { it.id == id && it.tag == tag }

    private fun waitUntil(timeoutMs: Long = 5_000, condition: () -> Boolean): Boolean {
        val end = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < end) {
            if (condition()) return true
            Thread.sleep(50)
        }
        return condition()
    }
}
