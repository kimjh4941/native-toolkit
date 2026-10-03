package com.jonghyunkim.android.nativetoolkit.testsharetarget

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Shows what a share intent carried, so the sample's UI tests can read it (U-10 of the
 * android-c-abi UI test design). It stores and sends nothing; Back closes it.
 */
class ShareTargetActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState, action: ${intent?.action}")
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val values = listOf(
            R.id.result_action to intent.action.orEmpty(),
            R.id.result_type to intent.type.orEmpty(),
            R.id.result_text to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString().orEmpty(),
            R.id.result_subject to intent.getStringExtra(Intent.EXTRA_SUBJECT).orEmpty(),
            R.id.result_title to intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString().orEmpty(),
            R.id.result_streams to describeStreams(streams())
        )
        for ((id, value) in values) {
            column.addView(TextView(this).apply {
                this.id = id
                text = value
                setPadding(PADDING, PADDING, PADDING, PADDING)
            })
        }
        // Targeting API 35 forces edge-to-edge; keep the values out from under the status bar so
        // UiAutomator sees them as visible.
        setContentView(ScrollView(this).apply {
            fitsSystemWindows = true
            addView(column)
        })
    }

    private fun streams(): List<Uri> {
        Log.d(TAG, "[streams]")
        return if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else {
            listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        }
    }

    /** One line per stream: display name, MIME type and content summary, after a count line. */
    private fun describeStreams(uris: List<Uri>): String {
        Log.d(TAG, "[describeStreams] uris: $uris")
        if (uris.isEmpty()) return "0"
        return buildString {
            append(uris.size)
            for (uri in uris) {
                append('\n').append(displayName(uri)).append(" | ").append(contentResolver.getType(uri)).append(" | ").append(summary(uri))
            }
        }
    }

    private fun displayName(uri: Uri): String {
        Log.d(TAG, "[displayName] uri: $uri")
        return runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull() ?: "(unknown)"
    }

    private fun summary(uri: Uri): String {
        Log.d(TAG, "[summary] uri: $uri")
        val type = contentResolver.getType(uri).orEmpty()
        return runCatching {
            if (type.startsWith("image/")) {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
                "${options.outWidth}x${options.outHeight}"
            } else {
                contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString().take(MAX_TEXT) }.orEmpty()
            }
        }.getOrElse { "(unreadable: ${it::class.java.simpleName})" }
    }

    private companion object {
        const val TAG = "com.jonghyunkim.android.nativetoolkit.testsharetarget.ShareTargetActivity"
        const val PADDING = 24
        const val MAX_TEXT = 200
    }
}
