package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * Debug builds only: the Kotlin side of the probe operation and event of the C ABI tests
 * (src/main/cpp/src/Debug/Probe.h). It behaves as a feature bridge does: the insertion and the
 * start in one main-thread message, a completion as a Manager's onResult would arrive, events
 * fanned out to every registration of the kind.
 */
internal object ProbeBridge {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.ProbeBridge"

    const val KIND_OPERATION = 900
    const val KIND_EVENT = 901

    /** Accepts a probe operation: inserts it on the main thread; it waits for [finish]. */
    @JvmStatic
    fun start(id: Long): Boolean {
        Log.d(TAG, "[start] id: $id")
        return MainPoster.post { Ledger.insertIfActive(id, KIND_OPERATION) }
    }

    /** Completes a probe operation on the main thread with [value], as a result arriving would. */
    @JvmStatic
    fun finish(id: Long, value: Long): Boolean {
        Log.d(TAG, "[finish] id: $id, value: $value")
        return MainPoster.post {
            if (Ledger.contains(id)) {
                Ledger.remove(id)
                nativeComplete(id, value)
            }
        }
    }

    /** Accepts a probe event registration. */
    @JvmStatic
    fun addListener(id: Long): Boolean {
        Log.d(TAG, "[addListener] id: $id")
        return MainPoster.post { Ledger.insertIfActive(id, KIND_EVENT) }
    }

    /** Delivers [value] to every probe event registration on the main thread. */
    @JvmStatic
    fun emit(value: Long): Boolean {
        Log.d(TAG, "[emit] value: $value")
        return MainPoster.post {
            for (id in Ledger.idsOf(KIND_EVENT)) nativeDeliver(id, value)
        }
    }

    /** The ledger's size, for the tests. Main thread only. */
    @JvmStatic
    fun ledgerSize(): Int {
        Log.d(TAG, "[ledgerSize]")
        return Ledger.size()
    }

    @JvmStatic
    external fun nativeComplete(id: Long, value: Long)

    @JvmStatic
    external fun nativeDeliver(id: Long, value: Long)
}
