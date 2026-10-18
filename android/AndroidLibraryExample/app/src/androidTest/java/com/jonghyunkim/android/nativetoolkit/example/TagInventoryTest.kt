package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Checks that every test tag the UI tests rely on exists exactly once on its screen.
 *
 * The tag list mirrors section 5.1 of the android-c-abi UI test design. A missing or duplicated
 * tag fails here first, before the behavior tests that use it.
 */
@RunWith(AndroidJUnit4::class)
class TagInventoryTest {

    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun menu_hasEveryCardTag() {
        assertTagsOnce(compose, MENU_TAGS)
    }

    @Test
    fun dialogScreen_hasEveryTag() {
        open("menu.dialog")
        assertTagsOnce(compose, DIALOG_TAGS)
    }

    @Test
    fun notificationScreen_hasEveryTag() {
        open("menu.notification")
        assertTagsOnce(compose, NOTIFICATION_TAGS)
    }

    @Test
    fun shareScreen_hasEveryTag() {
        open("menu.share")
        assertTagsOnce(compose, SHARE_TAGS)
    }

    @Test
    fun clipboardScreen_hasEveryTag() {
        open("menu.clipboard")
        assertTagsOnce(compose, CLIPBOARD_TAGS)
    }

    private fun open(menuTag: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag(menuTag))
        compose.onNodeWithTag(menuTag).performClick()
        compose.waitForIdle()
    }

    companion object {

        val MENU_TAGS = listOf("menu.dialog", "menu.notification", "menu.share", "menu.clipboard")

        val DIALOG_TAGS = tags(
            "dialog",
            "back", "status",
            "showDialog", "showConfirmDialog", "showSingleChoiceItemDialog",
            "showMultiChoiceItemDialog", "showTextInputDialog", "showLoginDialog",
            "showConfirmCoroutine", "showCancelableDialog", "showAndCancel"
        )

        val NOTIFICATION_TAGS = tags(
            "notification",
            "back", "status", "events",
            "checkNotificationPermission", "requestNotificationPermission", "requestNotificationPermissionCoroutine",
            "openNotificationSettings",
            "openAppDetailsSettings", "openExactAlarmSettings",
            "showDefaultStyle", "deleteDefaultStyle", "showBigTextStyle", "deleteBigTextStyle",
            "showInboxStyle", "deleteInboxStyle", "showBigPictureStyle", "deleteBigPictureStyle",
            "showMessagingStyle", "deleteMessagingStyle",
            "showMediaStyle", "deleteMediaStyle", "showDecoratedCustomViewStyle", "deleteDecoratedCustomViewStyle",
            "showDecoratedMediaCustomViewStyle", "deleteDecoratedMediaCustomViewStyle",
            "showGroupChild1", "showGroupChild2", "showGroupSummary", "showGroupAlertBehavior",
            "showEventSample", "showDeleteIntentSample", "showFullScreenIntentSample", "showActionButtonsSample", "deleteActionButtonsSample",
            "showProgress10", "showProgress50", "showProgress100", "showIndeterminateProgress", "deleteProgress",
            "startProgressFgs10", "updateProgressFgs50", "updateProgressFgs90", "completeProgressFgs", "stopProgressFgs",
            "incomingCall", "ongoingCall", "screeningCall", "stopCallForegroundService",
            "scheduleNotification15Sec", "checkScheduleIsScheduled", "deleteScheduleNotification"
        )

        val SHARE_TAGS = tags(
            "share",
            "back", "status",
            "shareText", "shareUrl", "shareTextWithRichPreview", "shareTextWithCustomAction", "shareTextWithInvalidAction",
            "shareWithSubjectTitle",
            "shareImage", "shareMultipleImages", "shareFile", "shareMultipleFiles",
            "registerDirectShareTarget", "removeDirectShareTarget",
            "shareWithCallback", "shareWithCallbackRichPreview", "cancelPendingCallback",
            "shareForSelection", "cancelShareSelection"
        )

        val CLIPBOARD_TAGS = tags(
            "clipboard",
            "back", "status",
            "copyPlainText", "copyPlainTextEmptyAllowed", "copyHtmlText", "copyUriContentViaFileProvider",
            "copyMultipleText", "copySensitiveText", "readClipboard", "hasClip", "getDescription", "clearClipboard",
            "startObserving", "stopObserving",
            "copyHtmlEmptyEmptyContent", "copyMultipleEmptyListEmptyItemList",
            "copyUriBlankInvalidUri", "copyUriHttpSchemeInvalidUri"
        )

        val RECEIVED_SHARE_TAGS = tags(
            "receivedShare",
            "back", "action", "mimeType", "text", "streamUris", "directShareTarget"
        )

        private fun tags(screen: String, vararg names: String): List<String> = names.map { "$screen.$it" }

        /**
         * Asserts that each tag exists exactly once, scrolling the screen's lazy list to reach it
         * when it is not composed yet.
         */
        fun assertTagsOnce(rule: ComposeTestRule, expected: List<String>) {
            for (tag in expected) {
                if (rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()) {
                    rule.onNode(hasScrollAction()).performScrollToNode(hasTestTag(tag))
                }
                rule.onAllNodesWithTag(tag).assertCountEquals(1)
            }
        }
    }
}

/** Checks the received-share screen tags, which only appear when the app is opened with a share intent. */
@RunWith(AndroidJUnit4::class)
class ReceivedShareTagInventoryTest {

    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun receivedShareScreen_hasEveryTag() {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Tag inventory")
            putExtra(Intent.EXTRA_SHORTCUT_ID, "sample_1")
        }
        ActivityScenario.launch<MainActivity>(intent).use {
            compose.waitForIdle()
            TagInventoryTest.assertTagsOnce(compose, TagInventoryTest.RECEIVED_SHARE_TAGS)
        }
    }
}
