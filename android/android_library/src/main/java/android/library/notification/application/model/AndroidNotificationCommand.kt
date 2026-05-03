package android.library.notification.application.model

import android.content.Intent
import android.graphics.Bitmap
import android.os.Parcelable
import android.library.notification.domain.model.NotificationContent
import kotlinx.parcelize.Parcelize

/**
 * Target component type used to create a PendingIntent.
 */
enum class AndroidPendingIntentType {
    ACTIVITY,
    BROADCAST,
    SERVICE,
    FOREGROUND_SERVICE
}

/**
 * Request data for creating a PendingIntent.
 *
 * @property intent Intent to wrap.
 * @property requestCode Request code.
 * @property type Target component type.
 * @property flags PendingIntent flags.
 * @property mutable Whether the PendingIntent is mutable.
 */
@Parcelize
data class AndroidPendingIntentRequest(
    val intent: Intent,
    val requestCode: Int,
    val type: AndroidPendingIntentType = AndroidPendingIntentType.ACTIVITY,
    val flags: Int = 0,
    val mutable: Boolean = false
) : Parcelable

/**
 * Definition for a notification action button.
 *
 * @property title Button label.
 * @property pendingIntent PendingIntent triggered when the button is tapped.
 * @property iconResId Resource ID of the button icon.
 * @property semanticAction Semantic action constant from [androidx.core.app.NotificationCompat.Action].
 */
@Parcelize
data class AndroidNotificationAction(
    val title: String,
    val pendingIntent: AndroidPendingIntentRequest,
    val iconResId: Int = 0,
    val allowGeneratedReplies: Boolean = false,
    val semanticAction: Int = 0,
    val contextual: Boolean = false,
    val showsUserInterface: Boolean = true
) : Parcelable

/**
 * Platform-specific options for CallStyle notifications.
 *
 * @property answerIntent PendingIntent fired when answering a call.
 * @property declineIntent PendingIntent fired when declining a call.
 * @property hangUpIntent PendingIntent fired when ending a call.
 */
@Parcelize
data class AndroidNotificationCallPlatformOptions(
    val answerIntent: AndroidPendingIntentRequest? = null,
    val declineIntent: AndroidPendingIntentRequest? = null,
    val hangUpIntent: AndroidPendingIntentRequest? = null
) : Parcelable

/**
 * RemoteViews actions for custom-view notifications.
 */
@Parcelize
sealed class RemoteViewAction : Parcelable {
    @Parcelize
    data class SetText(val viewId: Int, val text: String) : RemoteViewAction()

    @Parcelize
    data class SetImage(val viewId: Int, val resId: Int) : RemoteViewAction()

    @Parcelize
    data class SetClickIntent(
        val viewId: Int,
        val pendingIntent: AndroidPendingIntentRequest
    ) : RemoteViewAction()
}

/**
 * Platform-specific options for custom-view notifications.
 *
 * @property viewActions List of RemoteViews actions to apply.
 */
@Parcelize
data class AndroidNotificationCustomViewPlatformOptions(
    val viewActions: List<RemoteViewAction> = emptyList()
) : Parcelable

/**
 * Android-specific platform options for notifications.
 *
 * @property largeIconBitmap Large icon bitmap. Do not combine with [NotificationContent.largeIconResId].
 * @property contentIntent PendingIntent fired when the notification body is tapped.
 * @property deleteIntent PendingIntent fired when the notification is dismissed.
 * @property fullScreenIntent PendingIntent for full-screen presentation.
 * @property actions List of action buttons.
 * @property callStyleOptions Call control options used with CallStyle.
 * @property customViewOptions RemoteViews options used with custom views.
 */
@Parcelize
data class AndroidNotificationPlatformOptions(
    val largeIconBitmap: Bitmap? = null,
    val contentIntent: AndroidPendingIntentRequest? = null,
    val deleteIntent: AndroidPendingIntentRequest? = null,
    val fullScreenIntent: AndroidPendingIntentRequest? = null,
    val actions: List<AndroidNotificationAction> = emptyList(),
    val callStyleOptions: AndroidNotificationCallPlatformOptions? = null,
    val customViewOptions: AndroidNotificationCustomViewPlatformOptions? = null
) : Parcelable

/**
 * Command object used to post a notification.
 *
 * @property content Notification content definition.
 * @property platformOptions Android-specific platform options.
 */
data class AndroidNotificationCommand(
    val content: NotificationContent,
    val platformOptions: AndroidNotificationPlatformOptions = AndroidNotificationPlatformOptions()
)
