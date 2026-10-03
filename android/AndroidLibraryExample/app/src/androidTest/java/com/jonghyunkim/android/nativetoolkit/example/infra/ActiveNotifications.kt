package com.jonghyunkim.android.nativetoolkit.example.infra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Parcelable
import android.os.SystemClock
import android.service.notification.StatusBarNotification

/**
 * Reads the sample's posted notifications from inside the app process (section 3.2).
 *
 * Notifications are looked up by ID only. The system may add its own grouping summary
 * (`ranker_group` on API 35, an aggregate group on API 36); those use other IDs and are ignored.
 */
class ActiveNotifications(private val context: Context) {

    private val manager = context.getSystemService(NotificationManager::class.java)

    /** The sample's notification with [id], or null. */
    fun find(id: Int): StatusBarNotification? =
        manager.activeNotifications.firstOrNull { it.id == id && it.tag == null && it.packageName == context.packageName }

    /** Waits until notification [id] is posted and satisfies [condition], and returns it. */
    fun waitFor(
        id: Int,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
        condition: (StatusBarNotification) -> Boolean = { true }
    ): StatusBarNotification {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        var last: StatusBarNotification? = null
        while (SystemClock.elapsedRealtime() < end) {
            last = find(id)
            if (last != null && condition(last)) return last
            Thread.sleep(POLL_MS)
        }
        throw AssertionError("notification $id did not appear as expected within $timeoutMs ms; last=${last?.describe()}")
    }

    /** Waits until notification [id] is gone. */
    fun waitGone(id: Int, timeoutMs: Long = DEFAULT_TIMEOUT_MS) {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            if (find(id) == null) return
            Thread.sleep(POLL_MS)
        }
        throw AssertionError("notification $id was still posted after $timeoutMs ms: ${find(id)?.describe()}")
    }

    /** Asserts that notification [id] stays absent for [durationMs]. */
    fun assertAbsentFor(id: Int, durationMs: Long) {
        val end = SystemClock.elapsedRealtime() + durationMs
        while (SystemClock.elapsedRealtime() < end) {
            find(id)?.let { throw AssertionError("notification $id appeared unexpectedly: ${it.describe()}") }
            Thread.sleep(POLL_MS)
        }
    }

    /** Asserts that notification [id] stays posted for [durationMs]. */
    fun assertPresentFor(id: Int, durationMs: Long) {
        val end = SystemClock.elapsedRealtime() + durationMs
        while (SystemClock.elapsedRealtime() < end) {
            if (find(id) == null) throw AssertionError("notification $id disappeared unexpectedly")
            Thread.sleep(POLL_MS)
        }
    }

    /** IDs of all the sample's posted notifications that are not system grouping summaries. */
    fun sampleIds(): List<Int> =
        manager.activeNotifications.filter { it.packageName == context.packageName && it.tag == null }.map { it.id }

    /** The channel a notification was posted to. */
    fun channel(id: String): NotificationChannel? = manager.getNotificationChannel(id)

    companion object {
        const val DEFAULT_TIMEOUT_MS = 10_000L

        /** Foreground service notifications that are not shown immediately are deferred by up to 10 s. */
        const val FOREGROUND_SERVICE_TIMEOUT_MS = 15_000L

        private const val POLL_MS = 100L
    }
}

private val StatusBarNotification.extras get() = notification.extras

val StatusBarNotification.title: String? get() = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
val StatusBarNotification.text: String? get() = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
val StatusBarNotification.subText: String? get() = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
val StatusBarNotification.bigTitle: String? get() = extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()
val StatusBarNotification.bigText: String? get() = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
val StatusBarNotification.summaryText: String? get() = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
val StatusBarNotification.conversationTitle: String? get() = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
val StatusBarNotification.isGroupConversation: Boolean get() = extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION)
val StatusBarNotification.template: String? get() = extras.getString(Notification.EXTRA_TEMPLATE)
val StatusBarNotification.lines: List<String> get() = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.map { it.toString() }.orEmpty()
val StatusBarNotification.progress: Int get() = extras.getInt(Notification.EXTRA_PROGRESS)
val StatusBarNotification.progressMax: Int get() = extras.getInt(Notification.EXTRA_PROGRESS_MAX)
val StatusBarNotification.isIndeterminate: Boolean get() = extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE)
val StatusBarNotification.hasPicture: Boolean get() = extras.containsKey(Notification.EXTRA_PICTURE) || extras.containsKey(Notification.EXTRA_PICTURE_ICON)
val StatusBarNotification.hasLargeIcon: Boolean get() = notification.getLargeIcon() != null
val StatusBarNotification.isOngoingEvent: Boolean get() = notification.flags and Notification.FLAG_ONGOING_EVENT != 0
val StatusBarNotification.isForegroundService: Boolean get() = notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0
val StatusBarNotification.isGroupSummary: Boolean get() = notification.flags and Notification.FLAG_GROUP_SUMMARY != 0
val StatusBarNotification.actionTitles: List<String> get() = notification.actions?.map { it.title.toString() }.orEmpty()

/** Messages of a MessagingStyle notification as (sender, text) pairs. */
val StatusBarNotification.messages: List<Pair<String?, String?>>
    get() {
        @Suppress("DEPRECATION")
        val bundles: Array<Parcelable> = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        return bundles.filterIsInstance<android.os.Bundle>().map { it.getCharSequence("sender")?.toString() to it.getCharSequence("text")?.toString() }
    }

/** A short description for assertion messages; contains only the sample's own fields. */
fun StatusBarNotification.describe(): String =
    "id=$id title=$title text=$text template=$template progress=$progress/$progressMax flags=${notification.flags}"
