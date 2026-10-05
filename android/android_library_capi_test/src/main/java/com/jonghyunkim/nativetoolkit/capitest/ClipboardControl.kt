package com.jonghyunkim.nativetoolkit.capitest

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context

/** Puts a clip on the clipboard from Kotlin, for text C cannot write (unpaired surrogates, U+0000). */
object ClipboardControl {

    /** Set by the GoogleTest runner before each case. */
    @Volatile
    var context: Context? = null

    @JvmStatic
    fun setText(text: String) {
        val clipboard = checkNotNull(context).getSystemService(ClipboardManager::class.java)
        clipboard.setPrimaryClip(ClipData.newPlainText("kotlin", text))
    }
}
