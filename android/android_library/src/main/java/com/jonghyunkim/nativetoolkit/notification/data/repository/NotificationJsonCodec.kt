package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCallPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import com.jonghyunkim.nativetoolkit.notification.application.model.RemoteViewAction
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCallPerson
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCallType
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCustomViewStyleData
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationMessage
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationProgress
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationStyle
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Where a codec puts the parts of a command that are not plain data: Intents and Bitmaps
 * (Kotlin API design 8.6).
 */
internal interface NotificationBinarySlots {
    /** Returns the JSON value that stands for [intent]. */
    fun putIntent(intent: Intent): Any

    /** Returns the JSON value that stands for [bitmap]. */
    fun putBitmap(bitmap: Bitmap): Any

    /** Returns the Intent that [value] stands for. */
    fun intent(value: Any): Intent

    /** Returns the Bitmap that [value] stands for. */
    fun bitmap(value: Any): Bitmap
}

/**
 * The storage form (README D-11): Intents as `Intent.toUri` strings and Bitmaps as PNG in Base64.
 * Records whether `toUri` drops anything ([lossy]).
 */
internal class StoredBinarySlots : NotificationBinarySlots {

    /** Whether an Intent had something that `toUri` does not keep. */
    var lossy: Boolean = false
        private set

    override fun putIntent(intent: Intent): Any {
        Log.d(TAG, "[putIntent] action: ${intent.action}, component: ${intent.component}")
        val dropped = droppedByToUri(intent)
        if (dropped.isNotEmpty()) {
            lossy = true
            // Keys only: extra values may be secret (log redaction rule).
            Log.w(TAG, "[putIntent] toUri drops: $dropped")
        }
        return intent.toUri(Intent.URI_INTENT_SCHEME)
    }

    override fun putBitmap(bitmap: Bitmap): Any {
        Log.d(TAG, "[putBitmap] width: ${bitmap.width}, height: ${bitmap.height}")
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    // The storage file is private to the library, so the URI permission flags may come back too.
    override fun intent(value: Any): Intent {
        Log.d(TAG, "[intent] valueLength: ${(value as? String)?.length}")
        return Intent.parseUri(value as String, Intent.URI_INTENT_SCHEME or Intent.URI_ALLOW_UNSAFE)
    }

    override fun bitmap(value: Any): Bitmap {
        Log.d(TAG, "[bitmap] valueLength: ${(value as? String)?.length}")
        val bytes = Base64.decode(value as String, Base64.NO_WRAP)
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("unreadable bitmap")
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.StoredBinarySlots"

        private val KEPT_EXTRA_TYPES = setOf(
            String::class.java, java.lang.Boolean::class.java, java.lang.Byte::class.java,
            java.lang.Character::class.java, java.lang.Short::class.java, java.lang.Integer::class.java,
            java.lang.Long::class.java, java.lang.Float::class.java, java.lang.Double::class.java
        )

        /** The extra keys (and `clipData`) that `Intent.toUri` does not keep. */
        fun droppedByToUri(intent: Intent): List<String> {
            Log.d(TAG, "[droppedByToUri] action: ${intent.action}")
            val dropped = mutableListOf<String>()
            if (intent.clipData != null) dropped += "clipData"
            val extras = intent.extras ?: return dropped
            for (key in extras.keySet()) {
                @Suppress("DEPRECATION")
                val value = extras.get(key)
                if (value != null && value.javaClass !in KEPT_EXTRA_TYPES) dropped += key
            }
            return dropped
        }
    }
}

/**
 * The Alarm form (Kotlin API design 8.6): Intents and Bitmaps stay framework Parcelables in two
 * lists, and the JSON refers to them by index. No library class name enters the Alarm.
 */
internal class ParcelableBinarySlots(
    val intents: ArrayList<Intent> = ArrayList(),
    val bitmaps: ArrayList<Bitmap> = ArrayList()
) : NotificationBinarySlots {

    override fun putIntent(intent: Intent): Any {
        Log.d(TAG, "[putIntent] action: ${intent.action}, component: ${intent.component}")
        intents += intent
        return JSONObject().put(KEY_INTENT, intents.size - 1)
    }

    override fun putBitmap(bitmap: Bitmap): Any {
        Log.d(TAG, "[putBitmap] width: ${bitmap.width}, height: ${bitmap.height}")
        bitmaps += bitmap
        return JSONObject().put(KEY_BITMAP, bitmaps.size - 1)
    }

    override fun intent(value: Any): Intent {
        Log.d(TAG, "[intent] value: $value")
        return intents[(value as JSONObject).getInt(KEY_INTENT)]
    }

    override fun bitmap(value: Any): Bitmap {
        Log.d(TAG, "[bitmap] value: $value")
        return bitmaps[(value as JSONObject).getInt(KEY_BITMAP)]
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.ParcelableBinarySlots"
        private const val KEY_INTENT = "\$intent"
        private const val KEY_BITMAP = "\$bitmap"
    }
}

/**
 * Converts notification commands and schedules to JSON and back (Kotlin API design 8.6).
 *
 * Version rule: readers ignore unknown fields and use the default for missing ones. Adding fields
 * does not change [VERSION]; only an incompatible change does, and then the old reader stays.
 */
internal object NotificationJsonCodec {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationJsonCodec"

    /** The current format version. */
    const val VERSION: Int = 1

    /**
     * Encodes [command].
     *
     * @param command The command.
     * @param slots Where Intents and Bitmaps go.
     */
    fun encodeCommand(command: AndroidNotificationCommand, slots: NotificationBinarySlots): JSONObject {
        Log.d(TAG, "[encodeCommand] id: ${command.content.id}, tag: ${command.content.tag}, slots: $slots")
        return JSONObject()
            .put("v", VERSION)
            .put("content", encodeContent(command.content))
            .put("platform", encodePlatform(command.platformOptions, slots))
    }

    /**
     * Decodes a command written by [encodeCommand].
     *
     * @param json The JSON.
     * @param slots Where Intents and Bitmaps come from.
     * @throws org.json.JSONException When required fields are missing.
     */
    fun decodeCommand(json: JSONObject, slots: NotificationBinarySlots): AndroidNotificationCommand {
        Log.d(TAG, "[decodeCommand] slots: $slots")
        return AndroidNotificationCommand(
            content = decodeContent(json.getJSONObject("content")),
            platformOptions = json.optJSONObject("platform")?.let { decodePlatform(it, slots) }
                ?: AndroidNotificationPlatformOptions()
        )
    }

    /** Encodes [schedule]. */
    fun encodeSchedule(schedule: NotificationSchedule): JSONObject {
        Log.d(TAG, "[encodeSchedule] schedule: $schedule")
        return JSONObject()
        .put("triggerAtMillis", schedule.triggerAtMillis)
        .put("exact", schedule.exact)
        .put("allowWhileIdle", schedule.allowWhileIdle)
        .put("persistAcrossBoot", schedule.persistAcrossBoot)
        .put("alarmType", schedule.alarmType)
    }

    /** Decodes a schedule written by [encodeSchedule]. */
    fun decodeSchedule(json: JSONObject): NotificationSchedule {
        Log.d(TAG, "[decodeSchedule]")
        return NotificationSchedule(
        triggerAtMillis = json.getLong("triggerAtMillis"),
        exact = json.optBoolean("exact", true),
        allowWhileIdle = json.optBoolean("allowWhileIdle", true),
        persistAcrossBoot = json.optBoolean("persistAcrossBoot", true),
        alarmType = json.optInt("alarmType", 0)
    )
    }

    // --- content ---

    private fun encodeContent(c: NotificationContent): JSONObject = JSONObject()
        .put("id", c.id)
        .put("title", c.title)
        .put("message", c.message)
        .putOpt("tag", c.tag)
        .put("channel", encodeChannel(c.channel))
        .putOpt("smallIconResId", c.smallIconResId)
        .putOpt("largeIconResId", c.largeIconResId)
        .put("priority", c.priority)
        .put("autoCancel", c.autoCancel)
        .put("ongoing", c.ongoing)
        .putOpt("subText", c.subText)
        .put("showTimestamp", c.showTimestamp)
        .putOpt("timestampMillis", c.timestampMillis)
        .putOpt("soundUri", c.soundUri)
        .putOpt("category", c.category)
        .put("visibility", c.visibility)
        .putOpt("color", c.color)
        .putOpt("number", c.number)
        .putOpt("ticker", c.ticker)
        .putOpt("groupKey", c.groupKey)
        .put("isGroupSummary", c.isGroupSummary)
        .put("groupAlertBehavior", c.groupAlertBehavior)
        .putOpt("sortKey", c.sortKey)
        .put("onlyAlertOnce", c.onlyAlertOnce)
        .put("localOnly", c.localOnly)
        .put("silent", c.silent)
        .put("usesChronometer", c.usesChronometer)
        .putOpt("timeoutAfterMillis", c.timeoutAfterMillis)
        .putOpt("progress", c.progress?.let {
            JSONObject().put("max", it.max).put("current", it.current).put("indeterminate", it.indeterminate)
        })
        .put("style", encodeStyle(c.style))

    private fun decodeContent(j: JSONObject): NotificationContent = NotificationContent(
        id = j.getInt("id"),
        title = j.getString("title"),
        message = j.getString("message"),
        tag = j.optStringOrNull("tag"),
        channel = j.optJSONObject("channel")?.let(::decodeChannel) ?: NotificationChannel(),
        smallIconResId = j.optIntOrNull("smallIconResId"),
        largeIconResId = j.optIntOrNull("largeIconResId"),
        priority = j.optInt("priority", 0),
        autoCancel = j.optBoolean("autoCancel", true),
        ongoing = j.optBoolean("ongoing", false),
        subText = j.optStringOrNull("subText"),
        showTimestamp = j.optBoolean("showTimestamp", true),
        timestampMillis = j.optLongOrNull("timestampMillis"),
        soundUri = j.optStringOrNull("soundUri"),
        category = j.optStringOrNull("category"),
        visibility = j.optInt("visibility", 1),
        color = j.optIntOrNull("color"),
        number = j.optIntOrNull("number"),
        ticker = j.optStringOrNull("ticker"),
        groupKey = j.optStringOrNull("groupKey"),
        isGroupSummary = j.optBoolean("isGroupSummary", false),
        groupAlertBehavior = j.optInt("groupAlertBehavior", 0),
        sortKey = j.optStringOrNull("sortKey"),
        onlyAlertOnce = j.optBoolean("onlyAlertOnce", false),
        localOnly = j.optBoolean("localOnly", false),
        silent = j.optBoolean("silent", false),
        usesChronometer = j.optBoolean("usesChronometer", false),
        timeoutAfterMillis = j.optLongOrNull("timeoutAfterMillis"),
        progress = j.optJSONObject("progress")?.let {
            NotificationProgress(it.getInt("max"), it.getInt("current"), it.optBoolean("indeterminate", false))
        },
        style = j.optJSONObject("style")?.let(::decodeStyle) ?: NotificationStyle.Default
    )

    private fun encodeChannel(c: NotificationChannel): JSONObject = JSONObject()
        .put("id", c.id)
        .put("name", c.name)
        .put("importance", c.importance)
        .putOpt("description", c.description)
        .put("showBadge", c.showBadge)
        .put("enableLights", c.enableLights)
        .putOpt("lightColor", c.lightColor)
        .put("enableVibration", c.enableVibration)
        .putOpt("vibrationPattern", c.vibrationPattern?.let { JSONArray(it) })
        .putOpt("soundUri", c.soundUri)
        .put("lockscreenVisibility", c.lockscreenVisibility)
        .putOpt("groupId", c.groupId)
        .putOpt("groupName", c.groupName)

    private fun decodeChannel(j: JSONObject): NotificationChannel = NotificationChannel(
        id = j.optString("id", "default_channel"),
        name = j.optString("name", "Default Channel"),
        importance = j.optInt("importance", 3),
        description = j.optStringOrNull("description"),
        showBadge = j.optBoolean("showBadge", true),
        enableLights = j.optBoolean("enableLights", true),
        lightColor = j.optIntOrNull("lightColor"),
        enableVibration = j.optBoolean("enableVibration", true),
        vibrationPattern = j.optJSONArray("vibrationPattern")?.let { a -> List(a.length()) { a.getLong(it) } },
        soundUri = j.optStringOrNull("soundUri"),
        lockscreenVisibility = j.optInt("lockscreenVisibility", 1),
        groupId = j.optStringOrNull("groupId"),
        groupName = j.optStringOrNull("groupName")
    )

    // --- style ---

    private fun encodeStyle(s: NotificationStyle): JSONObject = when (s) {
        NotificationStyle.Default -> JSONObject().put("type", "default")
        is NotificationStyle.BigText -> JSONObject().put("type", "bigText")
            .put("bigText", s.bigText).putOpt("summaryText", s.summaryText).putOpt("bigContentTitle", s.bigContentTitle)
        is NotificationStyle.Inbox -> JSONObject().put("type", "inbox")
            .put("lines", JSONArray(s.lines)).putOpt("summaryText", s.summaryText).putOpt("bigContentTitle", s.bigContentTitle)
        is NotificationStyle.BigPicture -> JSONObject().put("type", "bigPicture")
            .putOpt("pictureResId", s.pictureResId).putOpt("pictureUriString", s.pictureUriString)
            .putOpt("summaryText", s.summaryText).putOpt("bigContentTitle", s.bigContentTitle)
            .putOpt("largeIconResId", s.largeIconResId).put("hideExpandedLargeIcon", s.hideExpandedLargeIcon)
        is NotificationStyle.Messaging -> JSONObject().put("type", "messaging")
            .put("userDisplayName", s.userDisplayName)
            .put("messages", JSONArray(s.messages.map {
                JSONObject().put("text", it.text).put("timestampMillis", it.timestampMillis).putOpt("senderName", it.senderName)
            }))
            .putOpt("conversationTitle", s.conversationTitle).putOpt("isGroupConversation", s.isGroupConversation)
        is NotificationStyle.Media -> JSONObject().put("type", "media")
            .put("compactActionIndices", JSONArray(s.compactActionIndices))
        is NotificationStyle.DecoratedCustomView -> JSONObject().put("type", "decoratedCustomView")
            .put("customView", encodeCustomView(s.customView))
        is NotificationStyle.DecoratedMediaCustomView -> JSONObject().put("type", "decoratedMediaCustomView")
            .put("customView", encodeCustomView(s.customView))
            .put("compactActionIndices", JSONArray(s.compactActionIndices))
        is NotificationStyle.Call -> JSONObject().put("type", "call")
            .put("callType", s.callType.name)
            .put("person", JSONObject().put("name", s.person.name).putOpt("avatarResId", s.person.avatarResId))
            .put("isVideo", s.isVideo).putOpt("verificationText", s.verificationText)
    }

    private fun decodeStyle(j: JSONObject): NotificationStyle = when (j.optString("type")) {
        "bigText" -> NotificationStyle.BigText(
            j.getString("bigText"), j.optStringOrNull("summaryText"), j.optStringOrNull("bigContentTitle")
        )
        "inbox" -> NotificationStyle.Inbox(
            j.getJSONArray("lines").strings(), j.optStringOrNull("summaryText"), j.optStringOrNull("bigContentTitle")
        )
        "bigPicture" -> NotificationStyle.BigPicture(
            pictureResId = j.optIntOrNull("pictureResId"),
            pictureUriString = j.optStringOrNull("pictureUriString"),
            summaryText = j.optStringOrNull("summaryText"),
            bigContentTitle = j.optStringOrNull("bigContentTitle"),
            largeIconResId = j.optIntOrNull("largeIconResId"),
            hideExpandedLargeIcon = j.optBoolean("hideExpandedLargeIcon", false)
        )
        "messaging" -> NotificationStyle.Messaging(
            userDisplayName = j.getString("userDisplayName"),
            messages = j.getJSONArray("messages").let { a ->
                List(a.length()) { i ->
                    val m = a.getJSONObject(i)
                    NotificationMessage(m.getString("text"), m.getLong("timestampMillis"), m.optStringOrNull("senderName"))
                }
            },
            conversationTitle = j.optStringOrNull("conversationTitle"),
            isGroupConversation = if (j.has("isGroupConversation")) j.getBoolean("isGroupConversation") else null
        )
        "media" -> NotificationStyle.Media(j.optJSONArray("compactActionIndices")?.ints() ?: emptyList())
        "decoratedCustomView" -> NotificationStyle.DecoratedCustomView(decodeCustomView(j.getJSONObject("customView")))
        "decoratedMediaCustomView" -> NotificationStyle.DecoratedMediaCustomView(
            decodeCustomView(j.getJSONObject("customView")),
            j.optJSONArray("compactActionIndices")?.ints() ?: emptyList()
        )
        "call" -> NotificationStyle.Call(
            callType = NotificationCallType.valueOf(j.getString("callType")),
            person = j.getJSONObject("person").let { NotificationCallPerson(it.getString("name"), it.optIntOrNull("avatarResId")) },
            isVideo = j.optBoolean("isVideo", false),
            verificationText = j.optStringOrNull("verificationText")
        )
        else -> NotificationStyle.Default
    }

    private fun encodeCustomView(c: NotificationCustomViewStyleData): JSONObject =
        JSONObject().put("layoutResId", c.layoutResId).putOpt("bigLayoutResId", c.bigLayoutResId)

    private fun decodeCustomView(j: JSONObject): NotificationCustomViewStyleData =
        NotificationCustomViewStyleData(j.getInt("layoutResId"), j.optIntOrNull("bigLayoutResId"))

    // --- platform options ---

    private fun encodePlatform(p: AndroidNotificationPlatformOptions, slots: NotificationBinarySlots): JSONObject =
        JSONObject()
            .putOpt("largeIconBitmap", p.largeIconBitmap?.let(slots::putBitmap))
            .putOpt("contentIntent", p.contentIntent?.let { encodeRequest(it, slots) })
            .putOpt("deleteIntent", p.deleteIntent?.let { encodeRequest(it, slots) })
            .putOpt("fullScreenIntent", p.fullScreenIntent?.let { encodeRequest(it, slots) })
            .put("actions", JSONArray(p.actions.map { encodeAction(it, slots) }))
            .putOpt("callStyleOptions", p.callStyleOptions?.let {
                JSONObject()
                    .putOpt("answerIntent", it.answerIntent?.let { r -> encodeRequest(r, slots) })
                    .putOpt("declineIntent", it.declineIntent?.let { r -> encodeRequest(r, slots) })
                    .putOpt("hangUpIntent", it.hangUpIntent?.let { r -> encodeRequest(r, slots) })
            })
            .putOpt("customViewOptions", p.customViewOptions?.let {
                JSONObject().put("viewActions", JSONArray(it.viewActions.map { a -> encodeViewAction(a, slots) }))
            })

    private fun decodePlatform(j: JSONObject, slots: NotificationBinarySlots): AndroidNotificationPlatformOptions =
        AndroidNotificationPlatformOptions(
            largeIconBitmap = j.opt("largeIconBitmap")?.takeUnless { it == JSONObject.NULL }?.let(slots::bitmap),
            contentIntent = j.optJSONObject("contentIntent")?.let { decodeRequest(it, slots) },
            deleteIntent = j.optJSONObject("deleteIntent")?.let { decodeRequest(it, slots) },
            fullScreenIntent = j.optJSONObject("fullScreenIntent")?.let { decodeRequest(it, slots) },
            actions = j.optJSONArray("actions")?.let { a -> List(a.length()) { decodeAction(a.getJSONObject(it), slots) } }
                ?: emptyList(),
            callStyleOptions = j.optJSONObject("callStyleOptions")?.let {
                AndroidNotificationCallPlatformOptions(
                    answerIntent = it.optJSONObject("answerIntent")?.let { r -> decodeRequest(r, slots) },
                    declineIntent = it.optJSONObject("declineIntent")?.let { r -> decodeRequest(r, slots) },
                    hangUpIntent = it.optJSONObject("hangUpIntent")?.let { r -> decodeRequest(r, slots) }
                )
            },
            customViewOptions = j.optJSONObject("customViewOptions")?.let {
                val a = it.optJSONArray("viewActions") ?: JSONArray()
                AndroidNotificationCustomViewPlatformOptions(List(a.length()) { i -> decodeViewAction(a.getJSONObject(i), slots) })
            }
        )

    private fun encodeRequest(r: AndroidPendingIntentRequest, slots: NotificationBinarySlots): JSONObject = JSONObject()
        .put("intent", slots.putIntent(r.intent))
        .put("requestCode", r.requestCode)
        .put("type", r.type.name)
        .put("flags", r.flags)
        .put("mutable", r.mutable)

    private fun decodeRequest(j: JSONObject, slots: NotificationBinarySlots): AndroidPendingIntentRequest =
        AndroidPendingIntentRequest(
            intent = slots.intent(j.get("intent")),
            requestCode = j.getInt("requestCode"),
            type = AndroidPendingIntentType.valueOf(j.optString("type", AndroidPendingIntentType.ACTIVITY.name)),
            flags = j.optInt("flags", 0),
            mutable = j.optBoolean("mutable", false)
        )

    private fun encodeAction(a: AndroidNotificationAction, slots: NotificationBinarySlots): JSONObject = JSONObject()
        .put("title", a.title)
        .put("pendingIntent", encodeRequest(a.pendingIntent, slots))
        .put("iconResId", a.iconResId)
        .put("allowGeneratedReplies", a.allowGeneratedReplies)
        .put("semanticAction", a.semanticAction)
        .put("contextual", a.contextual)
        .put("showsUserInterface", a.showsUserInterface)

    private fun decodeAction(j: JSONObject, slots: NotificationBinarySlots): AndroidNotificationAction =
        AndroidNotificationAction(
            title = j.getString("title"),
            pendingIntent = decodeRequest(j.getJSONObject("pendingIntent"), slots),
            iconResId = j.optInt("iconResId", 0),
            allowGeneratedReplies = j.optBoolean("allowGeneratedReplies", false),
            semanticAction = j.optInt("semanticAction", 0),
            contextual = j.optBoolean("contextual", false),
            showsUserInterface = j.optBoolean("showsUserInterface", true)
        )

    private fun encodeViewAction(a: RemoteViewAction, slots: NotificationBinarySlots): JSONObject = when (a) {
        is RemoteViewAction.SetText -> JSONObject().put("type", "setText").put("viewId", a.viewId).put("text", a.text)
        is RemoteViewAction.SetImage -> JSONObject().put("type", "setImage").put("viewId", a.viewId).put("resId", a.resId)
        is RemoteViewAction.SetClickIntent -> JSONObject().put("type", "setClickIntent").put("viewId", a.viewId)
            .put("pendingIntent", encodeRequest(a.pendingIntent, slots))
    }

    private fun decodeViewAction(j: JSONObject, slots: NotificationBinarySlots): RemoteViewAction =
        when (val type = j.getString("type")) {
            "setText" -> RemoteViewAction.SetText(j.getInt("viewId"), j.getString("text"))
            "setImage" -> RemoteViewAction.SetImage(j.getInt("viewId"), j.getInt("resId"))
            "setClickIntent" -> RemoteViewAction.SetClickIntent(j.getInt("viewId"), decodeRequest(j.getJSONObject("pendingIntent"), slots))
            else -> throw IllegalArgumentException("unknown view action type: $type")
        }

    // --- helpers ---

    private fun JSONObject.optStringOrNull(name: String): String? =
        if (has(name) && !isNull(name)) getString(name) else null

    private fun JSONObject.optIntOrNull(name: String): Int? =
        if (has(name) && !isNull(name)) getInt(name) else null

    private fun JSONObject.optLongOrNull(name: String): Long? =
        if (has(name) && !isNull(name)) getLong(name) else null

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun JSONArray.ints(): List<Int> = List(length()) { getInt(it) }
}
