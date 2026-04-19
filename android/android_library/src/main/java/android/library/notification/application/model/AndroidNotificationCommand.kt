package android.library.notification.application.model

import android.content.Intent
import android.graphics.Bitmap
import android.os.Parcelable
import android.library.notification.domain.model.NotificationContent
import kotlinx.parcelize.Parcelize

enum class AndroidPendingIntentType {
    ACTIVITY,
    BROADCAST,
    SERVICE,
    FOREGROUND_SERVICE
}

@Parcelize
data class AndroidPendingIntentRequest(
    val intent: Intent,
    val requestCode: Int,
    val type: AndroidPendingIntentType = AndroidPendingIntentType.ACTIVITY,
    val flags: Int = 0,
    val mutable: Boolean = false
) : Parcelable

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

@Parcelize
data class AndroidNotificationCallPlatformOptions(
    val answerIntent: AndroidPendingIntentRequest? = null,
    val declineIntent: AndroidPendingIntentRequest? = null,
    val hangUpIntent: AndroidPendingIntentRequest? = null
) : Parcelable

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

@Parcelize
data class AndroidNotificationCustomViewPlatformOptions(
    val viewActions: List<RemoteViewAction> = emptyList()
) : Parcelable

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

data class AndroidNotificationCommand(
    val content: NotificationContent,
    val platformOptions: AndroidNotificationPlatformOptions = AndroidNotificationPlatformOptions()
)
