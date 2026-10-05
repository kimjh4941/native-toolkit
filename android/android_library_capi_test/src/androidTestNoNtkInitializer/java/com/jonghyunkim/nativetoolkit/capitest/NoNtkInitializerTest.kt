package com.jonghyunkim.nativetoolkit.capitest

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi.InitResult
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * NtkInitializer removed and LibraryInitializer kept: the Kotlin side is done at app start, but
 * nothing tells C, so the app calls the manual initialization (design part 1, 5.3).
 */
@RunWith(AndroidJUnit4::class)
class NoNtkInitializerTest {

    @Test
    fun theCPathMakesItReady() {
        assertTrue(LibraryRuntime.isInitialized())
        NtkTestNative.load()
        assertEquals(0, NtkTestNative.isInitialized())
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        assertEquals(1, NtkTestNative.isInitialized())
    }

    @Test
    fun theKotlinPathMakesItReady() {
        assertTrue(LibraryRuntime.isInitialized())
        assertFalse(NativeToolkitCApi.isInitialized)
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
        NtkTestNative.load()
        assertEquals(1, NtkTestNative.isInitialized())
    }
}
