package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryClipboard
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Clipboard cases that the existing ClipboardSampleScreenUiTest does not cover (6.5 C-01 to C-07).
 */
@CategoryClipboard
@RunWith(AndroidJUnit4::class)
class ClipboardAdditionalUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("clipboard")
    }

    @Test
    fun c01_htmlRoundTrip() {
        app.click("clipboard.copyHtmlText")
        app.waitForStatus("clipboard", "✅ copyHtmlText called")
        app.click("clipboard.readClipboard")
        val status = app.waitForStatus("clipboard", "✅ Read: label=, mimeTypes=[text/html], items=[{text=Hello, htmlText=<b>Hello</b>, uri=null, coercedText=")
        // coercedText depends on how the platform coerces HTML, so it is not compared (6.5).
        assertTrue(status, status.endsWith("}]"))
    }

    @Test
    fun c02_plainTextRoundTrip() {
        app.click("clipboard.copyPlainText")
        app.waitForStatus("clipboard", "✅ copyPlainText called")
        app.click("clipboard.readClipboard")
        app.waitForStatus(
            "clipboard",
            "✅ Read: label=sample, mimeTypes=[text/plain], items=[{text=Hello from native-toolkit, htmlText=null, uri=null, coercedText=Hello from native-toolkit}]"
        )
    }

    @Test
    fun c03_multipleTextHasAllThreeItems() {
        app.click("clipboard.copyMultipleText")
        app.waitForStatus("clipboard", "✅ copyMultipleText called (3 items)")
        app.click("clipboard.readClipboard")
        val status = app.waitForStatus("clipboard", "✅ Read: ")
        for (text in listOf("first", "second", "third")) {
            assertTrue(status, status.contains("{text=$text, htmlText=null, uri=null, coercedText=$text}"))
        }
    }

    @Test
    fun c04_descriptionOfPlainText() {
        app.click("clipboard.copyPlainText")
        app.waitForStatus("clipboard", "✅ copyPlainText called")
        app.click("clipboard.getDescription")
        app.waitForStatus("clipboard", "✅ label=sample, mimeTypes=[text/plain], isStyledText=false, classificationStatus=")
    }

    @Test
    fun c05_sensitiveText() {
        app.click("clipboard.copySensitiveText")
        app.waitForStatus("clipboard", "✅ copySensitive called (preview suppressed on API 33+)")
        app.click("clipboard.readClipboard")
        app.waitForStatus("clipboard", "text=P@ssw0rd-sample")
    }

    @Test
    fun c06_reenteringStopsObserving() {
        app.click("clipboard.startObserving")
        app.waitForStatus("clipboard", "✅ observing started")
        app.back("clipboard")
        app.open("clipboard")
        app.click("clipboard.copyPlainText")
        app.waitForStatus("clipboard", "✅ copyPlainText called")
        Thread.sleep(2_000) // No change notification must arrive; there is no event to wait for.
        assertFalse(app.status("clipboard"), app.status("clipboard").contains("Clipboard changed"))
    }

    @Test
    fun c07_oneCopyNotifiesOnceOrTwice() {
        app.click("clipboard.startObserving")
        app.waitForStatus("clipboard", "✅ observing started")
        app.click("clipboard.copyPlainText")
        val status = app.waitForStatus("clipboard", "ℹ️ Clipboard changed (")
        // Some devices deliver one copy twice (the sample app design notes this).
        assertTrue(status, status.contains("(1)") || status.contains("(2)"))
    }
}
