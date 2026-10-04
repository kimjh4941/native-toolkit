package com.jonghyunkim.android.nativetoolkit.example

import android.content.Context
import android.util.Log
import android.widget.Toast
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationShown
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * The sample's one listener of the library's notification and chooser-action events
 * (sample app design 4.2). It replaces the sample's three BroadcastReceivers.
 *
 * MainActivity registers it in onCreate and removes it in onDestroy. Events of the notification
 * screen are passed to the screen while it collects [notificationEvents]; otherwise actions,
 * dismissals and chooser actions become toasts with the texts the old receivers used.
 */
object SampleEvents {

    private const val TAG = "SampleEvents"

    /** The label of an action or a dismissal, carried in the event's data. */
    const val DATA_LABEL = "label"

    private val events = MutableSharedFlow<Any>(replay = 0, extraBufferCapacity = 64)

    /** [NotificationInteraction] and [NotificationShown] for the notification screen. Not replayed. */
    val notificationEvents: SharedFlow<Any> = events.asSharedFlow()

    /**
     * Registers the listeners. Main thread only. Events the library kept while no listener was
     * registered are delivered inside this call.
     *
     * @param context The Activity; toasts use its application context.
     * @return The registrations, to remove in onDestroy.
     */
    fun register(context: Context): List<EventHub.Registration> {
        Log.d(TAG, "[register] context: $context")
        val appContext = context.applicationContext
        val notifications = AndroidNotificationManager.getInstance(context)
        val share = AndroidShareManager.getInstance(context)
        return listOf(
            notifications.interactions.addListener { event, _ -> onInteraction(appContext, event) },
            notifications.shown.addListener { event, _ -> forward(event) },
            share.chooserActions.addListener { id, _ ->
                Log.d(TAG, "[chooserAction] id: $id")
                toast(appContext, "Custom chooser action tapped")
            }
        )
    }

    private fun onInteraction(context: Context, event: NotificationInteraction) {
        Log.d(TAG, "[onInteraction] event: $event")
        val label = event.data[DATA_LABEL] ?: "Notification"
        when (event.kind) {
            NotificationInteraction.Kind.DISMISS -> toast(context, "$label dismissed (deleteIntent)")
            NotificationInteraction.Kind.ACTION -> if (!forward(event)) toast(context, "$label action pressed")
            NotificationInteraction.Kind.BODY_TAP -> forward(event)
        }
    }

    // Passes the event to the notification screen when it is shown. A full buffer drops the event.
    private fun forward(event: Any): Boolean {
        Log.d(TAG, "[forward] event: $event, subscribers: ${events.subscriptionCount.value}")
        if (events.subscriptionCount.value == 0) return false
        val sent = events.tryEmit(event)
        if (!sent) Log.w(TAG, "[forward] the screen's buffer is full; dropping $event")
        return sent
    }

    private fun toast(context: Context, text: String) {
        Log.d(TAG, "[toast] text: $text")
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }
}

/**
 * Passes a result to the screen that is shown now (sample app design 4.2; implementation review
 * I-X2, I-X3). Library callbacks can outlive the Activity that asked for them: a dialog or the
 * permission request survives MainActivity's recreation, and its callback would otherwise update
 * the state of the old composition. The shown screen attaches its state; a result with no screen
 * attached is only logged. Main thread only.
 *
 * @param name The name in logs.
 */
class ScreenResultSink(private val name: String) {

    private var target: ((String) -> Unit)? = null

    /**
     * Makes [target] receive the results.
     *
     * @param target Updates the screen's state.
     * @return Detaches [target], unless another one replaced it since.
     */
    fun attach(target: (String) -> Unit): () -> Unit {
        Log.d(TAG, "[attach] name: $name, target: $target")
        this.target = target
        return {
            Log.d(TAG, "[detach] name: $name, target: $target")
            if (this.target === target) this.target = null
        }
    }

    /**
     * Delivers [text] to the attached screen.
     *
     * @param text The result text.
     */
    fun deliver(text: String) {
        Log.d(TAG, "[deliver] name: $name, textLength: ${text.length}")
        target?.invoke(text) ?: Log.d(TAG, "[deliver] no screen is attached; dropping the result of $name")
    }

    private companion object {
        private const val TAG = "ScreenResultSink"
    }
}

/** The result sinks of the screens whose results can outlive the Activity. */
object ScreenResults {
    /** The dialog screen's result, held by the router. */
    val dialog = ScreenResultSink("dialog")

    /** The notification screen's status text, for the permission request callback. */
    val notificationStatus = ScreenResultSink("notificationStatus")
}
