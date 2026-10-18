package com.jonghyunkim.nativetoolkit.testing

import android.accessibilityservice.AccessibilityService
import android.app.Instrumentation
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until

/**
 * Operates the notification shade. Copied from the sample's UI test infra (NotificationShade.kt).
 *
 * Notifications are found by the sample's own text. BigText notifications show `bigContentTitle`
 * and `bigText` once expanded, so callers pass whichever text is visible. The shade is closed with
 * the dismiss-shade global action, never with Back (Back would leave the sample's screen when the
 * shade is not open).
 */
class NotificationShade(private val instrumentation: Instrumentation, private val device: UiDevice) {

    fun open() {
        device.openNotification()
        device.wait(Until.hasObject(By.res(SYSTEM_UI, "expandableNotificationRow")), TIMEOUT_MS)
    }

    fun close() {
        instrumentation.uiAutomation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
        device.wait(Until.gone(By.res(SYSTEM_UI, "expandableNotificationRow")), TIMEOUT_MS)
    }

    /** Waits for an object showing [text] in the shade (exactly, or as part of a longer text). */
    fun find(text: String, timeoutMs: Long = TIMEOUT_MS): UiObject2 {
        val end = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < end) {
            device.findObject(By.pkg(SYSTEM_UI).text(text))?.let { return it }
            device.findObject(By.pkg(SYSTEM_UI).textContains(text))?.let { return it }
            Thread.sleep(200)
        }
        throw AssertionError("<$text> was not shown in the notification shade within $timeoutMs ms")
    }

    /**
     * Waits until any of [texts] is shown in the shade and returns the one found. A notification
     * shows different text collapsed and expanded (BigText shows `bigContentTitle` when expanded).
     */
    fun findAny(texts: List<String>, timeoutMs: Long = TIMEOUT_MS): String {
        val end = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < end) {
            texts.firstOrNull { device.hasObject(By.pkg(SYSTEM_UI).text(it)) }?.let { return it }
            Thread.sleep(200)
        }
        throw AssertionError("none of $texts was shown in the notification shade within $timeoutMs ms")
    }

    /** The notification row that contains [text]. */
    fun row(text: String, timeoutMs: Long = TIMEOUT_MS): UiObject2 {
        find(text, timeoutMs)
        val rowSelector = By.res(SYSTEM_UI, "expandableNotificationRow")
        return device.findObject(rowSelector.hasDescendant(By.text(text)))
            ?: device.findObject(By.res(SYSTEM_UI, "expandableNotificationRow").hasDescendant(By.textContains(text)))
            ?: throw AssertionError("no notification row contains <$text>")
    }

    /** Expands the notification that contains [text] so its buttons become visible. */
    fun expand(text: String) {
        row(text).findObject(By.res("android", "expand_button"))?.click()
        device.waitForIdle()
    }

    /** Clicks the button labelled [label] in the notification that contains [text], expanding it if needed. */
    fun clickButton(text: String, label: String) {
        val row = row(text)
        var button = row.findObject(By.text(label)) ?: row.findObject(By.desc(label))
        if (button == null) {
            expand(text)
            // Expanding can replace the text the row was found by, so look in the whole shade.
            button = device.wait(Until.findObject(By.pkg(SYSTEM_UI).text(label)), TIMEOUT_MS)
                ?: device.findObject(By.pkg(SYSTEM_UI).desc(label))
        }
        (button ?: throw AssertionError("no button <$label> in the notification with <$text>")).click()
    }

    /**
     * Clicks the action button at [index] (0 = leftmost) in the notification that contains [text].
     * Used for call notifications, whose button labels come from the system (section 3.9).
     */
    fun clickActionAt(text: String, index: Int) {
        val buttons = row(text).findObjects(By.res("android", "action0")).sortedBy { it.visibleBounds.left }
        if (index >= buttons.size) throw AssertionError("notification with <$text> has ${buttons.size} action buttons, wanted index $index")
        buttons[index].click()
    }

    /** Clicks the body of the notification that contains [text]. */
    fun clickBody(text: String) {
        find(text).click()
    }

    /**
     * Swipes the notification that contains [text] away until [isGone] holds. A swipe can fail to
     * dismiss (seen on the emulator), so the row is found and swiped again, up to 3 times.
     */
    fun swipeAway(text: String, isGone: () -> Boolean) {
        repeat(SWIPE_RETRIES) {
            val row = runCatching { row(text, SHORT_MS) }.getOrNull() ?: return
            row.swipe(Direction.RIGHT, 1.0f, SWIPE_SPEED)
            val end = System.currentTimeMillis() + SWIPE_WAIT_MS
            while (System.currentTimeMillis() < end) {
                if (isGone()) return
                Thread.sleep(200)
            }
        }
    }

    companion object {
        private const val SYSTEM_UI = "com.android.systemui"
        private const val TIMEOUT_MS = 10_000L
        private const val SHORT_MS = 3_000L
        private const val SWIPE_SPEED = 2_000
        private const val SWIPE_RETRIES = 3
        private const val SWIPE_WAIT_MS = 4_000L
    }
}
