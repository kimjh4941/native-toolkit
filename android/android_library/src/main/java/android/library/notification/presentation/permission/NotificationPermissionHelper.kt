package android.library.notification.presentation.permission

import android.Manifest
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Helper for notification permission and alarm settings.
 *
 * Provides permission checks, permission requests, and transitions to settings screens.
 *
 * @param activity [ComponentActivity] used for permission requests and settings navigation.
 */
class NotificationPermissionHelper(private val activity: ComponentActivity) {

    private var onPermissionResult: ((Boolean) -> Unit)? = null

    private val permissionLauncher = activity.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        onPermissionResult?.invoke(isGranted)
    }

    /**
     * Checks whether notification permission is granted.
     *
     * @return True if granted. Always true on Android 12 and below.
     */
    fun hasPermission(): Boolean {
        Log.d(TAG, "[hasPermission]")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /**
     * Checks whether app notifications are enabled.
     *
     * @return True if enabled.
     */
    fun areNotificationsEnabled(): Boolean {
        Log.d(TAG, "[areNotificationsEnabled]")
        return NotificationManagerCompat.from(activity).areNotificationsEnabled()
    }

    /**
     * Checks whether exact alarms can be scheduled.
     *
     * @return True if exact alarm scheduling is allowed.
     */
    fun canScheduleExactAlarms(): Boolean {
        Log.d(TAG, "[canScheduleExactAlarms]")
        return activity.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
    }

    /**
     * Checks whether notification permission can be requested (Android 13+ only).
     *
     * @return True on Android 13 and above.
     */
    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.TIRAMISU)
    fun canRequestPermission(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    /**
     * Checks whether the notification permission rationale should be shown.
     *
     * @return True if rationale should be shown.
     */
    fun shouldShowPermissionRationale(): Boolean {
        Log.d(TAG, "[shouldShowPermissionRationale]")
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
    }

    /**
     * Requests notification permission.
     *
     * Immediately calls callback(true) when permission is already granted or cannot be requested.
     *
     * @param callback Callback receiving the permission result.
     */
    fun requestPermission(callback: (Boolean) -> Unit) {
        Log.d(TAG, "[requestPermission]")
        if (!canRequestPermission() || hasPermission()) {
            callback(true)
            return
        }

        onPermissionResult = callback
        permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    /**
     * Opens notification settings.
     *
     * Navigates to app notification settings and falls back to app details settings when unavailable.
     *
     * @return True when navigation succeeds.
     */
    fun openNotificationSettings(): Boolean {
        Log.d(TAG, "[openNotificationSettings]")
        val openedNotificationSettings = startSafely(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                data = packageUri()
            }
        )

        return openedNotificationSettings || openAppDetailsSettings()
    }

    /**
     * Opens app details settings.
     *
     * @return True when navigation succeeds.
     */
    fun openAppDetailsSettings(): Boolean {
        Log.d(TAG, "[openAppDetailsSettings]")
        return startSafely(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = packageUri()
            }
        )
    }

    /**
     * Opens exact alarm settings.
     *
     * Falls back to app details settings when unavailable.
     *
     * @return True when navigation succeeds.
     */
    fun openExactAlarmSettings(): Boolean {
        Log.d(TAG, "[openExactAlarmSettings]")
        val openedExactAlarmSettings = startSafely(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = packageUri()
            }
        )

        return openedExactAlarmSettings || openAppDetailsSettings()
    }

    companion object {
        private const val TAG = "NotificationPermissionHelper"
    }

    private fun startSafely(intent: Intent): Boolean {
        return try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun packageUri(): Uri {
        return Uri.fromParts("package", activity.packageName, null)
    }
}
