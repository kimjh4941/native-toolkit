package com.jonghyunkim.nativetoolkit.notification.presentation.event

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import org.json.JSONObject

/**
 * Builds the PendingIntent requests that deliver notification taps, actions and dismissals to
 * [NotificationEvents] (Kotlin API design 8.5).
 *
 * Put the results into `AndroidNotificationPlatformOptions`. Each request is told apart by its data
 * URI, so the request code is always 0 and two notifications never share a PendingIntent. The
 * receiver class names are compatibility identifiers: scheduled notifications store them.
 */
object NotificationEventIntents {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents"

    /** The action of every event intent. Never change it (Kotlin API design 8.5). */
    internal const val ACTION_EVENT: String = "com.jonghyunkim.nativetoolkit.notification.action.EVENT"

    /** The data URI scheme of event intents. Never change it. */
    internal const val SCHEME_EVENT: String = "ntk-notification-event"

    /** The extra holding the data map as a JSON object string. Never change it. */
    internal const val EXTRA_DATA: String = "com.jonghyunkim.nativetoolkit.notification.extra.DATA"

    /** The identifier prefix of full-screen launch intents. Never change it. */
    internal const val IDENTIFIER_LAUNCH_PREFIX: String = "ntk-notification-launch/"

    /**
     * A body tap.
     *
     * @param context Any Context.
     * @param notificationId The notification ID.
     * @param tag The notification tag, or `null`.
     * @param data Strings delivered with the event.
     * @param launchApp Whether the tap also opens the app.
     */
    fun bodyTap(
        context: Context,
        notificationId: Int,
        tag: String?,
        data: Map<String, String> = emptyMap(),
        launchApp: Boolean = true
    ): AndroidPendingIntentRequest {
        Log.d(TAG, "[bodyTap] notificationId: $notificationId, tag: $tag, dataKeys: ${data.keys}, launchApp: $launchApp")
        return eventRequest(context, NotificationInteraction.Kind.BODY_TAP, notificationId, tag, null, data, launchApp)
    }

    /**
     * An action button or a custom-view click target.
     *
     * @param context Any Context.
     * @param notificationId The notification ID.
     * @param tag The notification tag, or `null`.
     * @param actionId The action ID delivered with the event.
     * @param data Strings delivered with the event.
     * @param launchApp Whether the tap also opens the app.
     */
    fun action(
        context: Context,
        notificationId: Int,
        tag: String?,
        actionId: String,
        data: Map<String, String> = emptyMap(),
        launchApp: Boolean = false
    ): AndroidPendingIntentRequest {
        Log.d(TAG, "[action] notificationId: $notificationId, tag: $tag, actionId: $actionId, dataKeys: ${data.keys}, launchApp: $launchApp")
        return eventRequest(context, NotificationInteraction.Kind.ACTION, notificationId, tag, actionId, data, launchApp)
    }

    /**
     * A dismissal (use as the delete intent).
     *
     * @param context Any Context.
     * @param notificationId The notification ID.
     * @param tag The notification tag, or `null`.
     * @param data Strings delivered with the event.
     */
    fun dismiss(
        context: Context,
        notificationId: Int,
        tag: String?,
        data: Map<String, String> = emptyMap()
    ): AndroidPendingIntentRequest {
        Log.d(TAG, "[dismiss] notificationId: $notificationId, tag: $tag, dataKeys: ${data.keys}")
        return eventRequest(context, NotificationInteraction.Kind.DISMISS, notificationId, tag, null, data, launchApp = false)
    }

    /**
     * A full-screen intent that opens the app's launch Activity, or `null` when the app has none.
     *
     * No data URI is added (the app would read it as a deep link); `Intent.setIdentifier` tells the
     * requests apart instead.
     *
     * @param context Any Context.
     * @param notificationId The notification ID.
     * @param tag The notification tag, or `null`.
     */
    fun fullScreenLaunch(context: Context, notificationId: Int, tag: String?): AndroidPendingIntentRequest? {
        Log.d(TAG, "[fullScreenLaunch] notificationId: $notificationId, tag: $tag")
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        launch.identifier = "$IDENTIFIER_LAUNCH_PREFIX$notificationId/${tagField(tag)}"
        return AndroidPendingIntentRequest(
            intent = launch,
            requestCode = 0,
            type = AndroidPendingIntentType.ACTIVITY,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun eventRequest(
        context: Context,
        kind: NotificationInteraction.Kind,
        notificationId: Int,
        tag: String?,
        actionId: String?,
        data: Map<String, String>,
        launchApp: Boolean
    ): AndroidPendingIntentRequest {
        val target = if (launchApp) NotificationLaunchActivity::class.java else NotificationEventReceiver::class.java
        val intent = Intent(context, target)
            .setAction(ACTION_EVENT)
            .setData(eventUri(context.packageName, kind, notificationId, tag, actionId))
        if (data.isNotEmpty()) intent.putExtra(EXTRA_DATA, JSONObject(data).toString())
        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = 0,
            type = if (launchApp) AndroidPendingIntentType.ACTIVITY else AndroidPendingIntentType.BROADCAST,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun tagField(tag: String?): String = if (tag == null) "n" else "t$tag"

    private fun eventUri(
        packageName: String,
        kind: NotificationInteraction.Kind,
        notificationId: Int,
        tag: String?,
        actionId: String?
    ): Uri = Uri.Builder()
        .scheme(SCHEME_EVENT)
        .authority(packageName)
        .appendPath(kind.name)
        .appendPath(notificationId.toString())
        .appendPath(tagField(tag))
        .appendPath(if (actionId == null) "n" else "a$actionId")
        .build()

    /**
     * Reads an event intent back, or returns `null` when it is not one.
     *
     * @param intent The received intent.
     */
    internal fun parse(intent: Intent?): NotificationInteraction? {
        Log.d(TAG, "[parse] intent: $intent")
        val uri = intent?.data ?: return null
        if (intent.action != ACTION_EVENT || uri.scheme != SCHEME_EVENT) return null
        val segments = uri.pathSegments
        if (segments.size != 4) return null
        val kind = NotificationInteraction.Kind.entries.firstOrNull { it.name == segments[0] } ?: return null
        val notificationId = segments[1].toIntOrNull() ?: return null
        val tag = segments[2].takeIf { it.startsWith("t") }?.substring(1)
        val actionId = segments[3].takeIf { it.startsWith("a") }?.substring(1)
        val data = intent.getStringExtra(EXTRA_DATA)?.let { json ->
            runCatching {
                val obj = JSONObject(json)
                obj.keys().asSequence().associateWith { obj.getString(it) }
            }.getOrElse {
                Log.e(TAG, "[parse] unreadable data extra", it)
                emptyMap()
            }
        } ?: emptyMap()
        return NotificationInteraction(kind, notificationId, tag, actionId, data)
    }
}
