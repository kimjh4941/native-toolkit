package android.library.share.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.chooser.ChooserResult
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat

internal interface ShareCallbackReceiverRegistry {
    fun register(receiver: BroadcastReceiver, action: String)
    fun unregister(receiver: BroadcastReceiver)
}

private class AndroidShareCallbackReceiverRegistry(
    private val appContext: Context
) : ShareCallbackReceiverRegistry {
    override fun register(receiver: BroadcastReceiver, action: String) {
        Log.d(TAG, "[register] receiver: $receiver, action: $action")
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            IntentFilter(action),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun unregister(receiver: BroadcastReceiver) {
        Log.d(TAG, "[unregister] receiver: $receiver")
        appContext.unregisterReceiver(receiver)
    }

    private companion object {
        private const val TAG = "AndroidShareCallbackReceiverRegistry"
    }
}

// Internal result distinguishing an app selection from non-selection actions (Copy/Edit/Unknown).
internal sealed interface CallbackResult {
    data class Selected(val packageName: String?) : CallbackResult
    data object Ignored : CallbackResult
}

internal object ShareCallbackResultParser {

    private const val TAG = "ShareCallbackResultParser"

    fun parse(intent: Intent?): CallbackResult {
        Log.d(TAG, "[parse] intent: $intent")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            parseApi35(intent)
        } else {
            // Pre-35 callback fires only on an app selection.
            @Suppress("DEPRECATION")
            val pkg = intent?.getParcelableExtra<android.content.ComponentName>(Intent.EXTRA_CHOSEN_COMPONENT)?.packageName
            CallbackResult.Selected(pkg)
        }
    }

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    private fun parseApi35(intent: Intent?): CallbackResult {
        Log.d(TAG, "[parseApi35] intent: $intent")
        val result = intent?.extras
            ?.getParcelable("android.intent.extra.CHOOSER_RESULT", ChooserResult::class.java)
            ?: return CallbackResult.Ignored
        // Only a component selection maps to a package callback. Copy/Edit/Unknown are ignored.
        return mapApi35Result(result.type, result.selectedComponent?.packageName)
    }

    internal fun mapApi35Result(type: Int, selectedPackageName: String?): CallbackResult {
        Log.d(TAG, "[mapApi35Result] type: $type, selectedPackageName: $selectedPackageName")
        return if (type == ChooserResult.CHOOSER_RESULT_SELECTED_COMPONENT) {
            CallbackResult.Selected(selectedPackageName)
        } else {
            CallbackResult.Ignored
        }
    }
}

// Application-scoped single owner of the share-callback BroadcastReceiver.
// All public methods are synchronized; safe to call from any thread.
internal class ShareCallbackCoordinator(
    private val appContext: Context,
    private val receiverRegistry: ShareCallbackReceiverRegistry =
        AndroidShareCallbackReceiverRegistry(appContext)
) {

    private val lock = Any()
    private data class PendingRegistration(
        val token: Long,
        val receiver: BroadcastReceiver
    )

    private var pending: PendingRegistration? = null
    private var nextToken: Long = 0L

    /** Registers a one-shot receiver, replacing any previous pending one. Returns a token for cancel(token). */
    fun register(
        action: String,
        onSelected: (String?) -> Unit,
        onFinished: () -> Unit = {}
    ): Long = synchronized(lock) {
        Log.d(TAG, "[register] action: $action")
        unregisterLocked()
        val token = ++nextToken
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                Log.d(TAG, "[onReceive] ctx: $ctx, intent: $intent")
                val claimed = synchronized(lock) {
                    val current = pending
                    if (current?.token != token || current.receiver !== this) {
                        false
                    } else {
                        unregisterLocked()
                        true
                    }
                }
                if (!claimed) {
                    Log.d(TAG, "[onReceive] stale or cancelled registration; ignoring")
                    return
                }
                try {
                    when (val r = ShareCallbackResultParser.parse(intent)) {
                        is CallbackResult.Selected -> onSelected(r.packageName)
                        CallbackResult.Ignored -> Log.d(TAG, "[onReceive] non-selection action; not notifying")
                    }
                } finally {
                    onFinished()
                }
            }
        }
        pending = PendingRegistration(token, receiver)
        try {
            receiverRegistry.register(receiver, action)
        } catch (e: RuntimeException) {
            if (pending?.token == token) pending = null
            throw e
        }
        token
    }

    /** Unregisters only if the given token is still the current registration (launch-failure path). */
    fun cancel(token: Long) = synchronized(lock) {
        Log.d(TAG, "[cancel] token: $token")
        if (pending?.token == token) unregisterLocked()
    }

    /** Unconditionally unregisters the current pending receiver (explicit cancel / teardown). */
    fun cancel() = synchronized(lock) {
        Log.d(TAG, "[cancel]")
        unregisterLocked()
    }

    private fun unregisterLocked() {
        pending?.let {
            runCatching { receiverRegistry.unregister(it.receiver) }
            pending = null
        }
    }

    companion object {
        private const val TAG = "ShareCallbackCoordinator"

        @Volatile private var instance: ShareCallbackCoordinator? = null

        /** Returns the application-scoped singleton (one per process). */
        fun get(context: Context): ShareCallbackCoordinator {
            Log.d(TAG, "[get] context: $context")
            return instance ?: synchronized(this) {
                instance ?: ShareCallbackCoordinator(context.applicationContext).also { instance = it }
            }
        }
    }
}
