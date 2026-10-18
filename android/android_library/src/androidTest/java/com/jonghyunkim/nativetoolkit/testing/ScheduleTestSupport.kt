package com.jonghyunkim.nativetoolkit.testing

import android.app.Instrumentation
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.ParcelFileDescriptor
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationSchedulerSupport

/**
 * Looks at scheduled notifications from the outside: the Alarms in `dumpsys alarm`, the Alarm's
 * PendingIntent, and the posted notifications.
 */
class ScheduleTestSupport(private val instrumentation: Instrumentation) {

    private val context: Context = instrumentation.targetContext

    /** The requested times of this package's Alarms whose tag ends with [action]. */
    fun alarmTimes(action: String = NotificationSchedulerSupport.ACTION_SHOW_SCHEDULED): List<Long> {
        val lines = shell("dumpsys alarm").lines()
        val times = mutableListOf<Long>()
        val header = Regex("""Alarm\{\S+ type \d+ origWhen (-?\d+) .* (\S+)\}""")
        lines.forEachIndexed { index, line ->
            val match = header.find(line) ?: return@forEachIndexed
            if (match.groupValues[2] != context.packageName) return@forEachIndexed
            val tag = lines.getOrNull(index + 1)?.trim() ?: return@forEachIndexed
            if (tag == "tag=*walarm*:$action" || tag == "tag=*alarm*:$action") {
                times += match.groupValues[1].toLong()
            }
        }
        return times
    }

    /** Whether an Alarm with [action] is set for [triggerAtMillis]. */
    fun isAlarmSet(triggerAtMillis: Long, action: String = NotificationSchedulerSupport.ACTION_SHOW_SCHEDULED): Boolean =
        triggerAtMillis in alarmTimes(action)

    /** The Alarm's PendingIntent of [id] and [tag], or `null` when there is none. */
    fun schedulePendingIntent(id: Int, tag: String?): PendingIntent? = PendingIntent.getBroadcast(
        context,
        0,
        NotificationSchedulerSupport.scheduleIntent(context, id, tag),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
    )

    /** Fires the Alarm of [id] and [tag] now, with the extras it was set with. */
    fun fire(id: Int, tag: String?) {
        val pendingIntent = schedulePendingIntent(id, tag) ?: throw AssertionError("no Alarm for $tag::$id")
        pendingIntent.send()
    }

    /** Fires an Alarm intent built by the test. */
    fun fire(intent: Intent) {
        context.sendBroadcast(intent)
    }

    /** Waits until a notification with [id] and [tag] is posted, or not, for at most [timeoutMs]. */
    fun waitPosted(id: Int, tag: String?, posted: Boolean = true, timeoutMs: Long = 10_000): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        val end = System.currentTimeMillis() + timeoutMs
        while (true) {
            val found = manager.activeNotifications.any { it.id == id && it.tag == tag }
            if (found == posted) return true
            if (System.currentTimeMillis() > end) return false
            Thread.sleep(100)
        }
    }

    /** Runs a shell command and returns its output. */
    fun shell(command: String): String {
        val descriptor = instrumentation.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
    }
}
