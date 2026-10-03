package com.jonghyunkim.android.nativetoolkit.example.infra

import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until

/**
 * Operates the system Sharesheet (`com.android.intentresolver` on API 34 and later).
 *
 * The target order depends on usage history, so targets are searched by scrolling. Nothing about
 * other targets is logged (section 2).
 */
class Sharesheet(private val device: UiDevice) {

    fun waitOpen() {
        if (!device.wait(Until.hasObject(By.pkg(RESOLVER)), TIMEOUT_MS)) {
            throw AssertionError("the Sharesheet did not open")
        }
    }

    /** Waits for an object showing [text] in the Sharesheet (preview title, chooser action, target). */
    fun find(text: String): UiObject2 {
        waitOpen()
        // The targets load asynchronously (slowly on the emulator), so wait before scrolling, and
        // scroll back up too: a target that loads after the list was scrolled down appears above.
        device.wait(Until.findObject(By.pkg(RESOLVER).text(text)), LOAD_MS)?.let { return it }
        for (direction in listOf(Direction.DOWN, Direction.UP)) {
            repeat(MAX_SCROLLS) {
                device.findObject(By.pkg(RESOLVER).scrollable(true))?.scroll(direction, 0.8f)
                device.wait(Until.findObject(By.pkg(RESOLVER).text(text)), SHORT_MS)?.let { return it }
            }
        }
        throw AssertionError("<$text> was not shown in the Sharesheet")
    }

    /** Clicks the target, chooser action or shortcut labelled [label]. */
    fun choose(label: String) {
        // The target list can re-layout while it loads: the found object can go stale, or the click
        // can land after the list moved. Retry until the Sharesheet closes.
        repeat(CHOOSE_RETRIES) { attempt ->
            try {
                find(label).click()
                device.waitForIdle()
                if (device.wait(Until.gone(By.pkg(RESOLVER)), CLOSE_MS)) return
            } catch (e: StaleObjectException) {
                if (attempt == CHOOSE_RETRIES - 1) throw e
            }
        }
        throw AssertionError("the Sharesheet stayed open after choosing <$label>")
    }

    /** Closes the Sharesheet without choosing anything. */
    fun dismiss() {
        waitOpen()
        device.pressBack()
        device.wait(Until.gone(By.pkg(RESOLVER)), TIMEOUT_MS)
    }

    companion object {
        const val RESOLVER = "com.android.intentresolver"
        const val SAMPLE_LABEL = "Native Toolkit Example"
        const val SHARE_TARGET_LABEL = "NTK Share Target"
        private const val TIMEOUT_MS = 10_000L
        private const val LOAD_MS = 5_000L
        private const val SHORT_MS = 1_500L
        private const val MAX_SCROLLS = 6
        private const val CHOOSE_RETRIES = 3
        private const val CLOSE_MS = 3_000L
    }
}
