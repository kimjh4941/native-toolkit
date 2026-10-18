package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Parcelable
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import org.json.JSONObject

/**
 * The extras of a scheduled notification's Alarm (Kotlin API design 8.6).
 *
 * The extra names are compatibility identifiers: Alarms set by one version are delivered to the
 * next one. No library class name enters the extras: the command is JSON, and its Intents and
 * Bitmaps are framework Parcelables.
 */
internal object ScheduledAlarmExtras {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledAlarmExtras"

    const val COMMAND_JSON: String = "com.jonghyunkim.nativetoolkit.notification.extra.COMMAND_JSON"
    const val INTENTS: String = "com.jonghyunkim.nativetoolkit.notification.extra.INTENTS"
    const val BITMAPS: String = "com.jonghyunkim.nativetoolkit.notification.extra.BITMAPS"
    const val GENERATION: String = "com.jonghyunkim.nativetoolkit.notification.extra.GENERATION"

    /**
     * The Alarm intent with the command and the generation in its extras.
     *
     * @param context Any Context.
     * @param command The command.
     * @param generation The generation.
     */
    fun intent(context: Context, command: AndroidNotificationCommand, generation: Long): Intent {
        Log.d(TAG, "[intent] id: ${command.content.id}, tag: ${command.content.tag}, generation: $generation")
        val slots = ParcelableBinarySlots()
        val json = NotificationJsonCodec.encodeCommand(command, slots).toString()
        return NotificationSchedulerSupport.scheduleIntent(context, command.content.id, command.content.tag)
            .putExtra(COMMAND_JSON, json)
            .putParcelableArrayListExtra(INTENTS, slots.intents)
            .putParcelableArrayListExtra(BITMAPS, slots.bitmaps)
            .putExtra(GENERATION, generation)
    }

    /**
     * Reads the generation of an Alarm intent, or `null`.
     *
     * @param intent The received intent.
     */
    fun generationOf(intent: Intent): Long? {
        Log.d(TAG, "[generationOf] intent: $intent")
        return try {
            if (intent.hasExtra(GENERATION)) intent.getLongExtra(GENERATION, 0L) else null
        } catch (e: Exception) {
            Log.e(TAG, "[generationOf] cannot read the extras", e)
            null
        }
    }

    /**
     * Reads the command of an Alarm intent.
     *
     * @param intent The received intent.
     * @throws Exception When the extras are missing or unreadable.
     */
    fun commandOf(intent: Intent): AndroidNotificationCommand {
        Log.d(TAG, "[commandOf] intent: $intent")
        val json = intent.getStringExtra(COMMAND_JSON) ?: throw IllegalArgumentException("no command extra")
        val intents = parcelableList(intent, INTENTS, Intent::class.java)
        val bitmaps = parcelableList(intent, BITMAPS, Bitmap::class.java)
        return NotificationJsonCodec.decodeCommand(JSONObject(json), ParcelableBinarySlots(intents, bitmaps))
    }

    private fun <T : Parcelable> parcelableList(intent: Intent, key: String, type: Class<T>): ArrayList<T> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(key, type)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(key)
        } ?: ArrayList()
}
