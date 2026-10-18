package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryExecutors
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/**
 * What discarding the 1.x schedules needs from Android. Tests replace it.
 */
internal interface LegacyScheduleEnvironment {
    /** Whether the marker file of a finished discard exists. */
    fun isMarked(): Boolean

    /** The schedule key of each saved 1.x entry; `null` for an entry that is not readable JSON. */
    fun legacyKeys(): List<String?>

    /** Cancels the 1.x Alarm of [id] and [tag], if there is one. Throws when it cannot. */
    fun cancelAlarm(id: Int, tag: String?)

    /** Deletes the 1.x preferences. */
    fun deletePreferences(): Boolean

    /** Writes the marker file. */
    fun mark(): Boolean
}

/**
 * The states of discarding the 1.x schedules (Kotlin API design 8.6): not started (or the last try
 * failed), running (another thread is at it), done (the marker file exists).
 */
internal class LegacyScheduleDiscard {

    private val state = AtomicInteger(NOT_STARTED)

    /** Whether the discard is done in this process. */
    fun isDone(): Boolean {
        Log.d(TAG, "[isDone]")
        return state.get() == DONE
    }

    /**
     * Discards the 1.x schedules unless another thread is at it or it is done. A failed try goes
     * back to not started.
     *
     * @param env The environment.
     * @return Whether the discard is done.
     */
    fun runOnce(env: LegacyScheduleEnvironment): Boolean {
        Log.d(TAG, "[runOnce] env: $env")
        if (!state.compareAndSet(NOT_STARTED, RUNNING)) return state.get() == DONE
        var done = false
        try {
            done = discard(env)
        } catch (e: Exception) {
            Log.e(TAG, "[runOnce] the 1.x schedules could not be discarded", e)
        } finally {
            state.set(if (done) DONE else NOT_STARTED)
        }
        return done
    }

    /** Goes back to not started. For tests. */
    fun reset() {
        Log.d(TAG, "[reset]")
        state.set(NOT_STARTED)
    }

    private fun discard(env: LegacyScheduleEnvironment): Boolean {
        Log.d(TAG, "[discard] env: $env")
        if (env.isMarked()) return true
        var failed = false
        env.legacyKeys().forEach { key ->
            // An entry that cannot be read or parsed is the same on every try, so it is skipped
            // without counting as a failure.
            val parsed = key?.let(::parseLegacyKey)
            if (parsed == null) {
                Log.w(TAG, "[discard] skipping an entry whose key cannot be parsed: $key")
                return@forEach
            }
            try {
                env.cancelAlarm(parsed.first, parsed.second)
            } catch (e: Exception) {
                Log.e(TAG, "[discard] could not cancel the 1.x Alarm; key: $key", e)
                failed = true
            }
        }
        if (failed) return false
        if (!env.deletePreferences()) {
            Log.w(TAG, "[discard] could not delete the 1.x preferences")
            return false
        }
        if (!env.mark()) {
            Log.w(TAG, "[discard] could not write the marker file")
            return false
        }
        return true
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.LegacyScheduleDiscard"
        private const val NOT_STARTED = 0
        private const val RUNNING = 1
        private const val DONE = 2
        private const val UNTAGGED = "untagged"

        /**
         * Splits a 1.x schedule key at its last `::`. Returns `null` when the part after it is not
         * an integer. `untagged` reads as no tag.
         *
         * @param key The key, `<tag or untagged>::<id>`.
         */
        fun parseLegacyKey(key: String): Pair<Int, String?>? {
            Log.d(TAG, "[parseLegacyKey] key: $key")
            val index = key.lastIndexOf("::")
            if (index < 0) return null
            val id = key.substring(index + 2).toIntOrNull() ?: return null
            val tag = key.substring(0, index).takeIf { it != UNTAGGED }
            return id to tag
        }
    }
}

/**
 * Discards the schedules saved by 1.x and cancels their Alarms once per install (Kotlin API
 * design 8.6, KA-9).
 *
 * 1.x Alarms point at a receiver class that no longer exists, so they would never show anything.
 * Only schedules 1.x saved (`persistAcrossBoot`) can be found; the others cannot be listed and
 * are left to fire into nothing (D-11).
 */
internal object LegacyScheduleCleaner {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.LegacyScheduleCleaner"

    // 1.x identifiers (stage 0e result, chapter 4).
    const val LEGACY_PREFERENCES: String = "android.library.notification.scheduler"
    const val LEGACY_KEY_ENTRIES: String = "entries"
    const val LEGACY_KEY_SCHEDULE: String = "android.intent.extra.shortcut.ID"
    const val LEGACY_RECEIVER: String = "android.library.notification.data.repository.ScheduledNotificationReceiver"
    const val LEGACY_ACTION: String = "android.library.notification.action.SHOW_SCHEDULED"
    const val LEGACY_SCHEME: String = "native-toolkit-notification"
    private const val UNTAGGED = "untagged"

    private val discard = LegacyScheduleDiscard()

    /** Replaces the environment in tests. */
    @Volatile
    internal var environmentFactory: (Context) -> LegacyScheduleEnvironment = ::AndroidLegacyScheduleEnvironment

    /**
     * Runs [runOnce] on the library's disk thread.
     *
     * @param context Any Context.
     */
    fun runOnceInBackground(context: Context) {
        Log.d(TAG, "[runOnceInBackground] context: $context")
        if (discard.isDone()) return
        val appContext = context.applicationContext
        LibraryExecutors.io.execute { runOnce(appContext) }
    }

    /**
     * Discards the 1.x schedules unless another thread is at it or it is done.
     *
     * @param context Any Context.
     * @return Whether the discard is done.
     */
    fun runOnce(context: Context): Boolean {
        Log.d(TAG, "[runOnce] context: $context")
        return discard.runOnce(environmentFactory(context.applicationContext))
    }

    /**
     * Returns the marker file. It is per device, so it lives in `noBackupFilesDir`.
     *
     * @param context Any Context.
     */
    fun markerFile(context: Context): File {
        Log.d(TAG, "[markerFile] context: $context")
        return File(File(context.noBackupFilesDir, "ntk"), "legacy_v1_discarded")
    }

    /**
     * Builds the Intent of a 1.x Alarm.
     *
     * @param context Any Context.
     * @param id The notification ID.
     * @param tag The notification tag, or `null`.
     */
    fun legacyIntent(context: Context, id: Int, tag: String?): Intent {
        Log.d(TAG, "[legacyIntent] context: $context, id: $id, tag: $tag")
        val uri = Uri.Builder()
            .scheme(LEGACY_SCHEME)
            .authority(context.packageName)
            .appendPath(tag ?: UNTAGGED)
            .appendPath(id.toString())
            .build()
        return Intent()
            .setComponent(ComponentName(context.packageName, LEGACY_RECEIVER))
            .setAction(LEGACY_ACTION)
            .setPackage(context.packageName)
            .setData(uri)
    }

    /**
     * The request code of a 1.x Alarm.
     *
     * @param id The notification ID.
     * @param tag The notification tag, or `null`.
     */
    fun legacyRequestCode(id: Int, tag: String?): Int {
        Log.d(TAG, "[legacyRequestCode] id: $id, tag: $tag")
        return "${tag ?: UNTAGGED}::$id".hashCode()
    }

    /** Lets tests run the cleaner again. */
    internal fun resetForTest() {
        Log.d(TAG, "[resetForTest]")
        discard.reset()
        environmentFactory = ::AndroidLegacyScheduleEnvironment
    }
}

/**
 * The Android side of [LegacyScheduleDiscard].
 *
 * @param context The application Context.
 */
internal class AndroidLegacyScheduleEnvironment(private val context: Context) : LegacyScheduleEnvironment {

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    override fun isMarked(): Boolean {
        Log.d(TAG, "[isMarked]")
        return LegacyScheduleCleaner.markerFile(context).exists()
    }

    override fun legacyKeys(): List<String?> {
        Log.d(TAG, "[legacyKeys]")
        return context.getSharedPreferences(LegacyScheduleCleaner.LEGACY_PREFERENCES, Context.MODE_PRIVATE)
            .getStringSet(LegacyScheduleCleaner.LEGACY_KEY_ENTRIES, emptySet())
            .orEmpty()
            .map { value ->
                try {
                    JSONObject(value).optString(LegacyScheduleCleaner.LEGACY_KEY_SCHEDULE)
                } catch (e: JSONException) {
                    Log.e(TAG, "[legacyKeys] an entry is not readable JSON", e)
                    null
                }
            }
    }

    override fun cancelAlarm(id: Int, tag: String?) {
        Log.d(TAG, "[cancelAlarm] id: $id, tag: $tag")
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            LegacyScheduleCleaner.legacyRequestCode(id, tag),
            LegacyScheduleCleaner.legacyIntent(context, id, tag),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    override fun deletePreferences(): Boolean {
        Log.d(TAG, "[deletePreferences]")
        return context.deleteSharedPreferences(LegacyScheduleCleaner.LEGACY_PREFERENCES)
    }

    override fun mark(): Boolean {
        Log.d(TAG, "[mark]")
        val marker = LegacyScheduleCleaner.markerFile(context)
        return try {
            marker.parentFile?.mkdirs()
            marker.exists() || marker.createNewFile()
        } catch (e: Exception) {
            Log.e(TAG, "[mark] could not write the marker file", e)
            false
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.AndroidLegacyScheduleEnvironment"
    }
}
