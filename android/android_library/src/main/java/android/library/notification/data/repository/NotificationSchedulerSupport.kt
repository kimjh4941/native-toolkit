package android.library.notification.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Parcel
import android.os.Parcelable
import android.util.Base64
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.NotificationSchedule
import androidx.core.content.edit
import kotlinx.parcelize.parcelableCreator
import org.json.JSONObject

internal data class ScheduledNotificationEntry(
    val command: AndroidNotificationCommand,
    val schedule: NotificationSchedule
)

internal object NotificationSchedulerSupport {
    const val actionShowScheduledNotification: String = "android.library.notification.action.SHOW_SCHEDULED"
    private const val prefName: String = "android.library.notification.scheduler"
    private const val prefKeyEntries: String = "entries"
    private const val jsonKeyCommand: String = "command"
    private const val jsonKeySchedule: String = "schedule"
    private const val scheme: String = "native-toolkit-notification"

    fun buildScheduleIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return Intent(context, ScheduledNotificationReceiver::class.java).apply {
            action = actionShowScheduledNotification
            `package` = context.packageName
            data = buildScheduleUri(context, command.content.id, command.content.tag)
            putExtra(Intent.EXTRA_SHORTCUT_ID, scheduleKey(command.content.id, command.content.tag))
            putExtra(EXTRA_NOTIFICATION_COMMAND, command.toPayload())
        }
    }

    fun scheduleKey(id: Int, tag: String?): String = "${tag ?: "untagged"}::$id"

    fun persist(context: Context, entry: ScheduledNotificationEntry) {
        val values = context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .getStringSet(prefKeyEntries, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()

        values.removeIf { JSONObject(it).optString(Intent.EXTRA_SHORTCUT_ID) == scheduleKey(entry.command.content.id, entry.command.content.tag) }
        values.add(
            JSONObject()
                .put(Intent.EXTRA_SHORTCUT_ID, scheduleKey(entry.command.content.id, entry.command.content.tag))
                .put(jsonKeyCommand, marshallParcelable(entry.command.toPayload()))
                .put(jsonKeySchedule, marshallParcelable(entry.schedule.toPayload()))
                .toString()
        )

        context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .edit {
                putStringSet(prefKeyEntries, values)
            }
    }

    fun remove(context: Context, id: Int, tag: String?) {
        val targetKey = scheduleKey(id, tag)
        val values = context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .getStringSet(prefKeyEntries, emptySet())
            ?.toMutableSet()
            ?: return

        val changed = values.removeIf { JSONObject(it).optString(Intent.EXTRA_SHORTCUT_ID) == targetKey }
        if (changed) {
            context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
                .edit {
                    putStringSet(prefKeyEntries, values)
                }
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .edit { clear() }
    }

    fun loadAll(context: Context): List<ScheduledNotificationEntry> {
        val values = context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .getStringSet(prefKeyEntries, emptySet())
            .orEmpty()

        return values.mapNotNull { value ->
            runCatching {
                val json = JSONObject(value)
                val command = unmarshallParcelable(
                    json.getString(jsonKeyCommand),
                    parcelableCreator<AndroidNotificationCommandPayload>()
                )?.toCommand()
                val schedule = unmarshallParcelable(
                    json.getString(jsonKeySchedule),
                    parcelableCreator<NotificationSchedulePayload>()
                )?.toDomain()
                if (command != null && schedule != null) {
                    ScheduledNotificationEntry(command = command, schedule = schedule)
                } else {
                    null
                }
            }.getOrNull()
        }
    }

    inline fun <reified T : Parcelable> Intent.parcelableExtra(key: String): T? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(key, T::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(key)
        }
    }

    private fun buildScheduleUri(context: Context, id: Int, tag: String?): Uri {
        return Uri.Builder()
            .scheme(scheme)
            .authority(context.packageName)
            .appendPath(tag ?: "untagged")
            .appendPath(id.toString())
            .build()
    }

    private fun marshallParcelable(value: Parcelable): String {
        val parcel = Parcel.obtain()
        return try {
            value.writeToParcel(parcel, 0)
            Base64.encodeToString(parcel.marshall(), Base64.NO_WRAP)
        } finally {
            parcel.recycle()
        }
    }

    private fun <T> unmarshallParcelable(encoded: String, creator: Parcelable.Creator<T>): T? {
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val parcel = Parcel.obtain()
        return try {
            parcel.unmarshall(bytes, 0, bytes.size)
            parcel.setDataPosition(0)
            creator.createFromParcel(parcel)
        } finally {
            parcel.recycle()
        }
    }
}

internal const val EXTRA_NOTIFICATION_COMMAND: String = "android.library.notification.extra.COMMAND"
