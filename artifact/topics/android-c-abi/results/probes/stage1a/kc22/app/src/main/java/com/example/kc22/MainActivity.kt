package com.example.kc22

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.jonghyunkim.nativetoolkit.clipboard.data.repository.ClipboardUseCases
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("KC22", "kotlin=${KotlinVersion.CURRENT} hasClip=${ClipboardUseCases(this).hasClip()}")
        // The schedule is saved as a Parcel (Parcelize) and read back by isScheduled (parcelableCreator).
        val useCases = NotificationUseCases(this)
        val command = AndroidNotificationCommand(
            NotificationContent(
                id = 7777, title = "KC22", message = "probe",
                channel = NotificationChannel(id = "kc22", name = "KC22", importance = 3)
            )
        )
        val result = useCases.schedule(command, NotificationSchedule(triggerAtMillis = System.currentTimeMillis() + 3_600_000, persistAcrossBoot = true))
        Log.i("KC22", "schedule=$result isScheduled=${useCases.isScheduled(this, 7777)}")
        Log.i("KC22", "cancel=${useCases.cancelScheduled(7777)} isScheduledAfterCancel=${useCases.isScheduled(this, 7777)}")
    }
}
