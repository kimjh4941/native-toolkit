package com.jonghyunkim.nativetoolkit.common.logging

import androidx.annotation.RestrictTo

/**
 * Hides values that may be secret (clipboard text, dialog input, share text) before they reach logcat.
 *
 * This is a logging helper, so it does not log its own calls (agent-rules/coding-rules/android.md,
 * "秘密の値を伏せる（例外）").
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object LogRedaction {

    /**
     * Returns `<redacted, length=N>` for a value, or `null` for a null value.
     *
     * @param value The value to hide.
     * @return A string that shows only the length of [value].
     */
    fun redact(value: CharSequence?): String =
        if (value == null) "null" else "<redacted, length=${value.length}>"
}
