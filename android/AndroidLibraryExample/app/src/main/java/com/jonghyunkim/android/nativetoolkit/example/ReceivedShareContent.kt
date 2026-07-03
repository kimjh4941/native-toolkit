package com.jonghyunkim.android.nativetoolkit.example

/**
 * Content received from another app or a Direct Share target.
 *
 * @property action Received intent action (ACTION_SEND / ACTION_SEND_MULTIPLE).
 * @property mimeType Received intent type.
 * @property text Received text (EXTRA_TEXT), or null.
 * @property streamUris Received stream URIs (EXTRA_STREAM), or empty.
 * @property shortcutId Selected Direct Share target id (EXTRA_SHORTCUT_ID); null for a normal share.
 */
data class ReceivedShareContent(
    val action: String,
    val mimeType: String?,
    val text: String?,
    val streamUris: List<android.net.Uri>,
    val shortcutId: String?
)
