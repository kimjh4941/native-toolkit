package com.jonghyunkim.android.nativetoolkit.example.infra

import android.app.Instrumentation
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Collects the sample's Toast texts from accessibility events (section 3.1, U-4).
 *
 * Call [start] before the action that shows the Toast, and [stop] in tearDown.
 */
class Toasts(private val instrumentation: Instrumentation) {

    private val texts = CopyOnWriteArrayList<String>()
    private val packageName = instrumentation.targetContext.packageName

    fun start() {
        texts.clear()
        instrumentation.uiAutomation.setOnAccessibilityEventListener { event ->
            if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED &&
                event.className?.toString() == "android.widget.Toast" &&
                event.packageName?.toString() == packageName
            ) {
                texts.add(event.text.joinToString(" "))
            }
        }
    }

    fun stop() {
        instrumentation.uiAutomation.setOnAccessibilityEventListener(null)
    }

    /** Waits until a Toast containing [expected] has been shown since [start]. */
    fun waitFor(expected: String, timeoutMs: Long = 10_000L) {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            if (texts.any { it.contains(expected) }) return
            Thread.sleep(100)
        }
        throw AssertionError("no Toast containing <$expected> within $timeoutMs ms; seen=$texts")
    }
}
