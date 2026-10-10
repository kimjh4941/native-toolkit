package com.jonghyunkim.nativetoolkit.capi.jni

import android.os.Looper
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * The ledger of the C ABI: which registration ids are live on the Kotlin side, and of what kind
 * (C ABI design part 1, 5.7, AC-6). Only the main thread touches it, through messages of the one
 * main-thread Handler ([MainPoster]) in the order they were posted.
 *
 * C makes each registration ACTIVE before calling Kotlin and keeps the state; this ledger only
 * tells which ids an event goes to and which operations are still waiting.
 */
internal object Ledger {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.Ledger"

    private val entries = LinkedHashMap<Long, Int>()

    /**
     * The insertion of design 5.7: puts [id] in the ledger when its C registration is still
     * ACTIVE. A registration whose cancel came first is left out, and the removal the cancel
     * posted (or queued in C, when it could not be posted) releases it.
     *
     * @return Whether the id was inserted, which is whether the operation should start.
     */
    fun insertIfActive(id: Long, kind: Int): Boolean {
        Log.d(TAG, "[insertIfActive] id: $id, kind: $kind")
        checkMain()
        if (!nativeIsActive(id)) return false
        entries[id] = kind
        return true
    }

    /** Takes [id] out of the ledger. */
    fun remove(id: Long) {
        Log.d(TAG, "[remove] id: $id")
        checkMain()
        entries.remove(id)
    }

    /** Whether [id] is in the ledger. */
    fun contains(id: Long): Boolean {
        Log.d(TAG, "[contains] id: $id")
        checkMain()
        return id in entries
    }

    /** The ids of [kind], in the order they were inserted, copied so that a delivery may change the ledger. */
    fun idsOf(kind: Int): List<Long> {
        Log.d(TAG, "[idsOf] kind: $kind")
        checkMain()
        return entries.filterValues { it == kind }.keys.toList()
    }

    /** The number of entries, for the tests. */
    fun size(): Int {
        Log.d(TAG, "[size]")
        checkMain()
        return entries.size
    }

    /**
     * Posts the removal of design 5.7 (the 外す row) for a registration C has moved to
     * CANCEL_REQUESTED. Called from C on any thread; never waits.
     *
     * @return Whether it was posted. When it was not (the main looper has ended, or posting
     *   failed), C queues the removal and runs it on the main thread later, with [drop].
     */
    @JvmStatic
    fun postRemove(id: Long): Boolean {
        Log.d(TAG, "[postRemove] id: $id")
        return MainPoster.post {
            entries.remove(id)
            nativeRemove(id)
        }
    }

    /** Takes [id] out of the ledger for a removal C runs itself (one that could not be posted). Main thread only. */
    @JvmStatic
    fun drop(id: Long) {
        Log.d(TAG, "[drop] id: $id")
        checkMain()
        entries.remove(id)
    }

    private fun checkMain() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "The ledger is used off the main thread" }
    }

    /** Whether the C registration is ACTIVE. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeIsActive(id: Long): Boolean

    /** The removal in C: the canceled completion if any, then the release. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeRemove(id: Long)
}
