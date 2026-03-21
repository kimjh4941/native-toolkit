package android.library.notification.domain.model

sealed class NotificationStyle {
    data object Default : NotificationStyle()

    data class BigText(
        val bigText: String,
        val summaryText: String? = null,
        val bigContentTitle: String? = null
    ) : NotificationStyle()

    data class Inbox(
        val lines: List<String>,
        val summaryText: String? = null,
        val bigContentTitle: String? = null
    ) : NotificationStyle()

    data class BigPicture(
        val pictureResId: Int? = null,
        val pictureUriString: String? = null,
        val summaryText: String? = null,
        val bigContentTitle: String? = null,
        val largeIconResId: Int? = null,
        val hideExpandedLargeIcon: Boolean = false
    ) : NotificationStyle()

    data class Messaging(
        val userDisplayName: String,
        val messages: List<NotificationMessage>,
        val conversationTitle: String? = null,
        val isGroupConversation: Boolean? = null
    ) : NotificationStyle()

    data class Media(
        val compactActionIndices: List<Int> = emptyList()
    ) : NotificationStyle()

    data class DecoratedCustomView(
        val customView: NotificationCustomViewStyleData
    ) : NotificationStyle()

    data class DecoratedMediaCustomView(
        val customView: NotificationCustomViewStyleData,
        val compactActionIndices: List<Int> = emptyList()
    ) : NotificationStyle()

    data class Call(
        val callType: NotificationCallType,
        val person: NotificationCallPerson,
        val isVideo: Boolean = false,
        val verificationText: String? = null
    ) : NotificationStyle()
}

data class NotificationCustomViewStyleData(
    val layoutResId: Int,
    val bigLayoutResId: Int? = null,
    val titleViewId: Int? = null,
    val titleText: String? = null,
    val messageViewId: Int? = null,
    val messageText: String? = null,
    val iconViewId: Int? = null,
    val iconResId: Int? = null
)

enum class NotificationCallType {
    INCOMING,
    ONGOING,
    SCREENING
}

data class NotificationCallPerson(
    val name: String,
    val avatarResId: Int? = null
)
