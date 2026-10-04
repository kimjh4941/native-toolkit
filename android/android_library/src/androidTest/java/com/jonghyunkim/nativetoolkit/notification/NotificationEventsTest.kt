package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.testing.NotificationShade
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-09 and IT-10 of the Kotlin API design: notification events through the library receivers.
@RunWith(AndroidJUnit4::class)
class NotificationEventsTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val shade = NotificationShade(instrumentation, device)
    private val useCases = NotificationUseCases(context)
    private val channel = NotificationChannel(id = "ntk_it_events", name = "IT events", importance = 4)
    private val events = LinkedBlockingQueue<NotificationInteraction>()
    private var registration: EventHub.Registration? = null

    @Before
    fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        useCases.createChannel(channel)
        // Drop events retained by earlier tests.
        instrumentation.runOnMainSync { NotificationEvents.interactions.addListener { _, r -> r.remove() }.remove() }
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { registration?.remove() }
        shade.close()
        context.getSystemService(NotificationManager::class.java).cancelAll()
    }

    private fun listen() {
        instrumentation.runOnMainSync {
            registration = NotificationEvents.interactions.addListener { event, _ -> events.add(event) }
        }
    }

    private fun next(): NotificationInteraction {
        val event = events.poll(10, TimeUnit.SECONDS)
        assertNotNull("no event within 10 s", event)
        return event!!
    }

    private fun post(id: Int, title: String, data: Map<String, String>) {
        val options = AndroidNotificationPlatformOptions(
            contentIntent = NotificationEventIntents.bodyTap(context, id, "tag-$id", data, launchApp = false),
            deleteIntent = NotificationEventIntents.dismiss(context, id, "tag-$id", data),
            actions = listOf(
                AndroidNotificationAction(
                    title = "Act$id",
                    pendingIntent = NotificationEventIntents.action(context, id, "tag-$id", "act-$id", data)
                )
            )
        )
        val content = NotificationContent(
            id = id, title = title, message = "m", tag = "tag-$id", channel = channel,
            smallIconResId = android.R.drawable.ic_dialog_info
        )
        assertTrue(useCases.show(AndroidNotificationCommand(content, options)).isSuccess)
    }

    @Test
    fun actionButton_deliversTheActionWithItsData() {
        listen()
        post(9101, "it09-action", mapOf("k" to "v"))
        shade.open()
        shade.clickButton("it09-action", "Act9101")
        val event = next()
        assertEquals(
            NotificationInteraction(NotificationInteraction.Kind.ACTION, 9101, "tag-9101", "act-9101", mapOf("k" to "v")),
            event
        )
    }

    @Test
    fun bodyTap_deliversTheTap() {
        listen()
        post(9102, "it09-body", emptyMap())
        shade.open()
        shade.clickBody("it09-body")
        assertEquals(
            NotificationInteraction(NotificationInteraction.Kind.BODY_TAP, 9102, "tag-9102", null, emptyMap()),
            next()
        )
    }

    @Test
    fun swipeAway_deliversTheDismissal() {
        listen()
        post(9103, "it09-dismiss", emptyMap())
        shade.open()
        shade.swipeAway("it09-dismiss") { events.isNotEmpty() }
        assertEquals(
            NotificationInteraction(NotificationInteraction.Kind.DISMISS, 9103, "tag-9103", null, emptyMap()),
            next()
        )
    }

    @Test
    fun twoNotifications_doNotShareAPendingIntent() {
        listen()
        post(9104, "it09-first", mapOf("n" to "1"))
        post(9105, "it09-second", mapOf("n" to "2"))
        shade.open()
        shade.clickButton("it09-first", "Act9104")
        val event = next()
        assertEquals(9104, event.notificationId)
        assertEquals(mapOf("n" to "1"), event.data)
    }

    @Test
    fun eventsWithoutAListener_areRetained_andGoToTheFirstListenerInOrder() {
        val first = NotificationEventIntents.dismiss(context, 9201, null, mapOf("i" to "1"))
        val second = NotificationEventIntents.dismiss(context, 9202, null, mapOf("i" to "2"))
        PendingIntent.getBroadcast(context, 0, first.intent, first.flags or PendingIntent.FLAG_IMMUTABLE).send()
        PendingIntent.getBroadcast(context, 0, second.intent, second.flags or PendingIntent.FLAG_IMMUTABLE).send()
        Thread.sleep(2_000)
        listen()
        assertEquals(9201, next().notificationId)
        assertEquals(9202, next().notificationId)
        assertNull(events.poll(500, TimeUnit.MILLISECONDS))
    }

    @Test
    fun launchActivityPath_deliversTheEvent_andFinishesWithoutALauncher() {
        listen()
        val request = NotificationEventIntents.bodyTap(context, 9301, null, emptyMap(), launchApp = true)
        context.startActivity(Intent(request.intent).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        assertEquals(NotificationInteraction.Kind.BODY_TAP, next().kind)
    }

    @Test
    fun fullScreenLaunch_hasNoDataUri_whenTheAppHasALauncher() {
        // The library test APK has no launcher Activity, so there is nothing to launch.
        assertNull(NotificationEventIntents.fullScreenLaunch(context, 1, null))
    }
}
