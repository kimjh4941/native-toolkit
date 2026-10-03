package com.jonghyunkim.android.nativetoolkit.example

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryClipboard
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleApp
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose UI tests for [ClipboardSampleScreen], driven through [MainActivity] like a real user.
 *
 * Automates the manual confirmation items from the sample app design that do not require
 * pasting into another app or observing system UI (see the implementation result doc for the
 * full list of automated vs. manual-only items).
 */
@CategoryClipboard
@RunWith(AndroidJUnit4::class)
class ClipboardSampleScreenUiTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    private val app by lazy { SampleApp(composeTestRule) }

    private fun navigateToClipboardScreen() {
        app.open("clipboard")
    }

    /** Clicks a button by its test tag (stage 0c: buttons are found by tag, not by label). */
    private fun click(tag: String) {
        app.click(tag)
    }

    private fun waitForStatus(substring: String) {
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText(substring, substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun copyPlainText_success_showsSuccessStatus() {
        navigateToClipboardScreen()
        click("clipboard.copyPlainText")
        waitForStatus("✅ copyPlainText called")
    }

    @Test
    fun copyPlainTextEmpty_isAllowed_showsSuccessStatus() {
        navigateToClipboardScreen()
        click("clipboard.copyPlainTextEmptyAllowed")
        waitForStatus("✅ copyPlainText (empty) called")
    }

    @Test
    fun copyUri_thenRead_showsContentUriInResult() {
        navigateToClipboardScreen()
        click("clipboard.copyUriContentViaFileProvider")
        waitForStatus("✅ copyUri called: content://")
        click("clipboard.readClipboard")
        waitForStatus("uri=content://")
    }

    @Test
    fun copyMultipleText_thenRead_showsThreeItems() {
        navigateToClipboardScreen()
        click("clipboard.copyMultipleText")
        waitForStatus("✅ copyMultipleText called (3 items)")
        click("clipboard.readClipboard")
        waitForStatus("text=first")
    }

    @Test
    fun read_afterClear_showsEmptyNormalCase() {
        navigateToClipboardScreen()
        click("clipboard.copyPlainText")
        waitForStatus("✅ copyPlainText called")
        click("clipboard.clearClipboard")
        waitForStatus("✅ clear called")
        click("clipboard.readClipboard")
        waitForStatus("ℹ️ Clipboard is empty (normal)")
    }

    @Test
    fun getDescription_afterClear_showsEmptyNormalCase() {
        navigateToClipboardScreen()
        click("clipboard.copyPlainText")
        waitForStatus("✅ copyPlainText called")
        click("clipboard.clearClipboard")
        waitForStatus("✅ clear called")
        click("clipboard.getDescription")
        waitForStatus("ℹ️ Clipboard is empty (normal)")
    }

    @Test
    fun hasClip_reflectsCopyAndClearState() {
        navigateToClipboardScreen()
        click("clipboard.copyPlainText")
        waitForStatus("✅ copyPlainText called")
        click("clipboard.hasClip")
        waitForStatus("✅ hasClip = true")
        click("clipboard.clearClipboard")
        waitForStatus("✅ clear called")
        click("clipboard.hasClip")
        waitForStatus("✅ hasClip = false")
    }

    @Test
    fun observe_startThenCopy_notifiesChange() {
        // Asserts only that a change notification arrives, not an exact count: on-device testing
        // showed the system can deliver more than one OnPrimaryClipChangedListener callback for a
        // single setPrimaryClip call (observed twice on a Pixel 6a running API 36), so asserting an
        // exact "(1)" count is flaky. The exact-count / no-duplicate-registration behavior of
        // ClipboardChangeMonitor.start() itself is covered by the library-level instrumented test
        // (ClipboardChangeMonitorTest in android_library), not duplicated here.
        navigateToClipboardScreen()
        click("clipboard.startObserving")
        waitForStatus("✅ observing started")
        click("clipboard.copyPlainText")
        waitForStatus("ℹ️ Clipboard changed")
    }

    @Test
    fun observe_doubleStart_stillObservingAndNoUiError() {
        // Verifies the UI stays consistent (no crash, "observing started" shown) across a repeated
        // Start Observing tap. Idempotent system-listener registration itself is verified by
        // ClipboardChangeMonitorTest at the library level.
        navigateToClipboardScreen()
        click("clipboard.startObserving")
        waitForStatus("✅ observing started")
        click("clipboard.startObserving")
        waitForStatus("✅ observing started")
        click("clipboard.copyPlainText")
        waitForStatus("ℹ️ Clipboard changed")
    }

    @Test
    fun observe_stop_thenCopy_doesNotNotify() {
        navigateToClipboardScreen()
        click("clipboard.startObserving")
        waitForStatus("✅ observing started")
        click("clipboard.stopObserving")
        waitForStatus("✅ observing stopped")
        click("clipboard.copyPlainText")
        waitForStatus("✅ copyPlainText called")
        // The stop status must remain the last "observing" message; no "Clipboard changed" text appears.
        composeTestRule.onNodeWithText("Clipboard changed", substring = true).assertDoesNotExist()
    }

    @Test
    fun errorCase_copyHtmlEmpty_showsEmptyContent() {
        navigateToClipboardScreen()
        click("clipboard.copyHtmlEmptyEmptyContent")
        waitForStatus("❌ EmptyContent")
    }

    @Test
    fun errorCase_copyMultipleEmptyList_showsEmptyItemList() {
        navigateToClipboardScreen()
        click("clipboard.copyMultipleEmptyListEmptyItemList")
        waitForStatus("❌ EmptyItemList")
    }

    @Test
    fun errorCase_copyUriBlank_showsInvalidUri() {
        navigateToClipboardScreen()
        click("clipboard.copyUriBlankInvalidUri")
        waitForStatus("❌ InvalidUri")
    }

    @Test
    fun errorCase_copyUriHttpScheme_showsInvalidUri() {
        navigateToClipboardScreen()
        click("clipboard.copyUriHttpSchemeInvalidUri")
        waitForStatus("❌ InvalidUri: http://example.com/x")
    }
}
