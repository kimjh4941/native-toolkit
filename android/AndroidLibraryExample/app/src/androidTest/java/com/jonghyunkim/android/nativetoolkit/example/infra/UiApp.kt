package com.jonghyunkim.android.nativetoolkit.example.infra

import android.content.Context
import android.content.Intent
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until

/**
 * Drives the sample through UiAutomator only, using the test tags exposed as resource IDs.
 *
 * Used by the tests in which an intent from outside reaches the running `MainActivity`
 * (`singleTask`): received shares, the sample chosen in the Sharesheet, notification taps.
 * `onNewIntent` makes the Compose rule's ActivityScenario lose its activity, so those tests do
 * not use the Compose rule at all.
 */
class UiApp(private val context: Context, private val device: UiDevice) {

    private val packageName = context.packageName

    /** Starts the sample in a fresh task and waits for the menu. */
    fun launch() {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        if (device.wait(Until.hasObject(By.res("menu.dialog")), TIMEOUT_MS)) return
        // A slow start (seen on the emulator) or a leftover window in front: go home and start once more.
        device.pressHome()
        context.startActivity(intent)
        if (!device.wait(Until.hasObject(By.res("menu.dialog")), TIMEOUT_MS)) {
            throw AssertionError("the sample's menu did not appear; in front: ${device.currentPackageName}")
        }
    }

    /** Opens a screen from the menu. */
    fun open(screen: String) {
        // Right after launch the click can land on a menu that is about to be replaced (seen once on
        // the device), so click again while the menu is still there.
        repeat(OPEN_RETRIES) {
            if (device.hasObject(By.res("menu.$screen"))) click("menu.$screen")
            if (device.wait(Until.hasObject(By.res("$screen.back")), OPEN_MS)) return
        }
        waitFor("$screen.back")
    }

    /** Clicks the node with [tag], scrolling the screen to it first. */
    fun click(tag: String) {
        repeat(STALE_RETRIES) { attempt ->
            try {
                find(tag).click()
                device.waitForIdle()
                return
            } catch (e: StaleObjectException) {
                if (attempt == STALE_RETRIES - 1) throw e
            }
        }
    }

    /** The text of the node with [tag]. */
    fun text(tag: String): String = find(tag).text.orEmpty()

    /** Waits until the node with [tag] exists. */
    fun waitFor(tag: String, timeoutMs: Long = TIMEOUT_MS): UiObject2 =
        device.wait(Until.findObject(By.res(tag)), timeoutMs) ?: throw AssertionError("<$tag> did not appear within $timeoutMs ms")

    /** Waits until the node with [tag] shows exactly [expected]. */
    fun waitForText(tag: String, expected: String, timeoutMs: Long = TIMEOUT_MS) {
        val end = System.currentTimeMillis() + timeoutMs
        var last: String? = null
        while (System.currentTimeMillis() < end) {
            last = device.findObject(By.res(tag))?.text
            if (last == expected) return
            Thread.sleep(200)
        }
        throw AssertionError("$tag did not show <$expected> within $timeoutMs ms; was <$last>")
    }

    /** Waits until the status text of [screen] contains [expected]. */
    fun waitForStatus(screen: String, expected: String, timeoutMs: Long = TIMEOUT_MS) {
        val end = System.currentTimeMillis() + timeoutMs
        var last: String? = null
        while (System.currentTimeMillis() < end) {
            last = device.findObject(By.res("$screen.status"))?.text
            if (last?.contains(expected) == true) return
            Thread.sleep(200)
        }
        throw AssertionError("status of $screen did not contain <$expected> within $timeoutMs ms; was <$last>")
    }

    /** The status text of [screen]. */
    fun status(screen: String): String = device.findObject(By.res("$screen.status"))?.text.orEmpty()

    /** Whether a node with [tag] is on screen. */
    fun exists(tag: String): Boolean = device.hasObject(By.res(tag))

    /** Presses Back until the sample is no longer in front (Back on the menu finishes the activity). */
    fun finish() {
        repeat(MAX_BACKS) {
            if (!device.hasObject(By.pkg(packageName).depth(0))) return
            device.pressBack()
            device.wait(Until.gone(By.pkg(packageName).depth(0)), 1_000)
        }
    }

    private fun find(tag: String): UiObject2 {
        device.findObject(By.res(tag))?.let { return it }
        val scrollable = device.findObject(By.pkg(packageName).scrollable(true))
            ?: throw AssertionError("<$tag> is not on screen and there is nothing to scroll")
        repeat(2) {
            scrollable.scrollUntil(Direction.DOWN, Until.findObject(By.res(tag)))?.let { return it }
            scrollable.scrollUntil(Direction.UP, Until.findObject(By.res(tag)))?.let { return it }
        }
        throw AssertionError("<$tag> was not found")
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val OPEN_MS = 4_000L
        const val OPEN_RETRIES = 3
        const val MAX_BACKS = 5
        const val STALE_RETRIES = 3
    }
}
