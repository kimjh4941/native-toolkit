package com.jonghyunkim.nativetoolkit.common.runtime

import android.content.Context
import android.util.Log
import androidx.startup.Initializer

/**
 * Initializes the library at app start through androidx.startup (Kotlin API design 8.1).
 *
 * Registered in the library manifest. Apps that disable Startup call
 * [LibraryRuntime.ensureInitialized] themselves.
 */
class LibraryInitializer : Initializer<Unit> {

    override fun create(context: Context) {
        Log.d(TAG, "[create] context: $context")
        LibraryRuntime.ensureInitialized(context)
    }

    override fun dependencies(): List<Class<out Initializer<*>>> {
        Log.d(TAG, "[dependencies]")
        return emptyList()
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.runtime.LibraryInitializer"
    }
}
