package android.unity.share

import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Registers/unregisters the dynamic chooser-action receiver with generation tracking.
 *
 * Implementations isolate the SDK gate and registration side effects so the manager logic
 * (normalization, generation, failure cleanup, replacement) is testable without a device.
 */
internal interface ShareChooserActionReceiverRegistry {
    /**
     * Registers a receiver for [actionIds], replacing any previous registration.
     *
     * @param actionIds Distinct, non-blank action strings to listen for.
     * @param onAction Invoked with the tapped action string.
     * @return A positive generation token, or 0 if nothing was registered
     *         (below API 34, empty list, or registration failure).
     */
    fun register(actionIds: List<String>, onAction: (String) -> Unit): Long

    /**
     * Unregisters the current receiver only if [token] matches the current generation.
     *
     * @param token Generation token returned by [register].
     */
    fun unregister(token: Long)
}

internal class AndroidShareChooserActionReceiverRegistry(
    private val appContext: Context
) : ShareChooserActionReceiverRegistry {

    private val lock = Any()
    private var currentToken = 0L
    private var currentReceiver: BroadcastReceiver? = null

    override fun register(actionIds: List<String>, onAction: (String) -> Unit): Long {
        Log.d(TAG, "[register] actionIds: $actionIds")
        // Custom actions only appear on API 34+. Below that the library ignores them.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return 0L
        synchronized(lock) {
            unregisterCurrentLocked()
            if (actionIds.isEmpty()) return 0L
            val receiver = ShareChooserActionReceiver(onAction)
            val filter = IntentFilter().apply { actionIds.forEach { addAction(it) } }
            return try {
                ContextCompat.registerReceiver(
                    appContext, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
                )
                currentReceiver = receiver
                currentToken += 1
                currentToken
            } catch (e: Exception) {
                Log.e(TAG, "[register] failed to register receiver", e)
                currentReceiver = null
                0L
            }
        }
    }

    override fun unregister(token: Long) {
        Log.d(TAG, "[unregister] token: $token, currentToken: $currentToken")
        synchronized(lock) {
            if (token == 0L || token != currentToken) return
            unregisterCurrentLocked()
        }
    }

    private fun unregisterCurrentLocked() {
        val receiver = currentReceiver ?: return
        try {
            appContext.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Benign: receiver was already unregistered.
            // Documented exception to the Log.e rule: this is an expected race, not an error.
            Log.w(TAG, "[unregisterCurrentLocked] receiver not registered", e)
        } finally {
            currentReceiver = null
        }
    }

    private companion object {
        private const val TAG = "android.unity.share.AndroidShareChooserActionReceiverRegistry"
    }
}
