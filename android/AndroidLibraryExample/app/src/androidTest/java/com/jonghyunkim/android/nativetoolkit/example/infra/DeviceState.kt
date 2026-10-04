package com.jonghyunkim.android.nativetoolkit.example.infra

import android.Manifest
import android.app.Instrumentation
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleForegroundService
import com.jonghyunkim.nativetoolkit.notification.presentation.progress.ProgressForegroundNotifications
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until

/**
 * Device state and cleanup between tests (sections 3.5 and 4).
 *
 * Tests only move state in the "allow" direction. Revoking the notification permission or the
 * exact alarm permission kills the app process, so the host script does that (U-5).
 */
class DeviceState(private val instrumentation: Instrumentation, private val device: UiDevice) {

    private val context = instrumentation.targetContext
    private val packageName = context.packageName

    /** Grants what the ordinary test cases rely on. */
    fun allowAll() {
        instrumentation.uiAutomation.grantRuntimePermission(packageName, Manifest.permission.POST_NOTIFICATIONS)
        shell("appops set $packageName SCHEDULE_EXACT_ALARM allow")
        shell("appops set $packageName USE_FULL_SCREEN_INTENT allow")
    }

    /**
     * Stops the sample's foreground services, cancels its schedules, removes the direct share
     * shortcut and clears its notifications, then waits until none are left.
     */
    fun cleanup() {
        closeSystemWindows()
        runCatching { ProgressForegroundNotifications.stop(context) }
        runCatching { context.startService(CallStyleForegroundService.createStopIntent(context)) }
        val useCases = NotificationUseCases(context)
        for (id in SCHEDULED_IDS) runCatching { useCases.cancelScheduled(id, null) }
        runCatching { ShortcutManagerCompat.removeLongLivedShortcuts(context, listOf(DIRECT_SHARE_ID)) }
        NotificationManagerCompat.from(context).cancelAll()
        ActiveNotifications(context).let { notifications ->
            val end = System.currentTimeMillis() + 15_000
            while (notifications.sampleIds().isNotEmpty() && System.currentTimeMillis() < end) {
                NotificationManagerCompat.from(context).cancelAll()
                Thread.sleep(200)
            }
        }
    }

    /** Closes the shade, the Sharesheet and the share target app if any is in front. */
    fun closeSystemWindows() {
        repeat(3) {
            val front = device.currentPackageName
            if (front == packageName || front == null) return
            if (front == "com.android.systemui") {
                instrumentation.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
            } else {
                device.pressBack()
            }
            device.wait(Until.hasObject(By.pkg(packageName).depth(0)), 2_000)
        }
    }

    /** Brings the sample back to the front with its launcher intent. */
    fun bringSampleToFront() {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)!!.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(packageName).depth(0)), 10_000)
    }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).close()
    }

    companion object {
        /** Notification IDs that tests schedule: the sample's 15-second schedule and the host cases. */
        val SCHEDULED_IDS = listOf(1010, 9101, 9102, 9103)
        const val DIRECT_SHARE_ID = "sample_1"
    }
}
