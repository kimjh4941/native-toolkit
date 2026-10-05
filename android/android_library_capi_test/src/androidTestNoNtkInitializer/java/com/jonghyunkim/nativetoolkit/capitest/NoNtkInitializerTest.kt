package com.jonghyunkim.nativetoolkit.capitest

import androidx.test.core.app.ActivityScenario
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

    @Test
    fun thePermissionDialogIsCanceledDeniedThenGranted() {
        // Part 2, 12.2: the system's permission dialog pressed for a request made from C. This
        // flavor's fresh install has not been asked yet; the steps run in one test because the
        // answers stay with the install.
        val allow = "com.android.permissioncontroller:id/permission_allow_button"
        val deny = "com.android.permissioncontroller:id/permission_deny_button"
        NtkTestNative.load()
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        // No Activity yet and not granted: NOT_FOREGROUND with DENIED (part 2, 12.1 the foreground, OP-38).
        assertTrue(NtkTestNative.requestPermission() > 0)
        assertEquals(listOf(8, 1), NtkTestNative.awaitPermission(1).toList())

        ActivityScenario.launch(FocusActivity::class.java).use {
            // Two requests share one dialog (the Kotlin library's behaviour). The first is canceled
            // while it is up: CANCELED, and the dialog stays for the second, which gets the denial.
            val first = NtkTestNative.requestPermission()
            assertTrue("request: $first", first > 0)
            assertTrue(UiDriver.waitRes(allow))
            assertTrue(NtkTestNative.requestPermission() > 0)
            NtkTestNative.cancelPermission(first)
            assertEquals(listOf(6, 1), NtkTestNative.awaitPermission(2).toList())
            assertTrue(UiDriver.clickRes(deny))
            assertEquals(listOf(0, 1), NtkTestNative.awaitPermission(3).toList())
            assertTrue(UiDriver.waitGoneRes(deny))

            // Asked again once that dialog is gone, and allowed: GRANTED.
            assertTrue(NtkTestNative.requestPermission() > 0)
            assertTrue(UiDriver.clickRes(allow))
            assertEquals(listOf(0, 0), NtkTestNative.awaitPermission(4).toList())

            // Granted already: GRANTED without a dialog.
            assertTrue(NtkTestNative.requestPermission() > 0)
            assertEquals(listOf(0, 0), NtkTestNative.awaitPermission(5).toList())
        }
    }
}
