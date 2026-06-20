package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.IntentCompat

/**
 * Converts a received [Intent] to [ReceivedShareContent].
 *
 * Returns null for non-share intents (action is not ACTION_SEND or ACTION_SEND_MULTIPLE).
 */
object IncomingShareParser {

    private const val TAG = "IncomingShareParser"

    /**
     * Converts a received intent to [ReceivedShareContent]; returns null if it is not a share intent.
     *
     * @param intent Received intent (nullable).
     */
    fun parse(intent: Intent?): ReceivedShareContent? {
        Log.d(TAG, "[parse] intent: $intent, action: ${intent?.action}")
        if (intent == null) return null
        val shortcutId = intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                // EXTRA_TEXT is a CharSequence (may be Spanned); read as CharSequence then stringify.
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                val uri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                ReceivedShareContent(
                    action = Intent.ACTION_SEND,
                    mimeType = intent.type,
                    text = text,
                    streamUris = listOfNotNull(uri),
                    shortcutId = shortcutId
                )
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = IntentCompat.getParcelableArrayListExtra(
                    intent, Intent.EXTRA_STREAM, Uri::class.java
                ) ?: arrayListOf()
                ReceivedShareContent(
                    action = Intent.ACTION_SEND_MULTIPLE,
                    mimeType = intent.type,
                    text = null,
                    streamUris = uris,
                    shortcutId = shortcutId
                )
            }
            else -> null
        }
    }
}
