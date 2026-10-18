package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * A saved schedule (Kotlin API design 8.6). Only schedules with `persistAcrossBoot` are saved.
 *
 * @property generation The value written into the Alarm's extras; the receiver removes the entry
 *   only when it still has the same generation.
 * @property lossy Whether `Intent.toUri` dropped something from the command's Intents.
 * @property installId The install the Alarm was set in.
 * @property bootCount The boot the Alarm was set in, or -1 when unknown.
 */
internal data class ScheduledNotificationEntry(
    val command: AndroidNotificationCommand,
    val schedule: NotificationSchedule,
    val generation: Long = 0L,
    val lossy: Boolean = false,
    val installId: String = "",
    val bootCount: Int = -1
)

/**
 * Saves schedules as JSON in `filesDir/ntk/notification_schedules.json` with [AtomicFile]
 * (Kotlin API design 8.6).
 *
 * Writes finish on the calling thread (`finishWrite` syncs before it replaces the file) and throw
 * [IOException] on failure. Entries that cannot be read are skipped, kept as they are when the
 * file is rewritten, and logged. A file of an unknown version is renamed aside and treated as
 * empty. Callers hold [ScheduleLock].
 *
 * @param context Any Context.
 */
internal class JsonNotificationScheduleStore(context: Context) {

    private val appContext = context.applicationContext
    private val directory = File(appContext.filesDir, "ntk")
    private val file = AtomicFile(File(directory, FILE_NAME))

    private class Contents(val entries: MutableList<ScheduledNotificationEntry>, val unreadable: MutableList<JSONObject>)

    /** Returns every readable entry. */
    fun loadAll(): List<ScheduledNotificationEntry> {
        Log.d(TAG, "[loadAll]")
        return ScheduleLock.withLock { read().entries.toList() }
    }

    /**
     * Returns the entry of [id] and [tag], or `null`.
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun get(id: Int, tag: String?): ScheduledNotificationEntry? {
        Log.d(TAG, "[get] id: $id, tag: $tag")
        val key = NotificationSchedulerSupport.scheduleKey(id, tag)
        return ScheduleLock.withLock { read().entries.firstOrNull { it.key() == key } }
    }

    /**
     * Saves [entry], replacing the entry with the same key.
     *
     * @param entry The entry.
     * @throws IOException When the file cannot be written.
     */
    fun put(entry: ScheduledNotificationEntry) {
        Log.d(TAG, "[put] key: ${entry.key()}, generation: ${entry.generation}, lossy: ${entry.lossy}")
        ScheduleLock.withLock {
            val contents = read()
            contents.entries.removeAll { it.key() == entry.key() }
            contents.entries += entry
            write(contents)
        }
    }

    /**
     * Removes the entry of [id] and [tag], if any.
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     * @throws IOException When the file cannot be written.
     */
    fun remove(id: Int, tag: String?) {
        Log.d(TAG, "[remove] id: $id, tag: $tag")
        val key = NotificationSchedulerSupport.scheduleKey(id, tag)
        ScheduleLock.withLock {
            val contents = read()
            if (contents.entries.removeAll { it.key() == key }) write(contents)
        }
    }

    /**
     * Removes the entry of [id] and [tag] only when it still has [generation].
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     * @param generation The generation read from the Alarm.
     * @return Whether an entry was removed.
     * @throws IOException When the file cannot be written.
     */
    fun removeIfGeneration(id: Int, tag: String?, generation: Long): Boolean {
        Log.d(TAG, "[removeIfGeneration] id: $id, tag: $tag, generation: $generation")
        val key = NotificationSchedulerSupport.scheduleKey(id, tag)
        return ScheduleLock.withLock {
            val contents = read()
            val removed = contents.entries.removeAll { it.key() == key && it.generation == generation }
            if (removed) write(contents)
            removed
        }
    }

    /**
     * Removes every entry, unreadable ones included (as `SharedPreferences.clear()` did).
     *
     * @throws IOException When the file cannot be written.
     */
    fun clear() {
        Log.d(TAG, "[clear]")
        ScheduleLock.withLock { write(Contents(mutableListOf(), mutableListOf())) }
    }

    private fun ScheduledNotificationEntry.key(): String =
        NotificationSchedulerSupport.scheduleKey(command.content.id, command.content.tag)

    private fun read(): Contents {
        if (!file.baseFile.exists()) return Contents(mutableListOf(), mutableListOf())
        val root = try {
            JSONObject(String(file.readFully(), Charsets.UTF_8))
        } catch (e: Exception) {
            Log.e(TAG, "[read] the schedule file is not readable JSON; moving it aside", e)
            moveAside("corrupt")
            return Contents(mutableListOf(), mutableListOf())
        }
        val version = root.optInt("v", NotificationJsonCodec.VERSION)
        if (version != NotificationJsonCodec.VERSION) {
            Log.w(TAG, "[read] unknown schedule file version $version; keeping it aside")
            moveAside("v$version")
            return Contents(mutableListOf(), mutableListOf())
        }
        val entries = mutableListOf<ScheduledNotificationEntry>()
        val unreadable = mutableListOf<JSONObject>()
        val array = root.optJSONArray("entries") ?: JSONArray()
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            try {
                entries += decodeEntry(item)
            } catch (e: Exception) {
                Log.e(TAG, "[read] skipping an unreadable entry", e)
                unreadable += item
            }
        }
        return Contents(entries, unreadable)
    }

    private fun write(contents: Contents) {
        val array = JSONArray()
        contents.entries.forEach { array.put(encodeEntry(it)) }
        contents.unreadable.forEach { array.put(it) }
        val bytes = JSONObject().put("v", NotificationJsonCodec.VERSION).put("entries", array).toString()
            .toByteArray(Charsets.UTF_8)
        ScheduleTestHooks.beforeWrite?.invoke()
        if (!directory.exists() && !directory.mkdirs()) throw IOException("cannot create $directory")
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (e: Exception) {
            file.failWrite(stream)
            throw if (e is IOException) e else IOException(e)
        }
    }

    private fun moveAside(suffix: String) {
        val base = file.baseFile
        val target = File(base.parentFile, base.name.removeSuffix(".json") + ".$suffix.json")
        if (!base.renameTo(target)) Log.e(TAG, "[moveAside] could not rename $base to $target")
    }

    private fun encodeEntry(entry: ScheduledNotificationEntry): JSONObject {
        val slots = StoredBinarySlots()
        return JSONObject()
            .put("id", entry.command.content.id)
            .putOpt("tag", entry.command.content.tag)
            .put("generation", entry.generation)
            .put("lossy", entry.lossy)
            .put("installId", entry.installId)
            .put("bootCount", entry.bootCount)
            .put("schedule", NotificationJsonCodec.encodeSchedule(entry.schedule))
            .put("command", NotificationJsonCodec.encodeCommand(entry.command, slots))
    }

    private fun decodeEntry(item: JSONObject): ScheduledNotificationEntry {
        val command = NotificationJsonCodec.decodeCommand(item.getJSONObject("command"), StoredBinarySlots())
        return ScheduledNotificationEntry(
            command = command,
            schedule = NotificationJsonCodec.decodeSchedule(item.getJSONObject("schedule")),
            generation = item.optLong("generation", 0L),
            lossy = item.optBoolean("lossy", false),
            installId = item.optString("installId", ""),
            bootCount = item.optInt("bootCount", -1)
        )
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.JsonNotificationScheduleStore"

        /** The file name under `filesDir/ntk`. */
        const val FILE_NAME: String = "notification_schedules.json"

        /**
         * Builds an entry for [command] and [schedule]: encodes it once to learn whether `toUri`
         * drops anything, and stamps the install and the boot.
         *
         * @param context Any Context.
         * @param command The command.
         * @param schedule The schedule.
         * @param generation The generation of the Alarm.
         */
        fun newEntry(
            context: Context,
            command: AndroidNotificationCommand,
            schedule: NotificationSchedule,
            generation: Long
        ): ScheduledNotificationEntry {
            Log.d(TAG, "[newEntry] id: ${command.content.id}, tag: ${command.content.tag}, generation: $generation")
            val slots = StoredBinarySlots()
            try {
                NotificationJsonCodec.encodeCommand(command, slots)
            } catch (e: JSONException) {
                Log.e(TAG, "[newEntry] cannot encode the command", e)
            }
            return ScheduledNotificationEntry(
                command = command,
                schedule = schedule,
                generation = generation,
                lossy = slots.lossy,
                installId = ScheduleIdentity.installId(context),
                bootCount = ScheduleIdentity.bootCount(context)
            )
        }
    }
}
