package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import com.jonghyunkim.nativetoolkit.notification.data.repository.JsonNotificationScheduleStore
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.data.repository.StoredBinarySlots
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.testing.ScheduleTestSupport
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.Serializable
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-14 of the Kotlin API design: what Intent.toUri keeps (the table of 8.6), and a lossy schedule
// shown in full before a reboot and as the table says after it (D-11).
@RunWith(AndroidJUnit4::class)
class ScheduleToUriTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val support = ScheduleTestSupport(instrumentation)
    private val useCases = NotificationUseCases(context)
    private val channel = NotificationChannel(id = "ntk_it_touri", name = "IT toUri", importance = 4)
    private val received = LinkedBlockingQueue<Intent>()
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            received.add(intent)
        }
    }

    private data class Payload(val value: String) : Serializable

    @Before
    fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        useCases.createChannel(channel)
        ContextCompat.registerReceiver(context, receiver, IntentFilter(ACTION_TARGET), ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    @After
    fun tearDown() {
        context.unregisterReceiver(receiver)
        useCases.cancelScheduled(1401)
        useCases.cancelAllScheduled()
        File(File(context.filesDir, "ntk"), JsonNotificationScheduleStore.FILE_NAME).delete()
        context.getSystemService(NotificationManager::class.java).cancelAll()
    }

    private fun roundTrip(intent: Intent): Pair<Intent, Boolean> {
        val slots = StoredBinarySlots()
        val value = slots.putIntent(intent)
        return StoredBinarySlots().intent(value) to slots.lossy
    }

    // --- the table ---

    @Test
    fun keptFields_actionDataTypeCategoriesComponentPackageSelectorFlags() {
        val intent = Intent("a.ACTION")
            .setDataAndType(Uri.parse("content://x/1"), "image/png")
            .addCategory("a.CATEGORY")
            .setClassName(context, "com.example.Target")
            .setPackage(context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val (back, lossy) = roundTrip(intent)
        assertFalse(lossy)
        assertTrue(intent.filterEquals(back))
        assertEquals(intent.component, back.component)
        assertEquals(intent.`package`, back.`package`)
        assertEquals(intent.flags, back.flags)

        // An Intent cannot have both a package and a selector.
        val withSelector = Intent("b.ACTION")
        withSelector.selector = Intent("s.ACTION").addCategory("s.CATEGORY").setPackage(context.packageName)
        val (selectorBack, selectorLossy) = roundTrip(withSelector)
        assertFalse(selectorLossy)
        assertNotNull(selectorBack.selector)
        assertTrue(withSelector.selector!!.filterEquals(selectorBack.selector!!))
    }

    @Test
    fun keptExtras_stringBooleanByteCharShortIntLongFloatDouble() {
        val intent = Intent("a.ACTION")
            .putExtra("string", "s").putExtra("boolean", true).putExtra("byte", 3.toByte())
            .putExtra("char", 'c').putExtra("short", 4.toShort()).putExtra("int", 5)
            .putExtra("long", 6L).putExtra("float", 1.5f).putExtra("double", 2.5)
        val (back, lossy) = roundTrip(intent)
        assertFalse(lossy)
        @Suppress("DEPRECATION")
        intent.extras!!.keySet().forEach { assertEquals(it, intent.extras!!.get(it), back.extras!!.get(it)) }
    }

    @Test
    fun droppedExtras_makeTheEntryLossy() {
        val dropped = mapOf<String, (Intent) -> Intent>(
            "charSequence" to { it.putExtra("x", SpannableString("span") as CharSequence) },
            "array" to { it.putExtra("x", intArrayOf(1, 2)) },
            "stringArray" to { it.putExtra("x", arrayOf("a")) },
            "arrayList" to { it.putStringArrayListExtra("x", arrayListOf("a")) },
            "parcelable" to { it.putExtra("x", Rect(1, 2, 3, 4)) },
            "uri" to { it.putExtra("x", Uri.parse("content://u")) },
            "bundle" to { it.putExtra("x", Bundle().apply { putString("k", "v") }) },
            "serializable" to { it.putExtra("x", Payload("p")) }
        )
        dropped.forEach { (name, put) ->
            val (back, lossy) = roundTrip(put(Intent("a.ACTION").putExtra("kept", "k")))
            assertTrue("$name should be lossy", lossy)
            assertFalse("$name should be dropped", back.hasExtra("x"))
            assertEquals("$name: the other extras stay", "k", back.getStringExtra("kept"))
        }
    }

    @Test
    fun clipData_isDropped_andLossy() {
        val intent = Intent("a.ACTION").apply { clipData = ClipData.newRawUri("u", Uri.parse("content://c")) }
        val (back, lossy) = roundTrip(intent)
        assertTrue(lossy)
        assertNull(back.clipData)
    }

    // The two rows the design left open: recorded by this test.
    @Test
    @SdkSuppress(minSdkVersion = 29)
    fun sourceBoundsAndIdentifier_areKept() {
        val intent = Intent("a.ACTION").setIdentifier("id-1")
        intent.sourceBounds = Rect(1, 2, 3, 4)
        val (back, lossy) = roundTrip(intent)
        assertFalse(lossy)
        assertEquals(Rect(1, 2, 3, 4), back.sourceBounds)
        assertEquals("id-1", back.identifier)
    }

    // --- a lossy schedule before and after a reboot ---

    private fun lossyCommand() = AndroidNotificationCommand(
        NotificationContent(id = 1401, title = "Lossy", message = "IT-14", channel = channel),
        AndroidNotificationPlatformOptions(
            contentIntent = AndroidPendingIntentRequest(
                intent = Intent(ACTION_TARGET).setPackage(context.packageName)
                    .putExtra("kept", "k")
                    .putStringArrayListExtra("list", arrayListOf("a", "b")),
                requestCode = 1401,
                type = AndroidPendingIntentType.BROADCAST,
                // A PendingIntent left by another test would otherwise keep its extras.
                flags = PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
    )

    private fun tapContentIntent(): Intent {
        assertTrue(support.waitPosted(1401, null))
        val posted = context.getSystemService(NotificationManager::class.java).activeNotifications.single { it.id == 1401 }
        posted.notification.contentIntent.send()
        return received.poll(10, TimeUnit.SECONDS) ?: throw AssertionError("the content intent was not delivered")
    }

    @Test
    fun lossySchedule_beforeAReboot_showsEverything() {
        assertTrue(useCases.schedule(lossyCommand(), NotificationSchedule(System.currentTimeMillis() + 600_000)).isSuccess)
        assertTrue(JsonNotificationScheduleStore(context).get(1401, null)!!.lossy)
        support.fire(1401, null)
        val delivered = tapContentIntent()
        assertEquals("k", delivered.getStringExtra("kept"))
        assertEquals(arrayListOf("a", "b"), delivered.getStringArrayListExtra("list"))
    }

    @Test
    fun lossySchedule_afterAReboot_showsWhatTheTableKeeps() {
        val store = JsonNotificationScheduleStore(context)
        assertTrue(useCases.schedule(lossyCommand(), NotificationSchedule(System.currentTimeMillis() + 600_000)).isSuccess)
        // As after a reboot: the Alarm is gone and the boot count changed.
        val entry = store.get(1401, null)!!
        store.put(entry.copy(bootCount = entry.bootCount + 1))
        support.schedulePendingIntent(1401, null)?.let {
            context.getSystemService(AlarmManager::class.java).cancel(it)
            it.cancel()
        }
        assertTrue(useCases.restoreScheduled().isSuccess)
        support.fire(1401, null)
        val delivered = tapContentIntent()
        assertEquals("k", delivered.getStringExtra("kept"))
        assertFalse(delivered.hasExtra("list"))
    }

    private companion object {
        const val ACTION_TARGET = "com.jonghyunkim.nativetoolkit.test.TO_URI_TARGET"
    }
}
