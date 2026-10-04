package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.data.repository.JsonNotificationScheduleStore
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleIdentity
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleTestHooks
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationEntry
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.testing.ScheduleTestSupport
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-12 and IT-13 of the Kotlin API design: the schedule flow of 8.6 and its writes.
@RunWith(AndroidJUnit4::class)
class ScheduleFlowTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val support = ScheduleTestSupport(instrumentation)
    private val useCases = NotificationUseCases(context)
    private val store = JsonNotificationScheduleStore(context)
    private val channel = NotificationChannel(id = "ntk_it_schedule", name = "IT schedule", importance = 4)
    private val usedKeys: MutableSet<Pair<Int, String?>> = Collections.synchronizedSet(mutableSetOf())
    private var registration: EventHub.Registration? = null

    @Before
    fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        support.shell("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow")
        useCases.createChannel(channel)
        clearAll()
    }

    @After
    fun tearDown() {
        ScheduleTestHooks.reset()
        instrumentation.runOnMainSync { registration?.remove() }
        clearAll()
    }

    private fun clearAll() {
        synchronized(usedKeys) { usedKeys.toList() }.forEach { (id, tag) -> useCases.cancelScheduled(id, tag) }
        useCases.cancelAllScheduled()
        File(File(context.filesDir, "ntk"), JsonNotificationScheduleStore.FILE_NAME).delete()
        context.getSystemService(NotificationManager::class.java).cancelAll()
    }

    private fun command(id: Int, tag: String? = null, title: String = "Schedule $id") =
        AndroidNotificationCommand(NotificationContent(id = id, title = title, message = "IT-12", tag = tag, channel = channel))
            .also { usedKeys += id to tag }

    private fun future(offsetMs: Long = 600_000, persist: Boolean = true) =
        NotificationSchedule(triggerAtMillis = System.currentTimeMillis() + offsetMs, persistAcrossBoot = persist)

    private fun past(persist: Boolean = true) =
        NotificationSchedule(triggerAtMillis = System.currentTimeMillis() - 1_000, persistAcrossBoot = persist)

    private fun entry(
        id: Int,
        schedule: NotificationSchedule,
        generation: Long,
        lossy: Boolean = false,
        installId: String = ScheduleIdentity.installId(context),
        bootCount: Int = ScheduleIdentity.bootCount(context)
    ) = ScheduledNotificationEntry(command(id), schedule, generation, lossy, installId, bootCount)

    // Cancels the Alarm without touching the saved schedules, as the OS does on a reboot.
    private fun dropAlarm(id: Int, tag: String? = null) {
        val pendingIntent = support.schedulePendingIntent(id, tag) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun shownInside(block: (NotificationShownProbe) -> Unit): NotificationShownProbe {
        val probe = NotificationShownProbe()
        instrumentation.runOnMainSync {
            registration = NotificationEvents.shown.addListener { event, _ ->
                probe.events.add(event.notificationId to useCases.isScheduled(context, event.notificationId, event.tag))
            }
        }
        block(probe)
        return probe
    }

    private class NotificationShownProbe {
        val events = LinkedBlockingQueue<Pair<Int, Boolean>>()
        fun next(): Pair<Int, Boolean> = events.poll(10, TimeUnit.SECONDS) ?: throw AssertionError("no shown event within 10 s")
    }

    // --- 8.6 table rows ---

    @Test
    fun pastTime_sendsAtOnce_andRemovesTheSavedSchedule() {
        val old = future()
        assertTrue(useCases.schedule(command(1201), old).isSuccess)
        assertTrue(useCases.isScheduled(context, 1201))
        assertTrue(useCases.schedule(command(1201), past()).isSuccess)
        assertTrue(support.waitPosted(1201, null))
        assertFalse(useCases.isScheduled(context, 1201))
    }

    @Test
    fun futurePersisted_setsTheAlarm_andSaves() {
        val schedule = future()
        assertTrue(useCases.schedule(command(1202), schedule).isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
        assertTrue(useCases.isScheduled(context, 1202))
    }

    @Test
    fun futureNotPersisted_setsTheAlarm_andRemovesAnEarlierSave() {
        assertTrue(useCases.schedule(command(1203), future()).isSuccess)
        val schedule = future(persist = false)
        assertTrue(useCases.schedule(command(1203), schedule).isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
        assertFalse(useCases.isScheduled(context, 1203))
    }

    @Test
    fun cancelScheduled_cancelsTheAlarm_andRemoves() {
        val schedule = future()
        useCases.schedule(command(1204, "t"), schedule)
        assertTrue(useCases.cancelScheduled(1204, "t").isSuccess)
        assertFalse(support.isAlarmSet(schedule.triggerAtMillis))
        assertFalse(useCases.isScheduled(context, 1204, "t"))
    }

    @Test
    fun cancelAllScheduled_cancelsEverySavedAlarm_andClears() {
        val first = future(600_000)
        val second = future(700_000)
        useCases.schedule(command(1205), first)
        useCases.schedule(command(1206, "t"), second)
        assertTrue(useCases.cancelAllScheduled().isSuccess)
        assertFalse(support.isAlarmSet(first.triggerAtMillis))
        assertFalse(support.isAlarmSet(second.triggerAtMillis))
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun firingPersisted_shows_removes_andIsScheduledIsFalseInsideShown() {
        useCases.schedule(command(1207), future())
        val probe = shownInside { support.fire(1207, null) }
        assertEquals(1207 to false, probe.next())
        assertTrue(support.waitPosted(1207, null))
    }

    @Test
    fun firingNotPersisted_shows() {
        useCases.schedule(command(1208), future(persist = false))
        support.fire(1208, null)
        assertTrue(support.waitPosted(1208, null))
    }

    @Test
    fun realAlarm_firesAndShows() {
        val schedule = future(offsetMs = 3_000)
        useCases.schedule(command(1209), schedule)
        assertTrue(support.waitPosted(1209, null, timeoutMs = 30_000))
        assertFalse(useCases.isScheduled(context, 1209))
    }

    @Test
    fun untaggedTag_andNoTag_areTheSameSchedule() {
        useCases.schedule(command(1210, null), future())
        useCases.schedule(command(1210, "untagged"), future())
        assertEquals(1, store.loadAll().size)
        assertEquals("untagged", store.loadAll().single().command.content.tag)
        useCases.cancelScheduled(1210, null)
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun isScheduled_comparesTheTagAsBefore() {
        useCases.schedule(command(1211, "a"), future())
        assertTrue(useCases.isScheduled(context, 1211, "a"))
        assertFalse(useCases.isScheduled(context, 1211, null))
        assertFalse(useCases.isScheduled(context, 1211, "b"))
    }

    // --- generations and the lock ---

    @Test
    fun rescheduleWhileTheReceiverSends_keepsTheNewSchedule_andShownComesAfterTheRemoval() {
        useCases.schedule(command(1212, title = "old"), future())
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        ScheduleTestHooks.beforeSend = { sent ->
            if (sent.content.id == 1212 && sent.content.title == "old") {
                entered.countDown()
                release.await(10, TimeUnit.SECONDS)
            }
        }
        val probe = shownInside { support.fire(1212, null) }
        assertTrue(entered.await(10, TimeUnit.SECONDS))
        val newer = future(800_000)
        assertTrue(useCases.schedule(command(1212, title = "new"), newer).isSuccess)
        val newGeneration = store.get(1212, null)!!.generation
        assertTrue(probe.events.isEmpty())
        release.countDown()

        // The removal is decided before shown: the new schedule is still saved when shown comes.
        assertEquals(1212 to true, probe.next())
        assertEquals(newGeneration, store.get(1212, null)?.generation)
        assertEquals("new", store.get(1212, null)?.command?.content?.title)
        assertTrue(support.isAlarmSet(newer.triggerAtMillis))
    }

    @Test
    fun twoThreadsSchedulingTheSameKey_leaveTheAlarmAndTheSaveWithTheSameGeneration() {
        val start = CountDownLatch(1)
        val threads = (0 until 2).map { n ->
            Thread {
                start.await()
                repeat(20) { i -> useCases.schedule(command(1213, title = "t$n-$i"), future(600_000L + i)) }
            }.apply { start() }
        }
        start.countDown()
        threads.forEach { it.join(30_000) }
        val saved = store.get(1213, null)
        assertNotNull(saved)
        // Firing removes the save only when the Alarm carries the saved generation.
        val probe = shownInside { support.fire(1213, null) }
        assertEquals(1213 to false, probe.next())
        assertNull(store.get(1213, null))
    }

    @Test
    fun rescheduleDuringRestore_isNotOverwrittenByTheOldEntry() {
        val generation = ScheduleIdentity.newGeneration()
        store.put(entry(1214, past(), ScheduleIdentity.newGeneration()))
        store.put(entry(1215, future(), generation))
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        ScheduleTestHooks.beforeSend = { sent ->
            if (sent.content.id == 1214) {
                entered.countDown()
                release.await(10, TimeUnit.SECONDS)
            }
        }
        val restore = Thread { useCases.restoreScheduled() }.apply { start() }
        assertTrue(entered.await(10, TimeUnit.SECONDS))
        val newer = future(900_000)
        useCases.schedule(command(1215, title = "new"), newer)
        val newGeneration = store.get(1215, null)!!.generation
        assertNotEquals(generation, newGeneration)
        release.countDown()
        restore.join(10_000)

        assertEquals(newGeneration, store.get(1215, null)?.generation)
        // The Alarm still carries the new generation: firing removes the save.
        val probe = shownInside { support.fire(1215, null) }
        assertEquals(1215 to false, probe.next())
    }

    @Test
    fun cancelDuringRestore_skipsThePastEntry() {
        store.put(entry(1223, past(), ScheduleIdentity.newGeneration()))
        store.put(entry(1224, past(), ScheduleIdentity.newGeneration()))
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        ScheduleTestHooks.beforeSend = { sent ->
            if (sent.content.id == 1223) {
                entered.countDown()
                release.await(10, TimeUnit.SECONDS)
            }
        }
        val restore = Thread { useCases.restoreScheduled() }.apply { start() }
        assertTrue(entered.await(10, TimeUnit.SECONDS))
        useCases.cancelScheduled(1224)
        release.countDown()
        restore.join(10_000)

        assertTrue(support.waitPosted(1223, null))
        assertTrue(support.waitPosted(1224, null, posted = false, timeoutMs = 0))
        Thread.sleep(1_000)
        assertTrue(support.waitPosted(1224, null, posted = false, timeoutMs = 0))
    }

    // --- restoreScheduled (MY_PACKAGE_REPLACED, BOOT_COMPLETED) ---

    @Test
    fun restore_notLossyFuture_isSetAgain_withTheSavedGeneration() {
        val schedule = future()
        store.put(entry(1216, schedule, ScheduleIdentity.newGeneration()))
        dropAlarm(1216)
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
        val probe = shownInside { support.fire(1216, null) }
        assertEquals(1216 to false, probe.next())
    }

    @Test
    fun restore_lossyFutureWithALiveAlarm_isNotSetAgain() {
        assumeTrue("the boot count is not readable", ScheduleIdentity.bootCount(context) != -1)
        val schedule = future()
        store.put(entry(1217, schedule, ScheduleIdentity.newGeneration(), lossy = true))
        dropAlarm(1217)
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertFalse(support.isAlarmSet(schedule.triggerAtMillis))
        assertTrue(useCases.isScheduled(context, 1217))
    }

    @Test
    fun restore_lossyFutureAfterAReboot_isSetAgain() {
        val schedule = future()
        store.put(entry(1218, schedule, ScheduleIdentity.newGeneration(), lossy = true, bootCount = ScheduleIdentity.bootCount(context) - 1))
        dropAlarm(1218)
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
    }

    @Test
    fun restore_lossyFutureAfterAReinstall_isSetAgain() {
        val schedule = future()
        store.put(entry(1219, schedule, ScheduleIdentity.newGeneration(), lossy = true, installId = "another-install"))
        dropAlarm(1219)
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
    }

    @Test
    fun restore_lossyWithUnknownBootCount_isSetAgain() {
        val schedule = future()
        store.put(entry(1220, schedule, ScheduleIdentity.newGeneration(), lossy = true, bootCount = -1))
        dropAlarm(1220)
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
    }

    @Test
    fun restore_pastEntries_lossyOrNot_areSentAndRemoved() {
        store.put(entry(1221, past(), ScheduleIdentity.newGeneration()))
        store.put(entry(1222, past(), ScheduleIdentity.newGeneration(), lossy = true))
        assertTrue(useCases.restoreScheduled().isSuccess)
        assertTrue(support.waitPosted(1221, null))
        assertTrue(support.waitPosted(1222, null))
        assertTrue(store.loadAll().isEmpty())
    }

    // --- IT-13: writes ---

    @Test
    fun scheduleWriteFails_isAFailure_andTheAlarmStaysSet() {
        val schedule = future()
        ScheduleTestHooks.beforeWrite = { throw IOException("injected") }
        val result = useCases.schedule(command(1301), schedule)
        assertTrue(result.exceptionOrNull() is IOException)
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
        assertFalse(useCases.isScheduled(context, 1301))
    }

    @Test
    fun cancelWriteFails_isAFailure_theAlarmIsCanceled_andTheSaveStays() {
        val schedule = future()
        useCases.schedule(command(1302), schedule)
        ScheduleTestHooks.beforeWrite = { throw IOException("injected") }
        val result = useCases.cancelScheduled(1302)
        assertTrue(result.exceptionOrNull() is IOException)
        assertFalse(support.isAlarmSet(schedule.triggerAtMillis))
        ScheduleTestHooks.reset()
        assertTrue(useCases.isScheduled(context, 1302))
    }

    @Test
    fun cancelAllWriteFails_isAFailure_theAlarmsAreCanceled_andTheSavesStay() {
        val schedule = future()
        useCases.schedule(command(1303), schedule)
        ScheduleTestHooks.beforeWrite = { throw IOException("injected") }
        assertTrue(useCases.cancelAllScheduled().exceptionOrNull() is IOException)
        assertFalse(support.isAlarmSet(schedule.triggerAtMillis))
        ScheduleTestHooks.reset()
        assertTrue(useCases.isScheduled(context, 1303))
    }

    @Test
    fun alarmFails_isAFailure_andTheSaveDoesNotChange() {
        val first = future()
        useCases.schedule(command(1304, title = "first"), first)
        ScheduleTestHooks.beforeAlarm = { throw SecurityException("injected") }
        val result = useCases.schedule(command(1304, title = "second"), future(700_000))
        assertTrue(result.exceptionOrNull() is SecurityException)
        assertEquals("first", store.get(1304, null)?.command?.content?.title)
    }

    @Test
    fun restoreWriteFails_goesOnWithTheOthers_andFailsAtTheEnd() {
        store.put(entry(1305, past(), ScheduleIdentity.newGeneration()))
        val schedule = future()
        store.put(entry(1306, schedule, ScheduleIdentity.newGeneration()))
        dropAlarm(1306)
        ScheduleTestHooks.beforeWrite = { throw IOException("injected") }
        val result = useCases.restoreScheduled()
        assertTrue(result.exceptionOrNull() is IOException)
        assertTrue(support.waitPosted(1305, null))
        assertTrue(support.isAlarmSet(schedule.triggerAtMillis))
    }

    @Test
    fun scheduleReturns_afterTheFileIsWritten() {
        useCases.schedule(command(1307), future())
        val file = File(File(context.filesDir, "ntk"), JsonNotificationScheduleStore.FILE_NAME)
        assertTrue(file.readText().contains("\"id\":1307"))
    }
}
