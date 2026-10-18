package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log

/**
 * The error values 0 to 5 that every feature shares (C ABI design part 2, AP-12, chapter 11),
 * and the mapping of an exception that no feature table names. Each bridge maps its own
 * exceptions first and falls back to [common].
 */
internal object Errors {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.Errors"

    const val NONE = 0
    const val INVALID_PARAMETER = 1
    const val NOT_INITIALIZED = 2
    const val NOT_SUPPORTED = 3
    const val UNKNOWN = 4
    const val OUT_OF_MEMORY = 5

    /**
     * The shared value for [error]: an IllegalArgumentException is INVALID_PARAMETER, running out
     * of memory is OUT_OF_MEMORY, anything else UNKNOWN. Logs the class name only; a message may
     * hold user data (design 5.12).
     */
    fun common(error: Throwable): Int {
        Log.d(TAG, "[common] error: ${error.javaClass.name}")
        return when (error) {
            is IllegalArgumentException -> INVALID_PARAMETER
            is OutOfMemoryError -> OUT_OF_MEMORY
            else -> UNKNOWN
        }
    }
}
