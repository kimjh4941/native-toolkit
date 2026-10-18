package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationShown
import java.io.IOException

/**
 * Shows a scheduled notification when its Alarm fires (Kotlin API design 8.6). The class name is
 * a compatibility identifier: Alarms set by one version are delivered to the next one.
 */
internal class ScheduledNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "[onReceive] intent: $intent")
        val appContext = context.applicationContext
        val generation = ScheduledAlarmExtras.generationOf(intent)
        val command: AndroidNotificationCommand = try {
            ScheduledAlarmExtras.commandOf(intent)
        } catch (e: Exception) {
            Log.e(TAG, "[onReceive] cannot read the scheduled notification; not showing it", e)
            NotificationSchedulerSupport.idAndTagOf(intent)?.let { (id, tag) -> removeSaved(appContext, id, tag, generation) }
            return
        }

        val repository: NotificationCommandRepository = NotificationRepositoryImpl(appContext)
        repository.send(command)
        removeSaved(appContext, command.content.id, command.content.tag, generation)

        NotificationEvents.shown.emit(
            NotificationShown(command.content.id, command.content.tag, command.content.channel.id)
        )
    }

    // Removes the saved schedule only when it is still the one this Alarm was set for.
    private fun removeSaved(context: Context, id: Int, tag: String?, generation: Long?) {
        Log.d(TAG, "[removeSaved] id: $id, tag: $tag, generation: $generation")
        if (generation == null) return
        try {
            JsonNotificationScheduleStore(context).removeIfGeneration(id, tag, generation)
        } catch (e: IOException) {
            Log.e(TAG, "[removeSaved] could not remove the saved schedule; id: $id, tag: $tag", e)
        }
    }

    companion object {
        private const val TAG = "ScheduledNotificationReceiver"
    }
}
