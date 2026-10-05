package com.jonghyunkim.nativetoolkit.capitest

import android.content.Context
import android.content.ContextWrapper
import android.os.Process
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** The values of ntk_android_error (Android.h). */
object AndroidError {
    const val NONE = 0
    const val INVALID_PARAMETER = 1
    const val CLASS_NOT_FOUND = 2
    const val JNI_FAILURE = 3
    const val IN_PROGRESS = 4
}

/** How long a call that must not wait may take, with room for a slow device. */
const val NO_WAIT_MS = 3_000L

val appContext: Context
    get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext

/**
 * A Context whose application context is handed out only once [release] is called: LibraryRuntime
 * asks for it in the middle of its initialization, so the Kotlin side stays in progress until then.
 */
class LatchedContext(base: Context) : ContextWrapper(base) {
    private val entered = CountDownLatch(1)
    private val released = CountDownLatch(1)

    override fun getApplicationContext(): Context {
        entered.countDown()
        released.await(30, TimeUnit.SECONDS)
        return baseContext.applicationContext
    }

    /** Waits until the Kotlin side has started and is held. */
    fun awaitHeld(): Boolean = entered.await(10, TimeUnit.SECONDS)

    fun release() = released.countDown()
}

/** A Context whose application context is not an Application, so the Kotlin side fails and undoes its work. */
class BrokenContext(base: Context) : ContextWrapper(base) {
    override fun getApplicationContext(): Context = this
}

/** Polls [condition] until it holds or [timeoutMs] passes. */
fun waitUntil(timeoutMs: Long = 5_000, condition: () -> Boolean): Boolean {
    val end = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
    while (System.nanoTime() < end) {
        if (condition()) return true
        Thread.sleep(20)
    }
    return condition()
}

/** How many times libntk.so's JNI_OnLoad has run in this process, from its logcat lines. */
fun jniOnLoadRuns(): Int {
    val process = ProcessBuilder("logcat", "-d", "--pid", Process.myPid().toString(), "-s", "ntk:D")
        .redirectErrorStream(true).start()
    val lines = process.inputStream.bufferedReader().readLines()
    process.waitFor()
    return lines.count { "[JNI_OnLoad] vm:" in it }
}

/** Runs [block] and returns its result with how long it took. */
fun <T> timed(block: () -> T): Pair<T, Long> {
    val start = System.nanoTime()
    val result = block()
    return result to TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
}
