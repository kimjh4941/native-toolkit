package com.jonghyunkim.nativetoolkit.share.presentation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.util.Log
import androidx.core.content.ContextCompat
import com.jonghyunkim.nativetoolkit.common.runtime.ProcessNonce

/**
 * Receives taps on custom Sharesheet actions (Kotlin API design 8.9). One instance is registered
 * per process and stays registered.
 *
 * Each action's Intent carries the process nonce and the generation of its share in the data
 * URI. Every share with actions starts a new generation, so taps on the actions of an earlier
 * share, or of an earlier process, are dropped.
 */
internal class ShareChooserActionReceiver private constructor() : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "[onReceive] intent: $intent")
        val segments = intent.data?.takeIf { it.scheme == SCHEME_ACTION }?.pathSegments ?: return
        if (segments.size != 3) return
        val nonce = segments[0].toLongOrNull()
        val generation = segments[1].toLongOrNull()
        val id = segments[2]
        if (!isCurrent(nonce, generation)) {
            Log.d(TAG, "[onReceive] an action of an earlier share; ignoring")
            return
        }
        ShareEvents.chooserActions.emit(id)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.share.presentation.ShareChooserActionReceiver"

        const val ACTION_CHOOSER_ACTION: String = "com.jonghyunkim.nativetoolkit.share.action.CHOOSER_ACTION"
        const val SCHEME_ACTION: String = "ntk-share-action"

        private val lock = Any()
        private var registered = false
        private var generation = 0L

        /**
         * Registers the receiver if needed and starts a new generation; the actions of earlier
         * shares stop working.
         *
         * @param context Any Context.
         * @return The new generation.
         */
        fun nextGeneration(context: Context): Long = synchronized(lock) {
            Log.d(TAG, "[nextGeneration] context: $context")
            if (!registered) {
                val appContext = context.applicationContext
                val filter = IntentFilter(ACTION_CHOOSER_ACTION).apply {
                    addDataScheme(SCHEME_ACTION)
                    addDataAuthority(appContext.packageName, null)
                }
                ContextCompat.registerReceiver(appContext, ShareChooserActionReceiver(), filter, ContextCompat.RECEIVER_NOT_EXPORTED)
                registered = true
            }
            ++generation
        }

        /**
         * Builds the Intent of action [id] in [generation].
         *
         * @param context Any Context.
         * @param generation A value from [nextGeneration].
         * @param id The action ID.
         */
        fun intent(context: Context, generation: Long, id: String): Intent {
            Log.d(TAG, "[intent] generation: $generation, id: $id")
            val uri = Uri.Builder()
                .scheme(SCHEME_ACTION)
                .authority(context.packageName)
                .appendPath(ProcessNonce.value.toString())
                .appendPath(generation.toString())
                .appendPath(id)
                .build()
            return Intent(ACTION_CHOOSER_ACTION, uri).setPackage(context.packageName)
        }

        private fun isCurrent(nonce: Long?, actionGeneration: Long?): Boolean = synchronized(lock) {
            nonce == ProcessNonce.value && actionGeneration == generation
        }
    }
}
