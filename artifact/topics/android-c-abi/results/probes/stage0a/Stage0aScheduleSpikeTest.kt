package com.jonghyunkim.android.nativetoolkit.example.spike

import android.Manifest
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.data.repository.NotificationUseCases
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationSchedule
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Throwaway spike for stage 0a (not committed): schedules one persisted and one transient
 * notification so the host can update or reboot the device and check what survives.
 * The delay is passed with `-e delaySeconds <n>` (default 90).
 */
@RunWith(AndroidJUnit4::class)
class Stage0aScheduleSpikeTest {

    @Test
    fun spike10_scheduleForHostPhase() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val delaySeconds = InstrumentationRegistry.getArguments().getString("delaySeconds")?.toLong() ?: 90L
        Log.d(TAG, "[spike10_scheduleForHostPhase] delaySeconds: $delaySeconds")
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow").close()
        val useCases = NotificationUseCases(context)
        val channel = NotificationChannel(id = "spike_channel", name = "Spike Channel", importance = 4)
        val triggerAt = System.currentTimeMillis() + delaySeconds * 1_000L
        val persisted = useCases.schedule(
            AndroidNotificationCommand(NotificationContent(id = 9001, title = "Spike persisted", message = "persistAcrossBoot=true", channel = channel)),
            NotificationSchedule(triggerAtMillis = triggerAt, persistAcrossBoot = true)
        )
        val transient = useCases.schedule(
            AndroidNotificationCommand(NotificationContent(id = 9002, title = "Spike transient", message = "persistAcrossBoot=false", channel = channel)),
            NotificationSchedule(triggerAtMillis = triggerAt, persistAcrossBoot = false)
        )
        Log.d(TAG, "[spike10] triggerAt=$triggerAt persisted=$persisted transient=$transient")
        Log.d(TAG, "[spike10] isScheduled 9001=${useCases.isScheduled(context, 9001)} 9002=${useCases.isScheduled(context, 9002)}")
        Thread.sleep(2_000)
        Log.d(TAG, "[spike10] after wait isScheduled 9001=${useCases.isScheduled(context, 9001)}")
        assertTrue(persisted.isSuccess && transient.isSuccess)
    }

    private companion object {
        const val TAG = "Spike0a"
    }
}
