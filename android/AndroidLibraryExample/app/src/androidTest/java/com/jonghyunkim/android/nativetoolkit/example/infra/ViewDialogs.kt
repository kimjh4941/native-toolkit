package com.jonghyunkim.android.nativetoolkit.example.infra

import android.app.Instrumentation
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until

/**
 * Operates the library's `DialogFragment`, which shows a platform `android.app.AlertDialog`
 * (View-based, so not visible to the Compose rule).
 */
class ViewDialogs(private val instrumentation: Instrumentation, private val device: UiDevice) {

    /** Waits for the dialog with [title] and returns its title object. */
    fun waitFor(title: String): UiObject2 =
        device.wait(Until.findObject(By.res("android", "alertTitle").text(title)), TIMEOUT_MS)
            ?: throw AssertionError("dialog <$title> did not appear")

    fun message(): String? = device.findObject(By.res("android", "message"))?.text

    /** The positive button (`android:id/button1`). */
    fun positive(): UiObject2 = button("button1")

    /** The negative button (`android:id/button2`). */
    fun negative(): UiObject2 = button("button2")

    fun isShowing(): Boolean = device.hasObject(By.res("android", "alertTitle"))

    /** Clicks the list item labelled [label] (single or multi choice). */
    fun clickItem(label: String) {
        (device.findObject(By.text(label)) ?: throw AssertionError("no item <$label>")).click()
    }

    /** Whether the list item labelled [label] is checked. */
    fun isChecked(label: String): Boolean =
        (device.findObject(By.text(label)) ?: throw AssertionError("no item <$label>")).isChecked

    /** The dialog's text fields, in screen order. */
    fun inputs(): List<UiObject2> = device.findObjects(By.clazz("android.widget.EditText")).sortedBy { it.visibleBounds.top }

    /** Hint text and password flag of each text field, read from the accessibility nodes. */
    fun inputInfo(): List<Pair<String?, Boolean>> {
        val result = mutableListOf<Pair<String?, Boolean>>()
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return result
        val queue = ArrayDeque<AccessibilityNodeInfo>().apply { add(root) }
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.className?.toString() == "android.widget.EditText") {
                result.add(node.hintText?.toString() to node.isPassword)
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.addLast(it) }
        }
        return result
    }

    /** Taps outside the dialog (above it). */
    fun tapOutside() {
        device.click(device.displayWidth / 2, device.displayHeight / 12)
        device.waitForIdle()
    }

    private fun button(id: String): UiObject2 =
        device.findObject(By.res("android", id)) ?: throw AssertionError("dialog has no $id")

    private companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
