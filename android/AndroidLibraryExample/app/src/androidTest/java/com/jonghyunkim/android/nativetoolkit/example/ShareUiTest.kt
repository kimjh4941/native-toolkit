package com.jonghyunkim.android.nativetoolkit.example

import android.content.pm.ShortcutManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.Sharesheet
import androidx.test.uiautomator.By
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryShare
import com.jonghyunkim.android.nativetoolkit.example.infra.ExternalLaunchUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.Sharesheet.Companion.SAMPLE_LABEL
import com.jonghyunkim.android.nativetoolkit.example.infra.Sharesheet.Companion.SHARE_TARGET_LABEL
import com.jonghyunkim.android.nativetoolkit.example.infra.ShareTargetApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Share screen (6.4 S-01 to S-17). Contents are read in the test-only share target app (3.4, U-10).
 * The Sharesheet opens in its own task, so this class drives the sample with UiAutomator.
 */
@CategoryShare
@RunWith(AndroidJUnit4::class)
class ShareUiTest : ExternalLaunchUiTest() {

    @Before
    fun openScreen() {
        app.open("share")
    }

    @Test
    fun s01_shareText() {
        shareTo("share.shareText")
        assertEquals("android.intent.action.SEND", shareTarget.value("action"))
        assertEquals("text/plain", shareTarget.value("type"))
        assertEquals("Hello from native-toolkit", shareTarget.value("text"))
        closeTarget("✅ shareText called")
    }

    @Test
    fun s02_shareUrl() {
        shareTo("share.shareUrl")
        assertEquals("https://developer.android.com/", shareTarget.value("text"))
        closeTarget("✅ shareText (URL) called")
    }

    @Test
    fun s03_richPreview() {
        app.click("share.shareTextWithRichPreview")
        sharesheet.find("Introducing content previews")
        sharesheet.choose(SHARE_TARGET_LABEL)
        assertEquals("https://developer.android.com/", shareTarget.value("text"))
        assertEquals("Introducing content previews", shareTarget.value("title"))
        closeTarget("✅ shareText (rich preview) called")
    }

    @Test
    fun s04_customChooserAction() {
        app.click("share.shareTextWithCustomAction")
        sharesheet.choose("Custom")
        toasts.waitFor("Custom chooser action tapped")
        app.waitForStatus("share", "✅ shareText (custom action) called")
    }

    @Test
    fun s05_customChooserActionContent() {
        app.click("share.shareTextWithCustomAction")
        sharesheet.choose(SHARE_TARGET_LABEL)
        assertEquals("Shared with a custom chooser action", shareTarget.value("text"))
        closeTarget("✅ shareText (custom action) called")
    }

    @Test
    fun s06_subjectAndTitle() {
        shareTo("share.shareWithSubjectTitle")
        assertEquals("Body text shared from native-toolkit", shareTarget.value("text"))
        assertEquals("Sample subject line", shareTarget.value("subject"))
        closeTarget("✅ shareText (subject & title) called")
    }

    @Test
    fun s07_image() {
        shareTo("share.shareImage")
        assertEquals("image/png", shareTarget.value("type"))
        val streams = shareTarget.value("streams").lines()
        assertEquals("1", streams[0])
        assertTrue(streams[1], streams[1].startsWith("share_sample.png | image/png | "))
        closeTarget("✅ shareImage called")
    }

    @Test
    fun s08_multipleImages() {
        shareTo("share.shareMultipleImages")
        assertEquals("android.intent.action.SEND_MULTIPLE", shareTarget.value("action"))
        val streams = shareTarget.value("streams").lines()
        assertEquals("2", streams[0])
        assertEquals(listOf("share_sample_1.png", "share_sample_2.png"), streams.drop(1).map { it.substringBefore(" | ") })
        closeTarget("✅ shareImages called")
    }

    @Test
    fun s09_file() {
        shareTo("share.shareFile")
        assertEquals("text/plain", shareTarget.value("type"))
        val streams = shareTarget.value("streams").lines()
        assertEquals("1", streams[0])
        assertEquals("share_sample.txt | text/plain | Share sample from native-toolkit", streams[1])
        closeTarget("✅ shareFile called")
    }

    @Test
    fun s10_directShareTarget() {
        app.click("share.registerDirectShareTarget")
        app.waitForStatus("share", "✅ registerDirectShareTarget called")
        app.click("share.shareText")
        sharesheet.choose("Sample User")
        app.waitForText("receivedShare.directShareTarget", "sample_1")
        app.waitForText("receivedShare.text", "Hello from native-toolkit")
    }

    @Test
    fun s11_multipleFiles() {
        shareTo("share.shareMultipleFiles")
        assertEquals("android.intent.action.SEND_MULTIPLE", shareTarget.value("action"))
        val streams = shareTarget.value("streams").lines()
        assertEquals("2", streams[0])
        assertEquals(listOf("share_sample_1.txt", "share_sample_2.txt"), streams.drop(1).map { it.substringBefore(" | ") })
        closeTarget("✅ shareFiles called")
    }

    @Test
    fun s12_callbackReportsTheChosenTarget() {
        app.click("share.shareWithCallback")
        sharesheet.choose(SHARE_TARGET_LABEL)
        assertEquals("Hello with callback from native-toolkit", shareTarget.value("text"))
        closeTarget("✅ Selected: ${ShareTargetApp.PACKAGE}")
    }

    @Test
    fun s13_callbackStaysWaitingWhenDismissed() {
        app.click("share.shareWithCallback")
        sharesheet.dismiss()
        app.waitForStatus("share", "ℹ️ Sharesheet opened, waiting for result...")
        Thread.sleep(2_000) // The status must stay unchanged; there is no event to wait for (3.8).
        assertEquals("ℹ️ Sharesheet opened, waiting for result...", app.status("share"))
    }

    @Test
    fun s14_callbackWithRichPreview() {
        app.click("share.shareWithCallbackRichPreview")
        sharesheet.find("Callback with rich preview")
        sharesheet.choose(SHARE_TARGET_LABEL)
        closeTarget("✅ Selected: ${ShareTargetApp.PACKAGE}")
    }

    @Test
    fun s15_cancelPendingCallback() {
        app.click("share.shareWithCallback")
        sharesheet.dismiss()
        app.waitForStatus("share", "ℹ️ Sharesheet opened, waiting for result...")
        app.click("share.cancelPendingCallback")
        app.waitForStatus("share", "✅ cancelPendingCallback called")
    }

    @Test
    fun s16_sampleItselfReceivesTheShare() {
        app.click("share.shareText")
        sharesheet.choose(SAMPLE_LABEL)
        app.waitForText("receivedShare.text", "Hello from native-toolkit")
        app.waitForText("receivedShare.action", "android.intent.action.SEND")
    }

    @Test
    fun s17_removeDirectShareTarget() {
        app.click("share.registerDirectShareTarget")
        app.waitForStatus("share", "✅ registerDirectShareTarget called")
        assertTrue("sample_1 was not registered", shortcutIds().contains("sample_1"))
        app.click("share.removeDirectShareTarget")
        app.waitForStatus("share", "✅ removeDirectShareTargets called")
        assertFalse("sample_1 is still registered", shortcutIds().contains("sample_1"))
    }

    @Test
    fun s18_selectionEventReportsTheChosenTargetWithItsToken() {
        app.click("share.shareForSelection")
        app.waitForStatus("share", "waiting for selection...")
        val token = Regex("token=(\\d+)").find(app.status("share"))!!.groupValues[1]
        sharesheet.choose(SHARE_TARGET_LABEL)
        shareTarget.waitOpen()
        assertEquals("Hello with a selection event from native-toolkit", shareTarget.value("text"))
        shareTarget.close(context.packageName)
        app.waitForStatus("share", "✅ Selected (token=$token): ${ShareTargetApp.PACKAGE}")
    }

    @Test
    fun s19_selectionDismissedSendsNothing_thenCancel() {
        app.click("share.shareForSelection")
        sharesheet.dismiss()
        app.waitForStatus("share", "waiting for selection...")
        Thread.sleep(1_500)
        assertTrue(app.status("share"), app.status("share").contains("waiting for selection..."))
        // That a canceled wait gets no selection is checked by the library (IT-15); here only the
        // screen's handling of the token is.
        app.click("share.cancelShareSelection")
        app.waitForStatus("share", "✅ cancelShareSelection called (token=")
        app.click("share.cancelShareSelection")
        app.waitForStatus("share", "ℹ️ No selection is pending.")
    }

    @Test
    fun s20_invalidChooserActionIsRejected() {
        app.click("share.shareTextWithInvalidAction")
        app.waitForStatus("share", "❌ InvalidChooserAction: dup")
        Thread.sleep(1_000)
        assertFalse("the Sharesheet opened", device.hasObject(By.pkg(Sharesheet.RESOLVER)))
    }

    /**
     * Shares with [button] to the share target app. The status is checked after coming back
     * ([closeTarget]): while the Sharesheet is in front the sample's status is not visible.
     */
    private fun shareTo(button: String) {
        app.click(button)
        sharesheet.choose(SHARE_TARGET_LABEL)
    }

    /** Closes the share target app and checks the sample's status once it is back in front. */
    private fun closeTarget(status: String) {
        shareTarget.close(context.packageName)
        app.waitForStatus("share", status)
    }

    private fun shortcutIds(): List<String> {
        val manager = context.getSystemService(ShortcutManager::class.java)
        return manager.getShortcuts(ShortcutManager.FLAG_MATCH_DYNAMIC or ShortcutManager.FLAG_MATCH_CACHED).map { it.id }
    }
}
