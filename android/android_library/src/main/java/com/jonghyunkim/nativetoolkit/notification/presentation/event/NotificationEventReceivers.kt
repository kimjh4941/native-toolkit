package com.jonghyunkim.nativetoolkit.notification.presentation.event

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * Receives notification events that do not open the app (Kotlin API design 8.5). Its class name is
 * a compatibility identifier: scheduled notifications store it.
 */
internal class NotificationEventReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent")
        val event = NotificationEventIntents.parse(intent) ?: return
        NotificationEvents.interactions.emit(event)
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventReceiver"
    }
}

/**
 * Receives notification events that open the app (Kotlin API design 8.5).
 *
 * Android 12 and later do not let a broadcast started from a notification open an Activity while
 * the app is in the background (the notification trampoline restriction), so taps that open the app
 * come here as an Activity. It has no UI (`Theme.NoDisplay`): it delivers the event, opens the
 * app's launch Activity like the launcher does, and finishes before it would resume. Its class name
 * is a compatibility identifier.
 */
internal class NotificationLaunchActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        try {
            if (savedInstanceState == null) {
                NotificationEventIntents.parse(intent)?.let { NotificationEvents.interactions.emit(it) }
                packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                    startActivity(launch)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[onCreate] savedInstanceState: $savedInstanceState", e)
        } finally {
            // Theme.NoDisplay requires finishing before onResume.
            finish()
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationLaunchActivity"
    }
}
