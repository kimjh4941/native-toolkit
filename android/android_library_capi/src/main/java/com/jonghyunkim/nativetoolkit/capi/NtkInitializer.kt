package com.jonghyunkim.nativetoolkit.capi

import android.content.Context
import android.util.Log
import androidx.startup.Initializer
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryInitializer

/**
 * Initializes the C ABI at app start through androidx.startup (C ABI design part 1, 1.4). It runs
 * after [LibraryInitializer], which registers the foreground Activity tracker. An app installed as
 * 32-bit has no libntk.so; this logs that and does not crash the app (design 5.3).
 */
class NtkInitializer : Initializer<Unit> {

    override fun create(context: Context) {
        Log.d(TAG, "[create] context: $context")
        val result = NativeToolkitCApi.init(context)
        if (result != NativeToolkitCApi.InitResult.INITIALIZED) {
            Log.w(TAG, "[create] the C ABI is not initialized at app start: $result")
        }
    }

    override fun dependencies(): List<Class<out Initializer<*>>> {
        Log.d(TAG, "[dependencies]")
        return listOf(LibraryInitializer::class.java)
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.capi.NtkInitializer"
    }
}
