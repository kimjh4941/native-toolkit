package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.app.Activity
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationSettingsPort
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget

/**
 * Exact alarm queries and settings screens from any Context (Kotlin API design 8.7).
 *
 * An Activity opens the screen in its own task. Any other Context adds `FLAG_ACTIVITY_NEW_TASK`,
 * as the Unity bridge does. Whether the app is in the foreground is not checked here; the C ABI
 * receiver checks it before calling (C ABI design C-4).
 *
 * @param context The Context to open screens from.
 */
internal class AndroidNotificationSettingsGateway(private val context: Context) : NotificationSettingsPort {

    override fun canScheduleExactAlarms(): Boolean {
        Log.d(TAG, "[canScheduleExactAlarms]")
        return context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
    }

    override fun open(target: NotificationSettingsTarget): NotificationSettingsOpenResult {
        Log.d(TAG, "[open] target: $target")
        val primary = when (target) {
            // No data URI here: the settings app's filter for this action has no data, so a
            // package: URI makes the intent match nothing and always falls back. The Unity bridge
            // and NotificationPermissionHelper add one; they keep that until stage 3 (K-9).
            NotificationSettingsTarget.NOTIFICATIONS -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            NotificationSettingsTarget.EXACT_ALARM -> Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(packageUri())
            NotificationSettingsTarget.APP_DETAILS -> appDetailsIntent()
        }
        if (start(primary)) return NotificationSettingsOpenResult.OPENED
        if (target == NotificationSettingsTarget.APP_DETAILS) return NotificationSettingsOpenResult.FAILED
        return if (start(appDetailsIntent())) {
            NotificationSettingsOpenResult.OPENED_FALLBACK
        } else {
            NotificationSettingsOpenResult.FAILED
        }
    }

    private fun appDetailsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(packageUri())

    private fun packageUri(): Uri = Uri.fromParts("package", context.packageName, null)

    private fun start(intent: Intent): Boolean {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "[start] intent: $intent", e)
            false
        } catch (e: SecurityException) {
            Log.w(TAG, "[start] intent: $intent", e)
            false
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.AndroidNotificationSettingsGateway"
    }
}
