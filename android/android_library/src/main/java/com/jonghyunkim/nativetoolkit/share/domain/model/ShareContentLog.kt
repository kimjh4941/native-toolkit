package com.jonghyunkim.nativetoolkit.share.domain.model

/**
 * Describes [ShareContent] for logs without the shared text or subject.
 *
 * `ShareContent.toString()` is public behavior and stays unchanged, so log sites call this instead.
 */
internal fun ShareContent.logSafeDescription(): String =
    "textLength: ${text.length}, hasTitle: ${title != null}, hasSubject: ${subject != null}, mimeType: $mimeType"
