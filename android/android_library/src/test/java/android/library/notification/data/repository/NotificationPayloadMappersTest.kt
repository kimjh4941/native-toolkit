package android.library.notification.data.repository

import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCallPlatformOptions
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.domain.model.NotificationCallPerson
import android.library.notification.domain.model.NotificationCallType
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.domain.model.NotificationStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationPayloadMappersTest {

    @Test
    fun mediaStyle_roundTripsThroughPayload() {
        val command = AndroidNotificationCommand(
            content = NotificationContent(
                id = 1,
                title = "Media",
                message = "Media sample",
                style = NotificationStyle.Media(compactActionIndices = listOf(0, 1, 2))
            )
        )

        val restored = command.toPayload().toCommand()
        val restoredStyle = restored.content.style as NotificationStyle.Media

        assertEquals(listOf(0, 1, 2), restoredStyle.compactActionIndices)
    }

    @Test
    fun decoratedAndCallStyles_roundTripThroughPayload() {
        val customView = NotificationCustomViewStyleData(
            layoutResId = 100,
            bigLayoutResId = 101,
            titleViewId = 102,
            titleText = "Title",
            messageViewId = 103,
            messageText = "Message",
            iconViewId = 104,
            iconResId = 105
        )
        val pendingIntent = AndroidPendingIntentRequest(
            intent = Intent("native.toolkit.test"),
            requestCode = 77
        )
        val command = AndroidNotificationCommand(
            content = NotificationContent(
                id = 2,
                title = "Call",
                message = "Call sample",
                style = NotificationStyle.Call(
                    callType = NotificationCallType.INCOMING,
                    person = NotificationCallPerson(name = "Toolkit", avatarResId = 123),
                    isVideo = true,
                    verificationText = "Verified"
                )
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                callStyleOptions = AndroidNotificationCallPlatformOptions(
                    answerIntent = pendingIntent,
                    declineIntent = pendingIntent
                )
            )
        )

        val decoratedRestored = AndroidNotificationCommand(
            content = NotificationContent(
                id = 3,
                title = "Custom",
                message = "Decorated sample",
                style = NotificationStyle.DecoratedMediaCustomView(
                    customView = customView,
                    compactActionIndices = listOf(1, 2)
                )
            )
        ).toPayload().toCommand()

        val callRestored = command.toPayload().toCommand()

        val decoratedStyle = decoratedRestored.content.style as NotificationStyle.DecoratedMediaCustomView
        val callStyle = callRestored.content.style as NotificationStyle.Call

        assertEquals(customView, decoratedStyle.customView)
        assertEquals(listOf(1, 2), decoratedStyle.compactActionIndices)
        assertEquals(NotificationCallType.INCOMING, callStyle.callType)
        assertEquals("Toolkit", callStyle.person.name)
        assertTrue(callStyle.isVideo)
        assertEquals("Verified", callStyle.verificationText)
        assertEquals(77, callRestored.platformOptions.callStyleOptions?.answerIntent?.requestCode)
    }
}

