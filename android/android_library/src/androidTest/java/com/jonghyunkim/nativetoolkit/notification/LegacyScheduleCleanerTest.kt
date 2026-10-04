package com.jonghyunkim.nativetoolkit.notification

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryExecutors
import com.jonghyunkim.nativetoolkit.notification.data.repository.AndroidLegacyScheduleEnvironment
import com.jonghyunkim.nativetoolkit.notification.data.repository.LegacyScheduleCleaner
import com.jonghyunkim.nativetoolkit.notification.data.repository.LegacyScheduleEnvironment
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationBootReceiver
import com.jonghyunkim.nativetoolkit.testing.ScheduleTestSupport
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.TimeUnit

// IT-18 of the Kotlin API design: discarding the 1.x schedules (8.6, KA-9). The test writes the
// 1.x SharedPreferences and sets Alarms with the 1.x Intent (stage 0e result, chapter 4).
@RunWith(AndroidJUnit4::class)
class LegacyScheduleCleanerTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val support = ScheduleTestSupport(instrumentation)
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val marker = LegacyScheduleCleaner.markerFile(context)
    private val preferencesFile = File(context.dataDir, "shared_prefs/${LegacyScheduleCleaner.LEGACY_PREFERENCES}.xml")
    private val base = System.currentTimeMillis() + 3_600_000

    // key, trigger time
    private val legacy = listOf(
        Triple(1801, null as String?, base + 1),
        Triple(1802, "news", base + 2),
        Triple(1803, "a::b", base + 3)
    )

    @Before
    fun setUp() {
        drainBackground()
        LegacyScheduleCleaner.resetForTest()
        marker.delete()
        context.deleteSharedPreferences(LegacyScheduleCleaner.LEGACY_PREFERENCES)
    }

    @After
    fun tearDown() {
        drainBackground()
        legacy.forEach { (id, tag, _) -> legacyPendingIntent(id, tag, PendingIntent.FLAG_NO_CREATE)?.let { alarmManager.cancel(it); it.cancel() } }
        LegacyScheduleCleaner.resetForTest()
        context.deleteSharedPreferences(LegacyScheduleCleaner.LEGACY_PREFERENCES)
        // Leave the device as a 2.x install that already discarded 1.x.
        marker.parentFile?.mkdirs()
        marker.createNewFile()
    }

    private fun drainBackground() {
        LibraryExecutors.io.submit { }.get(10, TimeUnit.SECONDS)
    }

    private fun legacyPendingIntent(id: Int, tag: String?, flag: Int): PendingIntent? = PendingIntent.getBroadcast(
        context,
        "${tag ?: "untagged"}::$id".hashCode(),
        LegacyScheduleCleaner.legacyIntent(context, id, tag),
        flag or PendingIntent.FLAG_IMMUTABLE
    )

    // What 1.x left behind: the saved entries and their Alarms.
    private fun install1x(extraEntries: Set<String> = emptySet()) {
        val entries = legacy.map { (id, tag, _) ->
            JSONObject()
                .put(Intent.EXTRA_SHORTCUT_ID, "${tag ?: "untagged"}::$id")
                .put("command", "AAAA")
                .put("schedule", "AAAA")
                .toString()
        }.toSet() + extraEntries
        assertTrue(
            context.getSharedPreferences(LegacyScheduleCleaner.LEGACY_PREFERENCES, Context.MODE_PRIVATE)
                .edit().putStringSet("entries", entries).commit()
        )
        legacy.forEach { (id, tag, at) ->
            alarmManager.set(AlarmManager.RTC_WAKEUP, at, legacyPendingIntent(id, tag, PendingIntent.FLAG_UPDATE_CURRENT)!!)
        }
        val times = support.alarmTimes(LegacyScheduleCleaner.LEGACY_ACTION)
        legacy.forEach { (_, _, at) -> assertTrue("1.x Alarm at $at not set: $times", at in times) }
    }

    private fun assertDiscarded() {
        val times = support.alarmTimes(LegacyScheduleCleaner.LEGACY_ACTION)
        legacy.forEach { (id, tag, at) ->
            assertFalse("1.x Alarm at $at still set", at in times)
            assertNull(legacyPendingIntent(id, tag, PendingIntent.FLAG_NO_CREATE))
        }
        assertFalse(preferencesFile.exists())
        assertTrue(marker.exists())
    }

    @Test
    fun legacyIdentifiers_areTheOnesOf1x() {
        val intent = LegacyScheduleCleaner.legacyIntent(context, 5, null)
        assertEquals("android.library.notification.data.repository.ScheduledNotificationReceiver", intent.component?.className)
        assertEquals(context.packageName, intent.component?.packageName)
        assertEquals("android.library.notification.action.SHOW_SCHEDULED", intent.action)
        assertEquals("native-toolkit-notification://${context.packageName}/untagged/5", intent.dataString)
        assertEquals(context.packageName, intent.`package`)
        assertEquals("untagged::5".hashCode(), LegacyScheduleCleaner.legacyRequestCode(5, null))
        assertEquals("android.library.notification.scheduler", LegacyScheduleCleaner.LEGACY_PREFERENCES)
    }

    @Test
    fun myPackageReplaced_discardsThe1xSchedules() {
        install1x()
        ScheduledNotificationBootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))
        drainBackground()
        assertDiscarded()
    }

    @Test
    fun firstUseOfTheUseCases_discardsThe1xSchedules() {
        install1x()
        NotificationUseCases(context)
        drainBackground()
        assertDiscarded()
    }

    @Test
    fun unreadableEntries_areSkipped() {
        install1x(setOf("{not json", JSONObject().put(Intent.EXTRA_SHORTCUT_ID, "bad").toString()))
        assertTrue(LegacyScheduleCleaner.runOnce(context))
        assertDiscarded()
    }

    @Test
    fun aFailureOnTheWay_keepsThePreferences_andTheNextTriggerFinishes() {
        install1x()
        var failOnce = true
        LegacyScheduleCleaner.environmentFactory = { ctx ->
            val real = AndroidLegacyScheduleEnvironment(ctx)
            object : LegacyScheduleEnvironment by real {
                override fun cancelAlarm(id: Int, tag: String?) {
                    if (id == 1802 && failOnce) {
                        failOnce = false
                        throw IllegalStateException("injected")
                    }
                    real.cancelAlarm(id, tag)
                }
            }
        }
        assertFalse(LegacyScheduleCleaner.runOnce(context))
        assertTrue(preferencesFile.exists())
        assertFalse(marker.exists())
        assertTrue(base + 2 in support.alarmTimes(LegacyScheduleCleaner.LEGACY_ACTION))

        assertTrue(LegacyScheduleCleaner.runOnce(context))
        assertDiscarded()
    }

    @Test
    fun marked_doesNothing() {
        install1x()
        marker.parentFile?.mkdirs()
        marker.createNewFile()
        assertTrue(LegacyScheduleCleaner.runOnce(context))
        assertTrue(preferencesFile.exists())
        assertTrue(base + 1 in support.alarmTimes(LegacyScheduleCleaner.LEGACY_ACTION))
    }
}
