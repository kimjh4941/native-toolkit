package com.jonghyunkim.nativetoolkit.capitest

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** The automatic path: androidx.startup runs NtkInitializer at app start (design part 1, 1.4). */
@RunWith(AndroidJUnit4::class)
class AutomaticInitTest {

    @Before
    fun load() = NtkTestNative.load()

    @Test
    fun startupInitializedTheCAbi() {
        assertEquals(1, NtkTestNative.isInitialized())
        assertTrue(NativeToolkitCApi.isInitialized)
        assertTrue(NativeToolkitCApi.isAvailable)
    }

    @Test
    fun theManualPathsAfterwardsChangeNothing() {
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        assertEquals(NativeToolkitCApi.InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
        assertEquals(1, NtkTestNative.isInitialized())
    }

    @Test
    fun aSecondLibraryRunsJniOnLoadAgainAndChangesNothing() {
        assertEquals(1, jniOnLoadRuns())
        System.loadLibrary("ntk_second")
        assertEquals(2, jniOnLoadRuns())
        assertEquals(1, NtkTestNative.isInitialized())
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
    }

    @Test
    fun aNullEnvOrContextIsAnInvalidParameter() {
        assertEquals(AndroidError.INVALID_PARAMETER, NtkTestNative.init(null))
        assertEquals(AndroidError.INVALID_PARAMETER, NtkTestNative.initWithoutEnv(appContext))
    }
}
