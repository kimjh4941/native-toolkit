package com.jonghyunkim.nativetoolkit.common.logging

import android.util.Log
import androidx.annotation.RestrictTo

/**
 * Hides values that may be secret (clipboard text, dialog input, share text) before they reach logcat.
 *
 * Its own log shows only the length of the value (agent-rules/coding-rules/android.md,
 * "秘密の値を伏せる（例外）").
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object LogRedaction {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.logging.LogRedaction"

    /**
     * Returns `<redacted, length=N>` for a value, or `null` for a null value.
     *
     * @param value The value to hide.
     * @return A string that shows only the length of [value].
     */
    fun redact(value: CharSequence?): String {
        Log.d(TAG, "[redact] length: ${value?.length}")
        return if (value == null) "null" else "<redacted, length=${value.length}>"
    }
}
