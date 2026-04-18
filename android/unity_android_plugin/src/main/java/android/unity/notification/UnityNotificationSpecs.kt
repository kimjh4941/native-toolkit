package android.unity.notification

internal data class UnityNotificationResourceRef(
    val name: String,
    val type: String? = null
)

internal data class UnityNotificationChannelSpec(
    val id: String,
    val name: String,
    val importance: Int = 3,
    val description: String? = null,
    val showBadge: Boolean = true,
    val enableLights: Boolean = true,
    val lightColor: Int? = null,
    val enableVibration: Boolean = true,
    val vibrationPattern: List<Long>? = null,
    val soundUriString: String? = null,
    val lockscreenVisibility: Int = 1,
    val groupId: String? = null,
    val groupName: String? = null
)

internal data class UnityNotificationProgressSpec(
    val max: Int,
    val current: Int,
    val indeterminate: Boolean = false
)

internal data class UnityNotificationMessageSpec(
    val text: String,
    val timestampMillis: Long,
    val senderName: String? = null
)

internal data class UnityNotificationActionSpec(
    val title: String,
    val actionId: String,
    val icon: UnityNotificationResourceRef? = null,
    val launchApp: Boolean = false,
    val allowGeneratedReplies: Boolean = false,
    val semanticAction: Int = 0,
    val contextual: Boolean = false,
    val showsUserInterface: Boolean = true
)

internal data class UnityNotificationStyleSpec(
    val type: String = TYPE_DEFAULT,
    val bigText: String? = null,
    val summaryText: String? = null,
    val bigContentTitle: String? = null,
    val lines: List<String> = emptyList(),
    val picture: UnityNotificationResourceRef? = null,
    val pictureUriString: String? = null,
    val largeIcon: UnityNotificationResourceRef? = null,
    val hideExpandedLargeIcon: Boolean = false,
    val userDisplayName: String? = null,
    val conversationTitle: String? = null,
    val isGroupConversation: Boolean? = null,
    val messages: List<UnityNotificationMessageSpec> = emptyList()
) {
    companion object {
        const val TYPE_DEFAULT = "default"
        const val TYPE_BIG_TEXT = "bigText"
        const val TYPE_INBOX = "inbox"
        const val TYPE_BIG_PICTURE = "bigPicture"
        const val TYPE_MESSAGING = "messaging"
    }
}

internal data class UnityNotificationSpec(
    val id: Int,
    val title: String,
    val message: String,
    val tag: String? = null,
    val channel: UnityNotificationChannelSpec,
    val smallIcon: UnityNotificationResourceRef? = null,
    val largeIcon: UnityNotificationResourceRef? = null,
    val priority: Int = 0,
    val autoCancel: Boolean = true,
    val ongoing: Boolean = false,
    val subText: String? = null,
    val showTimestamp: Boolean = true,
    val timestampMillis: Long? = null,
    val soundUriString: String? = null,
    val category: String? = null,
    val visibility: Int = 1,
    val color: Int? = null,
    val number: Int? = null,
    val ticker: String? = null,
    val groupKey: String? = null,
    val isGroupSummary: Boolean = false,
    val groupAlertBehavior: Int = 0,
    val sortKey: String? = null,
    val onlyAlertOnce: Boolean = false,
    val localOnly: Boolean = false,
    val silent: Boolean = false,
    val usesChronometer: Boolean = false,
    val timeoutAfterMillis: Long? = null,
    val progress: UnityNotificationProgressSpec? = null,
    val style: UnityNotificationStyleSpec = UnityNotificationStyleSpec(),
    val launchAppOnTap: Boolean = true,
    val launchAction: String? = null,
    val actions: List<UnityNotificationActionSpec> = emptyList(),
    val fullScreenIntent: Boolean = false
)

internal data class UnityScheduledNotificationSpec(
    val notification: UnityNotificationSpec,
    val triggerAtMillis: Long,
    val exact: Boolean = true,
    val allowWhileIdle: Boolean = true,
    val persistAcrossBoot: Boolean = true,
    val alarmType: Int = 0
)

