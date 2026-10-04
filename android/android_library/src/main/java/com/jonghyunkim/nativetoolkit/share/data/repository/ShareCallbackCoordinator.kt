package com.jonghyunkim.nativetoolkit.share.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.service.chooser.ChooserResult
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.jonghyunkim.nativetoolkit.common.runtime.ProcessNonce
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection
import com.jonghyunkim.nativetoolkit.share.presentation.ShareEvents

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

/**
 * The result Intent of a share request (Kotlin API design 8.9): action [ACTION_RESULT], data
 * `ntk-share-result://<package>/<process nonce>/<token>`, limited to this package.
 */
internal object ShareResultIntents {

    private const val TAG = "com.jonghyunkim.nativetoolkit.share.data.repository.ShareResultIntents"

    const val ACTION_RESULT: String = "com.jonghyunkim.nativetoolkit.share.action.RESULT"
    const val SCHEME_RESULT: String = "ntk-share-result"

    /**
     * Builds the result Intent of [token].
     *
     * @param context Any Context.
     * @param nonce The process nonce.
     * @param token The request's token.
     */
    fun intent(context: Context, nonce: Long, token: Long): Intent {
        Log.d(TAG, "[intent] nonce: $nonce, token: $token")
        val uri = Uri.Builder()
            .scheme(SCHEME_RESULT)
            .authority(context.packageName)
            .appendPath(nonce.toString())
            .appendPath(token.toString())
            .build()
        return Intent(ACTION_RESULT, uri).setPackage(context.packageName)
    }

    /**
     * The filter of the receiver: the action and the scheme and authority of the data.
     *
     * @param context Any Context.
     */
    fun filter(context: Context): IntentFilter {
        Log.d(TAG, "[filter] context: $context")
        return IntentFilter(ACTION_RESULT).apply {
            addDataScheme(SCHEME_RESULT)
            addDataAuthority(context.packageName, null)
        }
    }

    /**
     * Reads the nonce and the token from a result Intent, or `null`.
     *
     * @param intent The received Intent.
     */
    fun nonceAndToken(intent: Intent?): Pair<Long, Long>? {
        Log.d(TAG, "[nonceAndToken] intent: $intent")
        val segments = intent?.data?.takeIf { it.scheme == SCHEME_RESULT }?.pathSegments ?: return null
        if (segments.size != 2) return null
        val nonce = segments[0].toLongOrNull() ?: return null
        val token = segments[1].toLongOrNull() ?: return null
        return nonce to token
    }
}

/** What a share request waits for. */
internal sealed interface ShareWaitMode {
    /** The existing `shareWithCallback`: [onSelected] for a pick, then [onFinished] once. */
    class Callback(val onSelected: (String?) -> Unit, val onFinished: () -> Unit) : ShareWaitMode {
        override fun toString(): String = "Callback"
    }

    /** `shareForSelection`: a pick becomes a selection event. */
    data object Event : ShareWaitMode
}

/**
 * The single wait for a share result in this process (Kotlin API design 8.9).
 *
 * Each request gets a token, and its result Intent carries the process nonce and the token, so a
 * result of an older Sharesheet or an earlier process is dropped. Opening a new one replaces the
 * wait (the old wait's onFinished is not called, as before). Inside the lock only the token is
 * checked and the wait taken out; user functions and events run outside it.
 *
 * @param nonce The process nonce in the result URIs.
 * @param ensureReceiver Registers the one result receiver of the process; called under the lock
 *   until it succeeds.
 * @param emitSelection Delivers a selection event; called on the main thread.
 */
internal class ShareCallbackCoordinator(
    val nonce: Long,
    private val ensureReceiver: () -> Unit,
    private val emitSelection: (ShareSelection) -> Unit
) {

    private class Pending(val token: Long, val mode: ShareWaitMode)

    private val lock = Any()
    private var receiverRegistered = false
    private var pending: Pending? = null
    private var nextToken: Long = 0L

    /**
     * Starts waiting for a new request, replacing the current wait.
     *
     * @param mode What to do with the result.
     * @return The token of the request; the first one is 1.
     */
    fun register(mode: ShareWaitMode): Long = synchronized(lock) {
        Log.d(TAG, "[register] mode: $mode")
        if (!receiverRegistered) {
            ensureReceiver()
            receiverRegistered = true
        }
        val token = ++nextToken
        pending = Pending(token, mode)
        token
    }

    /**
     * Handles a received result. Main thread.
     *
     * @param nonce The nonce in the result URI.
     * @param token The token in the result URI.
     * @param result The parsed result.
     */
    fun deliver(nonce: Long, token: Long, result: CallbackResult) {
        Log.d(TAG, "[deliver] nonce: $nonce, token: $token, result: $result")
        val mode = synchronized(lock) {
            val current = pending
            if (nonce != this.nonce || current == null || current.token != token) {
                null
            } else {
                pending = null
                current.mode
            }
        }
        if (mode == null) {
            Log.d(TAG, "[deliver] stale or cancelled request; ignoring")
            return
        }
        when (mode) {
            is ShareWaitMode.Callback -> try {
                if (result is CallbackResult.Selected) mode.onSelected(result.packageName)
            } finally {
                mode.onFinished()
            }
            ShareWaitMode.Event -> if (result is CallbackResult.Selected) {
                emitSelection(ShareSelection(token, result.packageName))
            }
        }
    }

    /**
     * Stops waiting only when [token] is the current wait (the launch-failure path and
     * `cancelShareSelection`).
     *
     * @param token The request's token.
     */
    fun cancel(token: Long) = synchronized(lock) {
        Log.d(TAG, "[cancel] token: $token")
        if (pending?.token == token) pending = null
    }

    /** Returns the token of the current wait, or `null`. */
    fun currentToken(): Long? = synchronized(lock) {
        Log.d(TAG, "[currentToken]")
        pending?.token
    }

    /** Stops waiting for the current request (explicit cancel). */
    fun cancel() = synchronized(lock) {
        Log.d(TAG, "[cancel]")
        pending = null
    }

    companion object {
        private const val TAG = "ShareCallbackCoordinator"

        @Volatile private var instance: ShareCallbackCoordinator? = null

        /**
         * Returns the process-wide coordinator. Nothing is registered until the first request.
         *
         * @param context Any Context.
         */
        fun get(context: Context): ShareCallbackCoordinator {
            Log.d(TAG, "[get] context: $context")
            return instance ?: synchronized(this) {
                instance ?: create(context.applicationContext).also { instance = it }
            }
        }

        private fun create(appContext: Context): ShareCallbackCoordinator {
            Log.d(TAG, "[create] appContext: $appContext")
            lateinit var coordinator: ShareCallbackCoordinator
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    Log.d(TAG, "[onReceive] intent: $intent")
                    val (nonce, token) = ShareResultIntents.nonceAndToken(intent) ?: return
                    coordinator.deliver(nonce, token, ShareCallbackResultParser.parse(intent))
                }
            }
            coordinator = ShareCallbackCoordinator(
                nonce = ProcessNonce.value,
                ensureReceiver = {
                    ContextCompat.registerReceiver(
                        appContext,
                        receiver,
                        ShareResultIntents.filter(appContext),
                        ContextCompat.RECEIVER_NOT_EXPORTED
                    )
                },
                emitSelection = { ShareEvents.selections.emit(it) }
            )
            return coordinator
        }
    }
}
