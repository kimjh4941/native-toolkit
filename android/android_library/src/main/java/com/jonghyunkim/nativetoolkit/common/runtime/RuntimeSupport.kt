package com.jonghyunkim.nativetoolkit.common.runtime

import android.util.Log
import androidx.annotation.RestrictTo
import java.security.SecureRandom
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Request IDs that are never reused within a process (Kotlin API design 6.1).
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object RequestIds {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.runtime.RequestIds"

    private val last = AtomicLong(0L)

    /**
     * Returns the next ID. The first ID is 1.
     */
    fun next(): Long {
        val id = last.incrementAndGet()
        Log.d(TAG, "[next] id: $id")
        return id
    }
}

/**
 * A random value chosen once per process.
 *
 * Library URIs carry it so that a URI made by an earlier process never equals one made by this
 * process (Kotlin API design 8.9).
 */
internal object ProcessNonce {

    /** The value for this process. */
    val value: Long by lazy { SecureRandom().nextLong() }
}

/**
 * The single background thread for library disk work.
 */
internal object LibraryExecutors {

    /** Runs disk work in order on one daemon thread. */
    val io: ExecutorService by lazy {
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "ntk-io").apply { isDaemon = true }
        }
    }
}
