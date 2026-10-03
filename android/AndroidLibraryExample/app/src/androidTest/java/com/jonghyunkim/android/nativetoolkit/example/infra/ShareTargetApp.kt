package com.jonghyunkim.android.nativetoolkit.example.infra

import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until

/**
 * Reads what the test-only share target app (`testShareTarget`, U-10) received.
 *
 * The app shows each value in a view with a resource ID `result_<name>`.
 */
class ShareTargetApp(private val device: UiDevice) {

    fun waitOpen() {
        if (!device.wait(Until.hasObject(By.res(PACKAGE, "result_action")), TIMEOUT_MS)) {
            throw AssertionError("the share target app did not open")
        }
    }

    /** The value shown for [name] (`action`, `type`, `text`, `subject`, `title`, `streams`). */
    fun value(name: String): String {
        waitOpen()
        return device.findObject(By.res(PACKAGE, "result_$name"))?.text.orEmpty()
    }

    /** Closes the share target app and waits for the sample to be in front again. */
    fun close(samplePackage: String) {
        device.pressBack()
        device.wait(Until.hasObject(By.pkg(samplePackage).depth(0)), TIMEOUT_MS)
    }

    companion object {
        const val PACKAGE = "com.jonghyunkim.android.nativetoolkit.testsharetarget"
        private const val TIMEOUT_MS = 10_000L
    }
}
