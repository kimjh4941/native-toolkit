package android.library.notification.data.repository

import android.os.Parcelable
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.domain.model.NotificationCallType
import kotlinx.parcelize.Parcelize

@Parcelize
internal data class NotificationChannelPayload(
    val id: String,
    val name: String,
    val importance: Int,
    val description: String?,
    val showBadge: Boolean,
    val enableLights: Boolean,
    val lightColor: Int?,
    val enableVibration: Boolean,
    val vibrationPattern: List<Long>?,
    val soundUri: String?,
    val lockscreenVisibility: Int,
    val groupId: String?,
    val groupName: String?
) : Parcelable

@Parcelize
internal data class NotificationProgressPayload(
    val max: Int,
    val current: Int,
    val indeterminate: Boolean
) : Parcelable

@Parcelize
internal data class NotificationMessagePayload(
    val text: String,
    val timestampMillis: Long,
    val senderName: String?
) : Parcelable

@Parcelize
internal data class NotificationCustomViewStyleDataPayload(
    val layoutResId: Int,
    val bigLayoutResId: Int?,
    val titleViewId: Int?,
    val titleText: String?,
    val messageViewId: Int?,
    val messageText: String?,
    val iconViewId: Int?,
    val iconResId: Int?
) : Parcelable

@Parcelize
internal data class NotificationCallPersonPayload(
    val name: String,
    val avatarResId: Int?
) : Parcelable

internal sealed class NotificationStylePayload : Parcelable {
    @Parcelize
    internal data object Default : NotificationStylePayload()

    @Parcelize
    internal data class BigText(
        val bigText: String,
        val summaryText: String?,
        val bigContentTitle: String?
    ) : NotificationStylePayload()

    @Parcelize
    internal data class Inbox(
        val lines: List<String>,
        val summaryText: String?,
        val bigContentTitle: String?
    ) : NotificationStylePayload()

    @Parcelize
    internal data class BigPicture(
        val pictureResId: Int?,
        val pictureUriString: String?,
        val summaryText: String?,
        val bigContentTitle: String?,
        val largeIconResId: Int?,
        val hideExpandedLargeIcon: Boolean
    ) : NotificationStylePayload()

    @Parcelize
    internal data class Messaging(
        val userDisplayName: String,
        val messages: List<NotificationMessagePayload>,
        val conversationTitle: String?,
        val isGroupConversation: Boolean?
    ) : NotificationStylePayload()

    @Parcelize
    internal data class Media(
        val compactActionIndices: List<Int>
    ) : NotificationStylePayload()

    @Parcelize
    internal data class DecoratedCustomView(
        val customView: NotificationCustomViewStyleDataPayload
    ) : NotificationStylePayload()

    @Parcelize
    internal data class DecoratedMediaCustomView(
        val customView: NotificationCustomViewStyleDataPayload,
        val compactActionIndices: List<Int>
    ) : NotificationStylePayload()

    @Parcelize
    internal data class Call(
        val callType: NotificationCallType,
        val person: NotificationCallPersonPayload,
        val isVideo: Boolean,
        val verificationText: String?
    ) : NotificationStylePayload()
}

@Parcelize
internal data class NotificationContentPayload(
    val id: Int,
    val title: String,
    val message: String,
    val tag: String?,
    val channel: NotificationChannelPayload,
    val smallIconResId: Int?,
    val largeIconResId: Int?,
    val priority: Int,
    val autoCancel: Boolean,
    val ongoing: Boolean,
    val subText: String?,
    val showTimestamp: Boolean,
    val timestampMillis: Long?,
    val soundUri: String?,
    val category: String?,
    val visibility: Int,
    val color: Int?,
    val number: Int?,
    val ticker: String?,
    val groupKey: String?,
    val isGroupSummary: Boolean,
    val groupAlertBehavior: Int,
    val sortKey: String?,
    val onlyAlertOnce: Boolean,
    val localOnly: Boolean,
    val silent: Boolean,
    val usesChronometer: Boolean,
    val timeoutAfterMillis: Long?,
    val progress: NotificationProgressPayload?,
    val style: NotificationStylePayload
) : Parcelable

@Parcelize
internal data class AndroidNotificationCommandPayload(
    val content: NotificationContentPayload,
    val platformOptions: AndroidNotificationPlatformOptions = AndroidNotificationPlatformOptions()
) : Parcelable
