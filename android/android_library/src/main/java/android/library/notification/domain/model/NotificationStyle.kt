package android.library.notification.domain.model

/**
 * Types of notification styles.
 */
sealed class NotificationStyle {
    /**
     * Default style.
     */
    data object Default : NotificationStyle()

    /**
     * BigText style for expanded long text.
     *
     * @property bigText Expanded long text.
     * @property summaryText Optional summary text.
     * @property bigContentTitle Optional expanded title.
     */
    data class BigText(
        val bigText: String,
        val summaryText: String? = null,
        val bigContentTitle: String? = null
    ) : NotificationStyle()

    /**
     * Inbox style for expanded multi-line content.
     *
     * @property lines Lines to render.
     * @property summaryText Optional summary text.
     * @property bigContentTitle Optional expanded title.
     */
    data class Inbox(
        val lines: List<String>,
        val summaryText: String? = null,
        val bigContentTitle: String? = null
    ) : NotificationStyle()

    /**
     * BigPicture style for expanded image content.
     *
     * @property pictureResId Resource ID of the picture.
     * @property pictureUriString Picture URI string. Use either this or pictureResId.
     * @property hideExpandedLargeIcon Whether to hide the large icon in expanded view.
     */
    data class BigPicture(
        val pictureResId: Int? = null,
        val pictureUriString: String? = null,
        val summaryText: String? = null,
        val bigContentTitle: String? = null,
        val largeIconResId: Int? = null,
        val hideExpandedLargeIcon: Boolean = false
    ) : NotificationStyle()

    /**
     * Messaging style for chat history presentation.
     *
     * @property userDisplayName Display name of the local user.
     * @property messages Message list.
     * @property conversationTitle Optional conversation title.
     * @property isGroupConversation Whether this is a group conversation.
     */
    data class Messaging(
        val userDisplayName: String,
        val messages: List<NotificationMessage>,
        val conversationTitle: String? = null,
        val isGroupConversation: Boolean? = null
    ) : NotificationStyle()

    /**
     * Media style with playback action controls.
     *
     * @property compactActionIndices Action indices shown in compact mode.
     */
    data class Media(
        val compactActionIndices: List<Int> = emptyList()
    ) : NotificationStyle()

    /**
     * DecoratedCustomView style that renders a custom view inside a notification template.
     */
    data class DecoratedCustomView(
        val customView: NotificationCustomViewStyleData
    ) : NotificationStyle()

    /**
     * DecoratedMediaCustomView style combining a custom view and media controls.
     */
    data class DecoratedMediaCustomView(
        val customView: NotificationCustomViewStyleData,
        val compactActionIndices: List<Int> = emptyList()
    ) : NotificationStyle()

    /**
     * CallStyle for incoming, ongoing, and screening call notifications.
     *
     * @property callType Type of call notification.
     * @property person Person metadata for the call.
     * @property isVideo Whether the call is video.
     * @property verificationText Optional verification label.
     */
    data class Call(
        val callType: NotificationCallType,
        val person: NotificationCallPerson,
        val isVideo: Boolean = false,
        val verificationText: String? = null
    ) : NotificationStyle()
}

/**
 * Layout configuration for custom-view notification styles.
 *
 * @property layoutResId Layout resource ID for compact view.
 * @property bigLayoutResId Optional layout resource ID for expanded view.
 */
data class NotificationCustomViewStyleData(
    val layoutResId: Int,
    val bigLayoutResId: Int? = null
)

/**
 * Call type for CallStyle notifications.
 */
enum class NotificationCallType {
    INCOMING,
    ONGOING,
    SCREENING
}

/**
 * Person information used by CallStyle notifications.
 *
 * @property name Display name.
 * @property avatarResId Optional avatar resource ID.
 */
data class NotificationCallPerson(
    val name: String,
    val avatarResId: Int? = null
)
