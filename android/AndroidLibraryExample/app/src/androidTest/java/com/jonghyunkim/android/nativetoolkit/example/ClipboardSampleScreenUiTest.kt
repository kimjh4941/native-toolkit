package com.jonghyunkim.android.nativetoolkit.example

import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
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
@RunWith(AndroidJUnit4::class)
class ClipboardSampleScreenUiTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    private fun navigateToClipboardScreen() {
        composeTestRule.onNode(hasScrollAction()).performScrollToNode(hasText("Clipboard Example"))
        composeTestRule.onNodeWithText("Clipboard Example").performClick()
        composeTestRule.onNodeWithText("Clipboard Example", substring = true).assertExists()
    }

    private fun click(label: String) {
        // The button list is a LazyColumn: off-screen nodes are not composed yet, so scroll the
        // scrollable container to the target node (by matcher) rather than scrolling the node itself.
        composeTestRule.onNode(hasScrollAction()).performScrollToNode(hasText(label))
        composeTestRule.onNodeWithText(label).performClick()
    }

    private fun waitForStatus(substring: String) {
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText(substring, substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun copyPlainText_success_showsSuccessStatus() {
        navigateToClipboardScreen()
        click("Copy Plain Text")
        waitForStatus("✅ copyPlainText called")
    }

    @Test
    fun copyPlainTextEmpty_isAllowed_showsSuccessStatus() {
        navigateToClipboardScreen()
        click("Copy Plain Text (empty, allowed)")
        waitForStatus("✅ copyPlainText (empty) called")
    }

    @Test
    fun copyUri_thenRead_showsContentUriInResult() {
        navigateToClipboardScreen()
        click("Copy URI (content:// via FileProvider)")
        waitForStatus("✅ copyUri called: content://")
        click("Read Clipboard")
        waitForStatus("uri=content://")
    }

    @Test
    fun copyMultipleText_thenRead_showsThreeItems() {
        navigateToClipboardScreen()
        click("Copy Multiple Text")
        waitForStatus("✅ copyMultipleText called (3 items)")
        click("Read Clipboard")
        waitForStatus("text=first")
    }

    @Test
    fun read_afterClear_showsEmptyNormalCase() {
        navigateToClipboardScreen()
        click("Copy Plain Text")
        waitForStatus("✅ copyPlainText called")
        click("Clear Clipboard")
        waitForStatus("✅ clear called")
        click("Read Clipboard")
        waitForStatus("ℹ️ Clipboard is empty (normal)")
    }

    @Test
    fun getDescription_afterClear_showsEmptyNormalCase() {
        navigateToClipboardScreen()
        click("Copy Plain Text")
        waitForStatus("✅ copyPlainText called")
        click("Clear Clipboard")
        waitForStatus("✅ clear called")
        click("Get Description")
        waitForStatus("ℹ️ Clipboard is empty (normal)")
    }

    @Test
    fun hasClip_reflectsCopyAndClearState() {
        navigateToClipboardScreen()
        click("Copy Plain Text")
        waitForStatus("✅ copyPlainText called")
        click("Has Clip")
        waitForStatus("✅ hasClip = true")
        click("Clear Clipboard")
        waitForStatus("✅ clear called")
        click("Has Clip")
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
        click("Start Observing")
        waitForStatus("✅ observing started")
        click("Copy Plain Text")
        waitForStatus("ℹ️ Clipboard changed")
    }

    @Test
    fun observe_doubleStart_stillObservingAndNoUiError() {
        // Verifies the UI stays consistent (no crash, "observing started" shown) across a repeated
        // Start Observing tap. Idempotent system-listener registration itself is verified by
        // ClipboardChangeMonitorTest at the library level.
        navigateToClipboardScreen()
        click("Start Observing")
        waitForStatus("✅ observing started")
        click("Start Observing")
        waitForStatus("✅ observing started")
        click("Copy Plain Text")
        waitForStatus("ℹ️ Clipboard changed")
    }

    @Test
    fun observe_stop_thenCopy_doesNotNotify() {
        navigateToClipboardScreen()
        click("Start Observing")
        waitForStatus("✅ observing started")
        click("Stop Observing")
        waitForStatus("✅ observing stopped")
        click("Copy Plain Text")
        waitForStatus("✅ copyPlainText called")
        // The stop status must remain the last "observing" message; no "Clipboard changed" text appears.
        composeTestRule.onNodeWithText("Clipboard changed", substring = true).assertDoesNotExist()
    }

    @Test
    fun errorCase_copyHtmlEmpty_showsEmptyContent() {
        navigateToClipboardScreen()
        click("Copy HTML (empty) → EmptyContent")
        waitForStatus("❌ EmptyContent")
    }

    @Test
    fun errorCase_copyMultipleEmptyList_showsEmptyItemList() {
        navigateToClipboardScreen()
        click("Copy Multiple (empty list) → EmptyItemList")
        waitForStatus("❌ EmptyItemList")
    }

    @Test
    fun errorCase_copyUriBlank_showsInvalidUri() {
        navigateToClipboardScreen()
        click("Copy URI (blank) → InvalidUri")
        waitForStatus("❌ InvalidUri")
    }

    @Test
    fun errorCase_copyUriHttpScheme_showsInvalidUri() {
        navigateToClipboardScreen()
        click("Copy URI (http scheme) → InvalidUri")
        waitForStatus("❌ InvalidUri: http://example.com/x")
    }
}
