package com.jonghyunkim.nativetoolkit

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.os.Process
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogButton
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.testing.ScheduleTestSupport
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareCallbackCoordinator
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareRepositoryImpl
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-21 of the Kotlin API design: with sentinel values in a password, clipboard text, share text
// and notification data, the operations leave no sentinel in this process's logcat (8.11). The
// test itself never logs the sentinel.
@RunWith(AndroidJUnit4::class)
class LogSentinelTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val sentinel = "ntkSentinel" + UUID.randomUUID().toString().replace("-", "")
    private var scenario: ActivityScenario<TestFragmentActivity>? = null
    private var registration: EventHub.Registration? = null

    private class RecordingContext(base: Context) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = baseContext.applicationContext
        override fun startActivity(intent: Intent) = Unit
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { registration?.remove() }
        ShareCallbackCoordinator.get(context).cancel()
        context.getSystemService(NotificationManager::class.java).cancelAll()
        scenario?.close()
    }

    @Test
    fun operationsWithSentinelValues_leaveNoSentinelInTheLog() {
        scenario = ActivityScenario.launch(TestFragmentActivity::class.java)
        device.wait(Until.hasObject(By.text(TestFragmentActivity::class.java.simpleName)), 5_000)

        // Dialog: a login dialog's username and password (also IT-03's login dialog).
        val results = LinkedBlockingQueue<DialogResult>()
        AndroidDialogManager.getInstance(context).show(DialogRequest.Login(title = "it21-login", message = "m")) { results.add(it) }
        assertNotNull(device.wait(Until.findObject(By.text("it21-login")), 5_000))
        val fields = device.findObjects(By.clazz("android.widget.EditText"))
        assertEquals(2, fields.size)
        fields[0].text = "user-$sentinel"
        fields[1].text = "pw-$sentinel"
        device.findObject(By.text("Login")).click()
        assertEquals(
            DialogResult.Button(DialogButton.POSITIVE, "Login", DialogValue.Login("user-$sentinel", "pw-$sentinel")),
            results.poll(10, TimeUnit.SECONDS)
        )

        // Dialog: a text-input dialog's text.
        AndroidDialogManager.getInstance(context).show(DialogRequest.TextInput(title = "it21-text", message = "m")) { results.add(it) }
        assertNotNull(device.wait(Until.findObject(By.text("it21-text")), 5_000))
        device.findObject(By.clazz("android.widget.EditText")).text = "text-$sentinel"
        device.findObject(By.text("OK")).click()
        assertEquals(
            DialogResult.Button(DialogButton.POSITIVE, "OK", DialogValue.Text("text-$sentinel")),
            results.poll(10, TimeUnit.SECONDS)
        )

        // Clipboard: copy and read back while this app has the focus.
        val clipboard = AndroidClipboardManager.getInstance(context)
        clipboard.copyPlainText(ClipContent.PlainText("clip-$sentinel"))
        assertEquals("clip-$sentinel", clipboard.read()?.items?.firstOrNull()?.text)

        // Share: the body (text and subject; 8.11) on every text share path; the Sharesheet is not opened.
        val share = ShareRepositoryImpl(RecordingContext(context))
        val content = ShareContent(text = "share-$sentinel", subject = "subject-$sentinel")
        share.shareText(content, "[]")
        share.shareTextWithActions(content, emptyList(), SharePreviewOptions(title = "preview"))
        share.shareForSelection(content, SharePreviewOptions())
        share.shareWithCallback(content, SharePreviewOptions(), {}, {})

        // Notification: data in a posted notification's tap, delivered as an event.
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        val useCases = NotificationUseCases(context)
        val channel = NotificationChannel(id = "ntk_it21", name = "IT-21", importance = 3)
        useCases.createChannel(channel)
        val data = mapOf("secret" to "data-$sentinel")
        val tap = NotificationEventIntents.bodyTap(context, 2101, "it21", data, launchApp = false)
        val posted = NotificationContent(
            id = 2101, title = "it21", message = "m", tag = "it21", channel = channel,
            smallIconResId = android.R.drawable.ic_dialog_info
        )
        assertTrue(useCases.show(AndroidNotificationCommand(posted, AndroidNotificationPlatformOptions(contentIntent = tap))).isSuccess)
        val events = LinkedBlockingQueue<NotificationInteraction>()
        instrumentation.runOnMainSync {
            NotificationEvents.interactions.addListener { _, r -> r.remove() }.remove()
            registration = NotificationEvents.interactions.addListener { event, _ -> events.add(event) }
        }
        PendingIntent.getBroadcast(context, tap.requestCode, tap.intent, tap.flags or PendingIntent.FLAG_IMMUTABLE).send()
        assertEquals(data, events.poll(10, TimeUnit.SECONDS)?.data)

        // Schedule: the data goes into the Alarm's JSON and the saved file.
        ScheduleTestSupport(instrumentation).shell("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow")
        val scheduled = AndroidNotificationCommand(
            posted.copy(id = 2102, tag = "it21-schedule"),
            AndroidNotificationPlatformOptions(contentIntent = NotificationEventIntents.bodyTap(context, 2102, "it21-schedule", data, launchApp = false))
        )
        assertTrue(useCases.schedule(scheduled, NotificationSchedule(System.currentTimeMillis() + 600_000, persistAcrossBoot = true)).isSuccess)
        assertTrue(useCases.isScheduled(context, 2102, "it21-schedule"))
        useCases.cancelScheduled(2102, "it21-schedule")

        Thread.sleep(1_000)
        val log = ownLog()
        // The log was read: the library's own lines of this test are in it.
        assertTrue("the library's log lines are missing", log.contains("[onReceive]") && log.contains("[shareTextWithActions]"))
        assertFalse("a sentinel value is in the log", log.contains(sentinel))
    }

    // This process's log lines, without UiAutomator's own lines (it logs the text it types into
    // the dialog). An app can read its own lines without READ_LOGS.
    private fun ownLog(): String {
        val process = ProcessBuilder("logcat", "-d", "--pid", Process.myPid().toString()).redirectErrorStream(true).start()
        val text = process.inputStream.bufferedReader().readLines().filterNot { " UiObject2: " in it }.joinToString("\n")
        process.waitFor(10, TimeUnit.SECONDS)
        return text
    }
}
