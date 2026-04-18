package android.unity.notification

import org.json.JSONArray
import org.json.JSONObject

internal object UnityNotificationJsonParser {

    fun parseChannel(json: String): UnityNotificationChannelSpec {
        return parseChannelObject(JSONObject(json))
    }

    fun parseNotification(
        json: String,
        nowProvider: () -> Long = System::currentTimeMillis
    ): UnityNotificationSpec {
        return parseNotificationObject(JSONObject(json), nowProvider)
    }

    fun parseScheduledNotification(
        json: String,
        nowProvider: () -> Long = System::currentTimeMillis
    ): UnityScheduledNotificationSpec {
        val root = JSONObject(json)
        val notificationObject = root.optJSONObject("notification")
            ?: throw IllegalArgumentException("notification is required.")
        val scheduleObject = root.optJSONObject("schedule")
            ?: throw IllegalArgumentException("schedule is required.")

        return UnityScheduledNotificationSpec(
            notification = parseNotificationObject(notificationObject, nowProvider),
            triggerAtMillis = scheduleObject.optLong("triggerAtMillis").takeIf { it > 0L }
                ?: throw IllegalArgumentException("schedule.triggerAtMillis must be greater than 0."),
            exact = scheduleObject.optBoolean("exact", true),
            allowWhileIdle = scheduleObject.optBoolean("allowWhileIdle", true),
            persistAcrossBoot = scheduleObject.optBoolean("persistAcrossBoot", true),
            alarmType = scheduleObject.optInt("alarmType", 0)
        )
    }

    private fun parseNotificationObject(
        json: JSONObject,
        nowProvider: () -> Long
    ): UnityNotificationSpec {
        val channelObject = json.optJSONObject("channel")
            ?: throw IllegalArgumentException("channel is required.")

        return UnityNotificationSpec(
            id = json.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE }
                ?: throw IllegalArgumentException("id is required."),
            title = json.requireString("title"),
            message = json.requireString("message"),
            tag = json.optStringOrNull("tag"),
            channel = parseChannelObject(channelObject),
            smallIcon = json.optResourceRef("smallIcon"),
            largeIcon = json.optResourceRef("largeIcon"),
            priority = json.optInt("priority", 0),
            autoCancel = json.optBoolean("autoCancel", true),
            ongoing = json.optBoolean("ongoing", false),
            subText = json.optStringOrNull("subText"),
            showTimestamp = json.optBoolean("showTimestamp", true),
            timestampMillis = json.optNullableLong("timestampMillis"),
            soundUriString = json.optStringOrNull("soundUri"),
            category = json.optStringOrNull("category"),
            visibility = json.optInt("visibility", 1),
            color = json.optNullableInt("color"),
            number = json.optNullableInt("number"),
            ticker = json.optStringOrNull("ticker"),
            groupKey = json.optStringOrNull("groupKey"),
            isGroupSummary = json.optBoolean("isGroupSummary", false),
            groupAlertBehavior = json.optInt("groupAlertBehavior", 0),
            sortKey = json.optStringOrNull("sortKey"),
            onlyAlertOnce = json.optBoolean("onlyAlertOnce", false),
            localOnly = json.optBoolean("localOnly", false),
            silent = json.optBoolean("silent", false),
            usesChronometer = json.optBoolean("usesChronometer", false),
            timeoutAfterMillis = json.optNullableLong("timeoutAfterMillis"),
            progress = json.optJSONObject("progress")?.let(::parseProgressObject),
            style = json.optJSONObject("style")?.let { parseStyleObject(it, nowProvider) }
                ?: UnityNotificationStyleSpec(),
            launchAppOnTap = json.optBoolean("launchAppOnTap", true),
            launchAction = json.optStringOrNull("launchAction"),
            actions = json.optJSONArray("actions")?.toActionSpecs().orEmpty(),
            fullScreenIntent = json.optBoolean("fullScreenIntent", false),
            data = json.optJSONObject("data")?.toStringMap()
        )
    }

    private fun JSONArray.toActionSpecs(): List<UnityNotificationActionSpec> {
        return buildList(length()) {
            for (index in 0 until length()) {
                val obj = optJSONObject(index) ?: continue
                val title = obj.optStringOrNull("title") ?: continue
                val actionId = obj.optStringOrNull("actionId") ?: continue
                add(
                    UnityNotificationActionSpec(
                        title = title,
                        actionId = actionId,
                        icon = obj.optResourceRef("icon"),
                        launchApp = obj.optBoolean("launchApp", false),
                        allowGeneratedReplies = obj.optBoolean("allowGeneratedReplies", false),
                        semanticAction = obj.optInt("semanticAction", 0),
                        contextual = obj.optBoolean("contextual", false),
                        showsUserInterface = obj.optBoolean("showsUserInterface", true)
                    )
                )
            }
        }
    }

    private fun parseChannelObject(json: JSONObject): UnityNotificationChannelSpec {
        return UnityNotificationChannelSpec(
            id = json.requireString("id"),
            name = json.requireString("name"),
            importance = json.optInt("importance", 3),
            description = json.optStringOrNull("description"),
            showBadge = json.optBoolean("showBadge", true),
            enableLights = json.optBoolean("enableLights", true),
            lightColor = json.optNullableInt("lightColor"),
            enableVibration = json.optBoolean("enableVibration", true),
            vibrationPattern = json.optLongList("vibrationPattern"),
            soundUriString = json.optStringOrNull("soundUri"),
            lockscreenVisibility = json.optInt("lockscreenVisibility", 1),
            groupId = json.optStringOrNull("groupId"),
            groupName = json.optStringOrNull("groupName")
        )
    }

    private fun parseProgressObject(json: JSONObject): UnityNotificationProgressSpec {
        return UnityNotificationProgressSpec(
            max = json.optInt("max", 0),
            current = json.optInt("current", 0),
            indeterminate = json.optBoolean("indeterminate", false)
        )
    }

    private fun parseStyleObject(
        json: JSONObject,
        nowProvider: () -> Long
    ): UnityNotificationStyleSpec {
        val type = json.optStringOrNull("type") ?: UnityNotificationStyleSpec.TYPE_DEFAULT
        return when (type) {
            UnityNotificationStyleSpec.TYPE_BIG_TEXT -> {
                UnityNotificationStyleSpec(
                    type = type,
                    bigText = json.requireString("bigText"),
                    summaryText = json.optStringOrNull("summaryText"),
                    bigContentTitle = json.optStringOrNull("bigContentTitle")
                )
            }

            UnityNotificationStyleSpec.TYPE_INBOX -> {
                UnityNotificationStyleSpec(
                    type = type,
                    lines = json.optStringList("lines"),
                    summaryText = json.optStringOrNull("summaryText"),
                    bigContentTitle = json.optStringOrNull("bigContentTitle")
                )
            }

            UnityNotificationStyleSpec.TYPE_BIG_PICTURE -> {
                UnityNotificationStyleSpec(
                    type = type,
                    picture = json.optResourceRef("picture"),
                    pictureUriString = json.optStringOrNull("pictureUri"),
                    summaryText = json.optStringOrNull("summaryText"),
                    bigContentTitle = json.optStringOrNull("bigContentTitle"),
                    largeIcon = json.optResourceRef("largeIcon"),
                    hideExpandedLargeIcon = json.optBoolean("hideExpandedLargeIcon", false)
                )
            }

            UnityNotificationStyleSpec.TYPE_MESSAGING -> {
                UnityNotificationStyleSpec(
                    type = type,
                    userDisplayName = json.optStringOrNull("userDisplayName") ?: "You",
                    conversationTitle = json.optStringOrNull("conversationTitle"),
                    isGroupConversation = if (json.has("isGroupConversation")) {
                        json.optBoolean("isGroupConversation")
                    } else {
                        null
                    },
                    messages = json.optJSONArray("messages")?.toMessageSpecs(nowProvider).orEmpty()
                )
            }

            else -> UnityNotificationStyleSpec(type = UnityNotificationStyleSpec.TYPE_DEFAULT)
        }
    }

    private fun JSONArray.toMessageSpecs(nowProvider: () -> Long): List<UnityNotificationMessageSpec> {
        return buildList(length()) {
            for (index in 0 until length()) {
                val messageObject = optJSONObject(index) ?: continue
                val text = messageObject.optStringOrNull("text") ?: continue
                add(
                    UnityNotificationMessageSpec(
                        text = text,
                        timestampMillis = messageObject.optNullableLong("timestampMillis") ?: nowProvider(),
                        senderName = messageObject.optStringOrNull("senderName")
                    )
                )
            }
        }
    }

    private fun JSONObject.optResourceRef(key: String): UnityNotificationResourceRef? {
        val resourceObject = optJSONObject(key) ?: return null
        val name = resourceObject.optStringOrNull("name") ?: return null
        return UnityNotificationResourceRef(
            name = name,
            type = resourceObject.optStringOrNull("type")
        )
    }

    private fun JSONObject.optStringList(key: String): List<String> {
        val array = optJSONArray(key) ?: return emptyList()
        return buildList(array.length()) {
            for (index in 0 until array.length()) {
                array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
            }
        }
    }

    private fun JSONObject.toStringMap(): Map<String, String>? {
        if (length() == 0) return null
        return buildMap {
            keys().forEach { key -> put(key, optString(key)) }
        }
    }

    private fun JSONObject.optLongList(key: String): List<Long>? {
        val array = optJSONArray(key) ?: return null
        return buildList(array.length()) {
            for (index in 0 until array.length()) {
                val value = array.optLong(index, Long.MIN_VALUE)
                if (value != Long.MIN_VALUE) {
                    add(value)
                }
            }
        }.takeIf { it.isNotEmpty() }
    }

    private fun JSONObject.optStringOrNull(key: String): String? {
        if (isNull(key)) return null
        return optString(key).takeIf { it.isNotBlank() }
    }

    private fun JSONObject.optNullableLong(key: String): Long? {
        if (!has(key) || isNull(key)) return null
        return optLong(key)
    }

    private fun JSONObject.optNullableInt(key: String): Int? {
        if (!has(key) || isNull(key)) return null
        return optInt(key)
    }

    private fun JSONObject.requireString(key: String): String {
        return optStringOrNull(key) ?: throw IllegalArgumentException("$key is required.")
    }
}

