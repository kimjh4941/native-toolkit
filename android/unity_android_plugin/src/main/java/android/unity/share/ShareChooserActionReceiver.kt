package android.unity.share

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Dynamically-registered receiver for custom chooser action taps (API 34+).
 *
 * Forwards the tapped action string (Intent.action) to [onAction].
 * Registered/unregistered by [ShareChooserActionReceiverRegistry]; never declared in the
 * manifest, so Unity may use arbitrary intentAction strings.
 */
internal class ShareChooserActionReceiver(
    private val onAction: (String) -> Unit
) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent, action: ${intent?.action}")
        val action = intent?.action ?: return
        onAction(action)
    }

    companion object {
        private const val TAG = "android.unity.share.ShareChooserActionReceiver"
    }
}
