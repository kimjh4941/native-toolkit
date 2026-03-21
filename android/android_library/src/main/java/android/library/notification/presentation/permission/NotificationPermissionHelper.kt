package android.library.notification.presentation.permission

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class NotificationPermissionHelper(private val activity: ComponentActivity) {

    private var onPermissionResult: ((Boolean) -> Unit)? = null

    private val permissionLauncher = activity.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        onPermissionResult?.invoke(isGranted)
    }

    fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun areNotificationsEnabled(): Boolean {
        return NotificationManagerCompat.from(activity).areNotificationsEnabled()
    }

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.TIRAMISU)
    fun canRequestPermission(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    fun shouldShowPermissionRationale(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun requestPermission(callback: (Boolean) -> Unit) {
        if (!canRequestPermission() || hasPermission()) {
            callback(true)
            return
        }

        onPermissionResult = callback
        permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun openNotificationSettings(): Boolean {
        val openedNotificationSettings = startSafely(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                data = packageUri()
            }
        )

        return openedNotificationSettings || openAppDetailsSettings()
    }

    fun openAppDetailsSettings(): Boolean {
        return startSafely(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = packageUri()
            }
        )
    }

    fun openExactAlarmSettings(): Boolean {
        val openedExactAlarmSettings = startSafely(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = packageUri()
            }
        )

        return openedExactAlarmSettings || openAppDetailsSettings()
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
