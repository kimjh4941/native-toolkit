package com.jonghyunkim.nativetoolkit.notification

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Parcel
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationSchedulerSupport
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledAlarmExtras
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationReceiver
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventReceiver
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationLaunchActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// IT-24 of the Kotlin API design: the identifiers that must not change after 2.0.0 (8.5) and the
// Alarm extras (8.6). The values are written out here on purpose: a rename must break this test.
@RunWith(AndroidJUnit4::class)
class ScheduleIdentifiersTest {

    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun receiverClassNames_areFrozen_andInTheManifest() {
        val receivers = mapOf(
            ScheduledNotificationReceiver::class.java to "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationReceiver",
            NotificationEventReceiver::class.java to "com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventReceiver"
        )
        receivers.forEach { (type, name) ->
            assertEquals(name, type.name)
            assertNotNull(context.packageManager.getReceiverInfo(ComponentName(context, name), 0))
        }
        val activity = "com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationLaunchActivity"
        assertEquals(activity, NotificationLaunchActivity::class.java.name)
        assertNotNull(context.packageManager.getActivityInfo(ComponentName(context, activity), 0))
    }

    @Test
    fun eventIdentifiers_areFrozen() {
        assertEquals("com.jonghyunkim.nativetoolkit.notification.action.EVENT", NotificationEventIntents.ACTION_EVENT)
        assertEquals("ntk-notification-event", NotificationEventIntents.SCHEME_EVENT)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.extra.DATA", NotificationEventIntents.EXTRA_DATA)
        assertEquals("ntk-notification-launch/", NotificationEventIntents.IDENTIFIER_LAUNCH_PREFIX)
    }

    @Test
    fun scheduleIdentifiers_areFrozen() {
        assertEquals("com.jonghyunkim.nativetoolkit.notification.action.SHOW_SCHEDULED", NotificationSchedulerSupport.ACTION_SHOW_SCHEDULED)
        assertEquals("ntk-notification-schedule", NotificationSchedulerSupport.SCHEME_SCHEDULE)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.extra.COMMAND_JSON", ScheduledAlarmExtras.COMMAND_JSON)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.extra.INTENTS", ScheduledAlarmExtras.INTENTS)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.extra.BITMAPS", ScheduledAlarmExtras.BITMAPS)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.extra.GENERATION", ScheduledAlarmExtras.GENERATION)
    }

    @Test
    fun alarmIntent_isExplicit_withTheFrozenActionAndData() {
        val intent = NotificationSchedulerSupport.scheduleIntent(context, 7, null)
        assertEquals(ComponentName(context.packageName, "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationReceiver"), intent.component)
        assertEquals("com.jonghyunkim.nativetoolkit.notification.action.SHOW_SCHEDULED", intent.action)
        assertEquals("ntk-notification-schedule://${context.packageName}/untagged/7", intent.dataString)
        assertEquals(
            "ntk-notification-schedule://${context.packageName}/a%2Fb/8",
            NotificationSchedulerSupport.scheduleIntent(context, 8, "a/b").dataString
        )
    }

    @Test
    fun alarmExtras_areOnlyTheFour_withFrameworkParcelablesOnly() {
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        val userIntent = Intent("user.ACTION").setClassName(context, "com.example.UserActivity").putExtra("k", "v")
        val command = AndroidNotificationCommand(
            NotificationContent(id = 9, title = "t", message = "m"),
            AndroidNotificationPlatformOptions(
                largeIconBitmap = bitmap,
                contentIntent = AndroidPendingIntentRequest(intent = userIntent, requestCode = 1)
            )
        )
        val intent = ScheduledAlarmExtras.intent(context, command, generation = 42L)
        val extras = intent.extras!!
        assertEquals(
            setOf(ScheduledAlarmExtras.COMMAND_JSON, ScheduledAlarmExtras.INTENTS, ScheduledAlarmExtras.BITMAPS, ScheduledAlarmExtras.GENERATION),
            extras.keySet()
        )
        assertEquals(42L, intent.getLongExtra(ScheduledAlarmExtras.GENERATION, 0))
        val json = intent.getStringExtra(ScheduledAlarmExtras.COMMAND_JSON)!!
        assertFalse("library class name in the JSON: $json", json.contains("com.jonghyunkim.nativetoolkit"))

        // Marshal the extras as the Alarm does and read them back with only the framework's class loader.
        val parcel = Parcel.obtain()
        val bytes = try {
            extras.writeToParcel(parcel, 0)
            parcel.marshall()
        } finally {
            parcel.recycle()
        }
        val restored = Parcel.obtain().let { p ->
            try {
                p.unmarshall(bytes, 0, bytes.size)
                p.setDataPosition(0)
                Bundle.CREATOR.createFromParcel(p).apply { classLoader = Bundle::class.java.classLoader }
            } finally {
                p.recycle()
            }
        }
        restored.keySet().forEach { key -> assertNotNull(key, restored.get(key)) }
        val restoredIntents = if (Build.VERSION.SDK_INT >= 33) {
            restored.getParcelableArrayList(ScheduledAlarmExtras.INTENTS, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            restored.getParcelableArrayList(ScheduledAlarmExtras.INTENTS)
        }
        assertTrue(restoredIntents!!.single().filterEquals(userIntent))
        val decoded = ScheduledAlarmExtras.commandOf(Intent().putExtras(restored))
        assertEquals(command.content, decoded.content)
        assertTrue(decoded.platformOptions.largeIconBitmap!!.sameAs(bitmap))
    }

    @Test
    fun generation_isReadBack_andMissingIsNull() {
        val intent = NotificationSchedulerSupport.scheduleIntent(context, 1, null)
        assertEquals(null, ScheduledAlarmExtras.generationOf(intent))
        assertEquals(5L, ScheduledAlarmExtras.generationOf(intent.putExtra(ScheduledAlarmExtras.GENERATION, 5L)))
    }

    @Test
    fun idAndTag_areReadFromTheData() {
        assertEquals(7 to null, NotificationSchedulerSupport.idAndTagOf(NotificationSchedulerSupport.scheduleIntent(context, 7, null)))
        assertEquals(8 to "a/b", NotificationSchedulerSupport.idAndTagOf(NotificationSchedulerSupport.scheduleIntent(context, 8, "a/b")))
        assertEquals(null, NotificationSchedulerSupport.idAndTagOf(Intent().setData(android.net.Uri.parse("other://x/untagged/1"))))
    }
}
