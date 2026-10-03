package com.jonghyunkim.android.nativetoolkit.example

import android.Manifest
import android.content.Context
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.data.repository.NotificationUseCases
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationSchedule
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryHost
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * First phase of the host-driven cases H-01 to H-03 (3.7 of the UI test design). Each method
 * schedules notifications through the Kotlin API and waits until the schedule is written; the
 * host script then updates or reboots the device and checks the notifications itself.
 *
 * This class does not clean up afterwards, on purpose: the schedules must survive.
 */
@CategoryHost
@RunWith(AndroidJUnit4::class)
class HostPhaseTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test
    fun h01_scheduleBeforeInstallReplace() {
        schedule(persisted = 9101, transient = 9102, delayMs = 120_000)
    }

    @Test
    fun h02_scheduleBeforeReboot() {
        schedule(persisted = 9101, transient = 9102, delayMs = 120_000)
    }

    @Test
    fun h03_scheduleThatComesDueDuringReboot() {
        schedule(persisted = 9103, transient = null, delayMs = 15_000)
    }

    private fun schedule(persisted: Int, transient: Int?, delayMs: Long) {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow").close()
        val useCases = NotificationUseCases(context)
        val triggerAt = System.currentTimeMillis() + delayMs
        val persistedResult = useCases.schedule(command(persisted, "Host persisted $persisted"), NotificationSchedule(triggerAtMillis = triggerAt, persistAcrossBoot = true))
        assertTrue("persisted schedule failed: $persistedResult", persistedResult.isSuccess)
        if (transient != null) {
            val transientResult = useCases.schedule(command(transient, "Host transient $transient"), NotificationSchedule(triggerAtMillis = triggerAt, persistAcrossBoot = false))
            assertTrue("transient schedule failed: $transientResult", transientResult.isSuccess)
        }
        assertTrue("schedule $persisted was not saved", useCases.isScheduled(context, persisted))
        // The library saves with apply(); commit() writes the whole map synchronously, so the
        // schedule is on disk before the host updates or reboots the device (3.7).
        context.getSharedPreferences(SCHEDULER_PREFERENCES, Context.MODE_PRIVATE).edit().commit()
        // Read by the host script from logcat to know when to check.
        Log.i(TAG, "HOST_TRIGGER_AT=$triggerAt")
    }

    private fun command(id: Int, title: String) = AndroidNotificationCommand(
        NotificationContent(
            id = id,
            title = title,
            message = "Host phase schedule",
            channel = NotificationChannel(id = "host_phase", name = "Host Phase", importance = 4)
        )
    )

    private companion object {
        const val SCHEDULER_PREFERENCES = "android.library.notification.scheduler"
        const val TAG = "HostPhaseTest"
    }
}
