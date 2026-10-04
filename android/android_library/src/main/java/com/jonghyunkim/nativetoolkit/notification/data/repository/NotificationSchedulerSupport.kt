package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

/**
 * The Alarm intent of scheduled notifications and the schedule key (Kotlin API design 8.6).
 *
 * The receiver class, [ACTION_SHOW_SCHEDULED] and [SCHEME_SCHEDULE] are compatibility identifiers:
 * Alarms set by one version are delivered to the next one. The extras are in [ScheduledAlarmExtras].
 */
internal object NotificationSchedulerSupport {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationSchedulerSupport"

    const val ACTION_SHOW_SCHEDULED: String = "com.jonghyunkim.nativetoolkit.notification.action.SHOW_SCHEDULED"
    const val SCHEME_SCHEDULE: String = "ntk-notification-schedule"

    private const val UNTAGGED = "untagged"

    /**
     * The schedule key. A missing tag is `untagged`, as before, so a schedule tagged `untagged` and
     * an untagged one share a key.
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun scheduleKey(id: Int, tag: String?): String = "${tag ?: UNTAGGED}::$id"

    /**
     * The Alarm intent for [id] and [tag] without extras: enough to find or cancel the Alarm.
     *
     * @param context Any Context.
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun scheduleIntent(context: Context, id: Int, tag: String?): Intent {
        Log.d(TAG, "[scheduleIntent] id: $id, tag: $tag")
        val uri = Uri.Builder()
            .scheme(SCHEME_SCHEDULE)
            .authority(context.packageName)
            .appendPath(tag ?: UNTAGGED)
            .appendPath(id.toString())
            .build()
        return Intent(context, ScheduledNotificationReceiver::class.java)
            .setAction(ACTION_SHOW_SCHEDULED)
            .setData(uri)
    }

    /**
     * Reads the ID and the tag from the data URI of an Alarm intent, or `null`. `untagged` reads as
     * no tag, which has the same schedule key.
     *
     * @param intent The received intent.
     */
    fun idAndTagOf(intent: Intent): Pair<Int, String?>? {
        Log.d(TAG, "[idAndTagOf] intent: $intent")
        val segments = intent.data?.takeIf { it.scheme == SCHEME_SCHEDULE }?.pathSegments ?: return null
        if (segments.size != 2) return null
        val id = segments[1].toIntOrNull() ?: return null
        return id to segments[0].takeIf { it != UNTAGGED }
    }
}
