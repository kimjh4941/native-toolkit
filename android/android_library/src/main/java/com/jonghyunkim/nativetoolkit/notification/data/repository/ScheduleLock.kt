package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import android.provider.Settings
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.ProcessNonce
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock

/**
 * The single lock of schedule operations (Kotlin API design 8.6). Hold it only around PendingIntent
 * creation, AlarmManager and file access; never call user code (callbacks, ContentProviders) inside.
 */
internal object ScheduleLock {
    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleLock"
    private val lock = ReentrantLock()

    /**
     * Runs [block] holding the lock. The same thread may enter again.
     *
     * @param block The work.
     */
    fun <T> withLock(block: () -> T): T {
        Log.d(TAG, "[withLock] block: $block")
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }
}

/**
 * Generations, the install ID and the boot count (Kotlin API design 8.6).
 */
internal object ScheduleIdentity {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleIdentity"
    private val counter = AtomicInteger(0)

    @Volatile
    private var installId: String? = null

    /** A new generation: the process nonce in the upper 32 bits and a counter in the lower 32 bits. */
    fun newGeneration(): Long {
        val generation = (ProcessNonce.value shl 32) or (counter.incrementAndGet().toLong() and 0xffffffffL)
        Log.d(TAG, "[newGeneration] generation: $generation")
        return generation
    }

    /**
     * Returns this install's ID, kept in `noBackupFilesDir` so that a reinstall or a device move
     * gives a new one.
     *
     * @param context Any Context.
     */
    fun installId(context: Context): String {
        Log.d(TAG, "[installId] context: $context")
        installId?.let { return it }
        return synchronized(this) {
            installId ?: run {
                val file = File(File(context.noBackupFilesDir, "ntk"), "install_id")
                val existing = runCatching { file.readText().trim() }.getOrNull()?.takeIf { it.isNotEmpty() }
                val id = existing ?: UUID.randomUUID().toString().also { newId ->
                    runCatching {
                        file.parentFile?.mkdirs()
                        file.writeText(newId)
                    }.onFailure { Log.e(TAG, "[installId] could not save the install ID", it) }
                }
                id.also { installId = it }
            }
        }
    }

    /**
     * Returns whether the Alarm of a saved entry is still alive: it was set in this install and in
     * this boot, and the boot count is known.
     *
     * @param entryInstallId The install the entry's Alarm was set in.
     * @param entryBootCount The boot the entry's Alarm was set in, or -1.
     * @param installId This install.
     * @param bootCount This boot, or -1.
     */
    fun isAlarmAlive(entryInstallId: String, entryBootCount: Int, installId: String, bootCount: Int): Boolean {
        Log.d(TAG, "[isAlarmAlive] entryInstallId: $entryInstallId, entryBootCount: $entryBootCount, installId: $installId, bootCount: $bootCount")
        return entryBootCount != -1 && entryBootCount == bootCount && entryInstallId == installId
    }

    /**
     * Returns the current boot count, or -1 when it cannot be read.
     *
     * @param context Any Context.
     */
    fun bootCount(context: Context): Int {
        Log.d(TAG, "[bootCount] context: $context")
        return runCatching { Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1) }
            .getOrDefault(-1)
    }
}

/**
 * Points where tests block or fail the schedule flow (Kotlin API design IT-12, IT-13). Always
 * `null` outside tests.
 */
internal object ScheduleTestHooks {
    /** Runs before a notification is sent; a test may block here. */
    @Volatile
    var beforeSend: ((AndroidNotificationCommand) -> Unit)? = null

    /** Runs before the schedule file is written; a test may throw an IOException here. */
    @Volatile
    var beforeWrite: (() -> Unit)? = null

    /** Runs before an Alarm is set; a test may throw here. */
    @Volatile
    var beforeAlarm: (() -> Unit)? = null

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleTestHooks"

    /** Clears every hook. */
    fun reset() {
        Log.d(TAG, "[reset]")
        beforeSend = null
        beforeWrite = null
        beforeAlarm = null
    }
}
