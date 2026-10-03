package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryReceivedShare
import com.jonghyunkim.android.nativetoolkit.example.infra.ExternalLaunchUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleApp
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Receiving a share while the sample is running (6.4 R-01, R-03 to R-07). The share reaches the
 * running `MainActivity` through `onNewIntent`, so this class drives the sample with UiAutomator.
 */
@CategoryReceivedShare
@RunWith(AndroidJUnit4::class)
class ReceivedShareUiTest : ExternalLaunchUiTest() {

    @Test
    fun r01_sendTextWhileRunning() {
        send(shareIntent())
        app.waitForText("receivedShare.action", "android.intent.action.SEND")
        app.waitForText("receivedShare.mimeType", "text/plain")
        app.waitForText("receivedShare.text", "Received text")
        app.waitForText("receivedShare.streamUris", "(none)")
    }

    @Test
    fun r03_sendImageStream() {
        send(Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, URI_1))
        app.waitForText("receivedShare.streamUris", "1 URI(s):\n$URI_1")
        app.waitForText("receivedShare.text", "(none)")
    }

    @Test
    fun r04_sendMultipleIgnoresText() {
        send(
            Intent(Intent.ACTION_SEND_MULTIPLE).setType("image/png")
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(URI_1, URI_2))
                .putExtra(Intent.EXTRA_TEXT, "Ignored text")
        )
        app.waitForText("receivedShare.action", "android.intent.action.SEND_MULTIPLE")
        app.waitForText("receivedShare.streamUris", "2 URI(s):\n$URI_1\n$URI_2")
        app.waitForText("receivedShare.text", "(none)")
    }

    @Test
    fun r05_directShareShortcutId() {
        send(shareIntent().putExtra(Intent.EXTRA_SHORTCUT_ID, "sample_1"))
        app.waitForText("receivedShare.directShareTarget", "sample_1")
    }

    @Test
    fun r06_backButtonClearsTheShare() {
        send(shareIntent())
        app.waitForText("receivedShare.text", "Received text")
        app.click("receivedShare.back")
        app.waitFor("menu.dialog")
        reopenFromLauncher()
        check(!app.exists("receivedShare.back")) { "the received-share screen came back" }
    }

    @Test
    fun r07_systemBackClearsTheShare() {
        send(shareIntent())
        app.waitForText("receivedShare.text", "Received text")
        device.pressBack()
        app.waitFor("menu.dialog")
        reopenFromLauncher()
        check(!app.exists("receivedShare.back")) { "the received-share screen came back" }
    }

    private fun send(intent: Intent) {
        context.startActivity(intent.setClass(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Goes home and opens the sample again from its launcher intent (without clearing the task). */
    private fun reopenFromLauncher() {
        device.pressHome()
        state.bringSampleToFront()
        app.waitFor("menu.dialog")
    }

    companion object {
        val URI_1: Uri = Uri.parse("content://com.jonghyunkim.android.nativetoolkit.example.test/one.png")
        val URI_2: Uri = Uri.parse("content://com.jonghyunkim.android.nativetoolkit.example.test/two.png")

        fun shareIntent(): Intent =
            Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "Received text")
    }
}

/** Receiving a share when the sample has no activity yet (6.4 R-02; a process cold start is H-04). */
@CategoryReceivedShare
@RunWith(AndroidJUnit4::class)
class ReceivedShareLaunchUiTest {

    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun r02_sendTextWithoutAnActivity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = ReceivedShareUiTest.shareIntent().setClass(context, MainActivity::class.java)
        ActivityScenario.launch<MainActivity>(intent).use {
            val app = SampleApp(compose)
            app.waitForText("receivedShare.action", "android.intent.action.SEND")
            app.waitForText("receivedShare.mimeType", "text/plain")
            app.waitForText("receivedShare.text", "Received text")
        }
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressHome()
    }
}
