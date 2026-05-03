package android.unity.notification

/**
 * Resource reference by name.
 *
 * @property name Resource name.
 * @property type Optional resource type (for example, "drawable"). Auto-resolved when null.
 */
internal data class UnityNotificationResourceRef(
    val name: String,
    val type: String? = null
)

/**
 * DTO for notification channel settings passed from Unity.
 */
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

/**
 * DTO for progress configuration passed from Unity.
 *
 * @property indeterminate If true, max and current are ignored.
 */
internal data class UnityNotificationProgressSpec(
    val max: Int,
    val current: Int,
    val indeterminate: Boolean = false
)

/**
 * DTO for a single message entry in Messaging style notifications.
 *
 * @property senderName Sender name, or null for local user messages.
 */
internal data class UnityNotificationMessageSpec(
    val text: String,
    val timestampMillis: Long,
    val senderName: String? = null
)

/**
 * DTO for a notification action button.
 *
 * @property actionId Action identifier delivered to [NotificationActionReceiver] on tap.
 * @property launchApp Whether to bring the app to foreground on tap.
 */
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

/**
 * DTO for RemoteViews actions in custom-view notifications.
 *
 * @property type Action type such as [TYPE_SET_CLICK_INTENT].
 * @property viewId Resource name of the target view.
 * @property actionId Action identifier delivered on click.
 */
internal data class UnityNotificationViewActionSpec(
    val type: String,
    val viewId: String,
    val actionId: String? = null
) {
    companion object {
        const val TYPE_SET_CLICK_INTENT = "setClickIntent"
    }
}

/**
 * DTO for notification style configuration passed from Unity.
 *
 * Selects a style by [type] and fills fields relevant to that style.
 * Supported styles: [TYPE_DEFAULT], [TYPE_BIG_TEXT], [TYPE_INBOX], [TYPE_BIG_PICTURE],
 * [TYPE_MESSAGING], and [TYPE_DECORATED_CUSTOM_VIEW].
 */
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
    val messages: List<UnityNotificationMessageSpec> = emptyList(),
    val customViewLayoutName: String? = null,
    val bigCustomViewLayoutName: String? = null,
    val viewActions: List<UnityNotificationViewActionSpec> = emptyList()
) {
    companion object {
        const val TYPE_DEFAULT = "default"
        const val TYPE_BIG_TEXT = "bigText"
        const val TYPE_INBOX = "inbox"
        const val TYPE_BIG_PICTURE = "bigPicture"
        const val TYPE_MESSAGING = "messaging"
        const val TYPE_DECORATED_CUSTOM_VIEW = "decoratedCustomView"
    }
}

/**
 * DTO for full notification content passed from Unity.
 *
 * @property launchAppOnTap Whether to launch the app when the notification body is tapped.
 * @property launchAction Custom action string delivered on tap.
 * @property actions List of action buttons.
 * @property fullScreenIntent Whether to issue a full-screen intent.
 * @property data Optional custom key-value payload attached to the notification.
 */
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
    val fullScreenIntent: Boolean = false,
    val data: Map<String, String>? = null
)

/**
 * DTO for scheduled notifications passed from Unity.
 *
 * @property triggerAtMillis Trigger time in epoch milliseconds.
 * @property exact Whether to use an exact alarm.
 * @property allowWhileIdle Whether the alarm can fire during Doze mode.
 * @property persistAcrossBoot Whether to restore scheduling after device reboot.
 * @property alarmType Alarm type constant from AlarmManager.
 */
internal data class UnityScheduledNotificationSpec(
    val notification: UnityNotificationSpec,
    val triggerAtMillis: Long,
    val exact: Boolean = true,
    val allowWhileIdle: Boolean = true,
    val persistAcrossBoot: Boolean = true,
    val alarmType: Int = 0
)

