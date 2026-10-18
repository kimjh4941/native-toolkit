package com.jonghyunkim.android.nativetoolkit.example

import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.actionTitles
import com.jonghyunkim.android.nativetoolkit.example.infra.bigText
import com.jonghyunkim.android.nativetoolkit.example.infra.bigTitle
import com.jonghyunkim.android.nativetoolkit.example.infra.conversationTitle
import com.jonghyunkim.android.nativetoolkit.example.infra.hasLargeIcon
import com.jonghyunkim.android.nativetoolkit.example.infra.hasPicture
import com.jonghyunkim.android.nativetoolkit.example.infra.isGroupConversation
import com.jonghyunkim.android.nativetoolkit.example.infra.isOngoingEvent
import com.jonghyunkim.android.nativetoolkit.example.infra.lines
import com.jonghyunkim.android.nativetoolkit.example.infra.messages
import com.jonghyunkim.android.nativetoolkit.example.infra.subText
import com.jonghyunkim.android.nativetoolkit.example.infra.summaryText
import com.jonghyunkim.android.nativetoolkit.example.infra.template
import com.jonghyunkim.android.nativetoolkit.example.infra.text
import com.jonghyunkim.android.nativetoolkit.example.infra.title
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Notification styles (6.3 N-10 to N-17). */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationStyleUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n10_defaultStyle() {
        val sbn = show("showDefaultStyle", 1001, "✅ Displayed Default style notification.")
        assertEquals("Native Toolkit", sbn.title)
        assertEquals("Default style notification sample", sbn.text)
        assertEquals("Default", sbn.subText)
        assertEquals("native_toolkit_sample", sbn.notification.channelId)
        val channel = notifications.channel("native_toolkit_sample")!!
        assertEquals("Native Toolkit Sample", channel.name)
        assertEquals(3, channel.importance)
        expectInShade("Default style notification sample")
        delete("deleteDefaultStyle", 1001, "🗑️ Deleted Default Style notification.")
    }

    @Test
    fun n11_bigTextStyle() {
        val sbn = show("showBigTextStyle", 1002, "✅ Displayed BigText style notification.")
        assertEquals(BIG_TEXT_STYLE, sbn.template)
        assertEquals("BigText Style", sbn.bigTitle)
        assertEquals("BigText", sbn.summaryText)
        assertEquals(
            "This is a BigText notification sample from Native Toolkit Example. Expand the notification to verify the full body text rendering.",
            sbn.bigText
        )
        expectInShade("BigText style notification sample", "BigText Style")
        delete("deleteBigTextStyle", 1002, "🗑️ Deleted BigText Style notification.")
    }

    @Test
    fun n12_inboxStyle() {
        val sbn = show("showInboxStyle", 1003, "✅ Displayed Inbox style notification.")
        assertEquals("android.app.Notification\$InboxStyle", sbn.template)
        assertEquals(
            listOf("• Permission status checked", "• Channel created successfully", "• Immediate notification sent", "• Scheduled notification ready"),
            sbn.lines
        )
        assertEquals(4, sbn.notification.number)
        assertEquals("4 sample events", sbn.summaryText)
        assertEquals("Inbox Style", sbn.bigTitle)
        expectInShade("Inbox style notification sample", "Inbox Style")
        delete("deleteInboxStyle", 1003, "🗑️ Deleted Inbox Style notification.")
    }

    @Test
    fun n13_bigPictureStyle() {
        val sbn = show("showBigPictureStyle", 1004, "✅ Displayed BigPicture style notification.")
        assertEquals("android.app.Notification\$BigPictureStyle", sbn.template)
        assertTrue("no picture", sbn.hasPicture)
        assertTrue("no large icon", sbn.hasLargeIcon)
        assertEquals("Launcher image preview", sbn.summaryText)
        assertEquals("BigPicture Style", sbn.bigTitle)
        expectInShade("BigPicture style notification sample", "BigPicture Style")
        delete("deleteBigPictureStyle", 1004, "🗑️ Deleted BigPicture Style notification.")
    }

    @Test
    fun n14_messagingStyle() {
        val sbn = show("showMessagingStyle", 1005, "✅ Displayed Messaging style notification.")
        assertEquals("android.app.Notification\$MessagingStyle", sbn.template)
        // The platform MessagingStyle replaces the content title ("Native Toolkit Team") with
        // "<conversation title>: <user>"; the current value is the baseline (3.8).
        assertEquals("Native Toolkit Example: You", sbn.title)
        assertEquals(3, sbn.notification.number)
        assertEquals("Native Toolkit Example", sbn.conversationTitle)
        assertTrue("not a group conversation", sbn.isGroupConversation)
        assertEquals(
            listOf(
                "Alex" to "Can you verify the notification styles?",
                "Jordan" to "Sure, BigText / Inbox / BigPicture / Messaging are ready.",
                "You" to "Confirmed. This is the Messaging sample."
            ),
            sbn.messages.map { (sender, text) -> (sender ?: "You") to text }
        )
        expectInShade("Can you verify the notification styles?", "Confirmed. This is the Messaging sample.", "Native Toolkit Example")
        delete("deleteMessagingStyle", 1005, "🗑️ Deleted Messaging Style notification.")
    }

    @Test
    fun n15_mediaStyle() {
        val sbn = show("showMediaStyle", 1006, "✅ Displayed Media style notification.")
        assertEquals("android.app.Notification\$MediaStyle", sbn.template)
        assertEquals("Native Toolkit Player", sbn.title)
        assertTrue("not ongoing", sbn.isOngoingEvent)
        assertEquals("transport", sbn.notification.category)
        assertEquals(listOf("Previous", "Play", "Next"), sbn.actionTitles)
        expectInShade("Native Toolkit Player")
        delete("deleteMediaStyle", 1006, "🗑️ Deleted Media Style notification.")
    }

    @Test
    fun n16_decoratedCustomViewDismissButton() {
        show("showDecoratedCustomViewStyle", 1007, "✅ Displayed DecoratedCustomView style notification.")
        assertEquals("android.app.Notification\$DecoratedCustomViewStyle", notifications.waitFor(1007).template)
        shade.open()
        shade.find("Decorated custom view sample")
        shade.clickButton("Decorated custom view sample", "Dismiss")
        shade.close()
        app.waitForStatus("notification", "✅ Action button pressed: Dismiss (id=custom_view_dismiss, notificationId=1007)")
        notifications.waitFor(1007)
        delete("deleteDecoratedCustomViewStyle", 1007, "🗑️ Deleted DecoratedCustomView Style notification.")
    }

    @Test
    fun n17_decoratedMediaCustomViewStyle() {
        val sbn = show("showDecoratedMediaCustomViewStyle", 1008, "✅ Displayed DecoratedMediaCustomView style notification.")
        assertEquals("android.app.Notification\$DecoratedMediaCustomViewStyle", sbn.template)
        assertTrue("not ongoing", sbn.isOngoingEvent)
        assertEquals(listOf("Previous", "Play", "Next"), sbn.actionTitles)
        expectInShade("Decorated media custom view sample")
        delete("deleteDecoratedMediaCustomViewStyle", 1008, "🗑️ Deleted DecoratedMediaCustomView Style notification.")
    }

    private fun show(button: String, id: Int, status: String): StatusBarNotification {
        app.click("notification.$button")
        app.waitForStatus("notification", status)
        return notifications.waitFor(id)
    }

    private fun delete(button: String, id: Int, status: String) {
        app.click("notification.$button")
        app.waitForStatus("notification", status)
        notifications.waitGone(id)
    }

    private fun expectInShade(vararg texts: String) {
        shade.open()
        shade.findAny(texts.toList())
        shade.close()
    }

    private companion object {
        const val BIG_TEXT_STYLE = "android.app.Notification\$BigTextStyle"
    }
}
