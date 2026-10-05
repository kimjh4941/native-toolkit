package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log

/**
 * Strings between C and Kotlin (C ABI design part 1, 5.10, AC-8, AC-19). C checks its strings
 * as strict UTF-8 at the entry, so decoding never replaces anything. Encoding replaces what C
 * cannot hold: an unpaired surrogate and U+0000 become U+FFFD. Android's own encoder would turn
 * an unpaired surrogate into '?', so it only sees the replaced text.
 */
internal object Utf8 {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.Utf8"
    private const val REPLACEMENT = '�'

    /** Decodes bytes C has checked. */
    fun decode(bytes: ByteArray): String {
        Log.d(TAG, "[decode] size: ${bytes.size}")
        return bytes.decodeToString()
    }

    /** [decode] for a value that may be absent. */
    fun decodeOrNull(bytes: ByteArray?): String? {
        Log.d(TAG, "[decodeOrNull] size: ${bytes?.size}")
        return bytes?.let(::decode)
    }

    /** Encodes for C, replacing unpaired surrogates and U+0000 with U+FFFD. */
    fun encode(text: String): ByteArray {
        Log.d(TAG, "[encode] length: ${text.length}")
        return replaceForC(text).encodeToByteArray()
    }

    /** [encode] for a value that may be absent. */
    fun encodeOrNull(text: String?): ByteArray? {
        Log.d(TAG, "[encodeOrNull] length: ${text?.length}")
        return text?.let(::encode)
    }

    /** The text with unpaired surrogates and U+0000 replaced with U+FFFD. */
    fun replaceForC(text: String): String {
        Log.d(TAG, "[replaceForC] length: ${text.length}")
        val out = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                c == '\u0000' -> out.append(REPLACEMENT)
                c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate() -> {
                    out.append(c).append(text[i + 1])
                    i++
                }
                c.isSurrogate() -> out.append(REPLACEMENT)
                else -> out.append(c)
            }
            i++
        }
        return out.toString()
    }
}
