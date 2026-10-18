package com.jonghyunkim.nativetoolkit.notification

import android.app.PendingIntent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-20 of the Kotlin API design (notification part, 8.5): the real PendingIntents of the event
// requests. Every event request uses request code 0, so the data URI (and the identifier of the
// full-screen launch) is what keeps them apart: no tag, an empty tag and a tag that needs encoding
// are different keys; the same key is one PendingIntent whose extras the latest request replaces.
// The full-screen launch needs a launcher Activity, which this test APK lacks; the release probe
// checks it (postColdTap).
@RunWith(AndroidJUnit4::class)
class NotificationPendingIntentIdentityTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val events = LinkedBlockingQueue<NotificationInteraction>()
    private var registration: EventHub.Registration? = null

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { registration?.remove() }
    }

    private fun pendingIntent(request: AndroidPendingIntentRequest): PendingIntent {
        val flags = request.flags or PendingIntent.FLAG_IMMUTABLE
        return when (request.type) {
            AndroidPendingIntentType.ACTIVITY -> PendingIntent.getActivity(context, request.requestCode, request.intent, flags)
            else -> PendingIntent.getBroadcast(context, request.requestCode, request.intent, flags)
        }
    }

    @Test
    fun tagsActionsAndKinds_areSeparateKeys_andTheSameKeyIsOnePendingIntent() {
        val noTag = pendingIntent(NotificationEventIntents.dismiss(context, 2001, null))
        val emptyTag = pendingIntent(NotificationEventIntents.dismiss(context, 2001, ""))
        val encodedTag = pendingIntent(NotificationEventIntents.dismiss(context, 2001, "a/b c?d#é"))
        val otherEncodedTag = pendingIntent(NotificationEventIntents.dismiss(context, 2001, "a/b c?d#e"))
        val all = listOf(noTag, emptyTag, encodedTag, otherEncodedTag)
        assertEquals("every tag is its own key", all.size, all.toSet().size)
        assertEquals(noTag, pendingIntent(NotificationEventIntents.dismiss(context, 2001, null)))
        assertEquals(encodedTag, pendingIntent(NotificationEventIntents.dismiss(context, 2001, "a/b c?d#é")))

        val tap = pendingIntent(NotificationEventIntents.bodyTap(context, 2001, null, launchApp = false))
        val first = pendingIntent(NotificationEventIntents.action(context, 2001, null, "first"))
        val second = pendingIntent(NotificationEventIntents.action(context, 2001, null, "second"))
        assertEquals(5, setOf(noTag, tap, first, second, pendingIntent(NotificationEventIntents.dismiss(context, 2002, null))).size)
    }

    @Test
    fun theSameKeyAgain_replacesTheExtras() {
        // Start without a PendingIntent of this key left by an earlier run.
        val request = NotificationEventIntents.dismiss(context, 2003, "t")
        PendingIntent.getBroadcast(context, 0, request.intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.cancel()
        instrumentation.runOnMainSync {
            NotificationEvents.interactions.addListener { _, r -> r.remove() }.remove()
            registration = NotificationEvents.interactions.addListener { event, _ -> events.add(event) }
        }
        val old = pendingIntent(NotificationEventIntents.dismiss(context, 2003, "t", mapOf("v" to "old")))
        val new = pendingIntent(NotificationEventIntents.dismiss(context, 2003, "t", mapOf("v" to "new")))
        assertEquals(old, new)
        old.send()
        val event = events.poll(10, TimeUnit.SECONDS)
        assertNotNull(event)
        assertEquals(mapOf("v" to "new"), event!!.data)
    }
}
