package com.jonghyunkim.nativetoolkit.capitest

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** The main thread for the GoogleTest cases (TestSupport.h): run on it, hold it, wait for it. */
object MainControl {

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var gate: CountDownLatch? = null

    /** Runs a native task on the main thread and waits for it. */
    @JvmStatic
    fun runOnMain(task: Long) {
        val done = CountDownLatch(1)
        main.post {
            nativeRun(task)
            done.countDown()
        }
        check(done.await(10, TimeUnit.SECONDS)) { "the main thread did not run the task" }
    }

    /** Waits until the main thread has run every message posted before. */
    @JvmStatic
    fun drain() {
        val done = CountDownLatch(1)
        main.post { done.countDown() }
        check(done.await(10, TimeUnit.SECONDS)) { "the main thread did not drain" }
    }

    /** Holds the main thread until [unhold]. Returns once it is held. */
    @JvmStatic
    fun hold() {
        val held = CountDownLatch(1)
        val release = CountDownLatch(1)
        gate = release
        main.post {
            held.countDown()
            release.await(30, TimeUnit.SECONDS)
        }
        check(held.await(10, TimeUnit.SECONDS)) { "the main thread was not held" }
    }

    @JvmStatic
    fun unhold() {
        gate?.countDown()
        gate = null
    }

    /** The size of the C ABI's ledger (capi.jni.ProbeBridge.ledgerSize), read on the main thread. */
    @JvmStatic
    fun ledgerSize(): Int {
        var size = -1
        val done = CountDownLatch(1)
        main.post {
            size = Class.forName("com.jonghyunkim.nativetoolkit.capi.jni.ProbeBridge")
                .getMethod("ledgerSize").invoke(null) as Int
            done.countDown()
        }
        check(done.await(10, TimeUnit.SECONDS)) { "the main thread did not answer" }
        return size
    }

    @JvmStatic
    external fun nativeRun(task: Long)
}
