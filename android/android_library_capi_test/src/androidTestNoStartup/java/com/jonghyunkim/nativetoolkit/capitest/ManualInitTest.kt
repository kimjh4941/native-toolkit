package com.jonghyunkim.nativetoolkit.capitest

import android.system.Os
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi.InitResult
import com.jonghyunkim.nativetoolkit.capi.NtkInitializer
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The manual paths, with androidx.startup removed from the app (design part 1, 1.4, 5.3 and
 * chapter 6). Every test runs in a new process, so each starts with nothing initialized.
 */
@RunWith(AndroidJUnit4::class)
class ManualInitTest {

    @Test
    fun withoutStartupNothingIsInitialized() {
        NtkTestNative.load()
        assertFalse(LibraryRuntime.isInitialized())
        assertEquals(0, NtkTestNative.isInitialized())
        assertFalse(NativeToolkitCApi.isInitialized)
    }

    @Test
    fun anOperationBeforeInitializationIsRejectedAndReleasedAtOnce() {
        // The probe operation of debug builds goes through the same entry checks as the features.
        NtkTestNative.load()
        val (error, releasedHere, id) = NtkTestNative.probeStartRejected().toList()
        assertEquals(2, error) // NOT_INITIALIZED (part 2, AP-12)
        assertEquals(1, releasedHere)
        assertEquals(0, id)
    }

    @Test
    fun clipboardOperationsBeforeInitializationAreNotInitialized() {
        // Design part 1, chapter 6 and part 2, 12.1 (未初期化), moved from TB-1 to TB-3.
        NtkTestNative.load()
        val result = NtkTestNative.clipboardUninitialized().toList()
        assertEquals(listOf(2, 2, 1, 2, 1, 1, 1), result)
    }

    @Test
    fun afterTheCPathWithAnActivityADialogShows() {
        // Design part 1, chapter 6 (moved from TB-1 to TB-4): with Startup removed nothing tracks
        // Activities until the manual initialization, so the Activity passed in must be taken as
        // the foreground at once.
        ActivityScenario.launch(FocusActivity::class.java).use { scenario ->
            NtkTestNative.load()
            var activity: FocusActivity? = null
            scenario.onActivity { activity = it }
            assertEquals(AndroidError.NONE, NtkTestNative.init(activity))
            assertEquals(0, NtkTestNative.showAlert("After the manual path"))
            assertTrue(UiDriver.waitText("After the manual path"))
            assertTrue(UiDriver.click("OK"))
            assertEquals(listOf(0, 1), NtkTestNative.awaitAlert().toList())
        }
    }

    @Test
    fun anActivityPassedInAndSentBackIsNotForeground() {
        ActivityScenario.launch(FocusActivity::class.java).use { scenario ->
            NtkTestNative.load()
            var activity: FocusActivity? = null
            scenario.onActivity { activity = it }
            assertEquals(AndroidError.NONE, NtkTestNative.init(activity))
            assertTrue(UiDriver.home())
            assertEquals(0, NtkTestNative.showAlert("Sent back"))
            assertEquals(listOf(8, 1), NtkTestNative.awaitAlert().toList()) // NOT_FOREGROUND
        }
    }

    @Test
    fun theNotificationBuildersWorkBeforeInitialization() {
        NtkTestNative.load()
        assertEquals(0, NtkTestNative.isInitialized())
        assertEquals(listOf(0, 0, 0, 0), NtkTestNative.buildersUninitialized().toList())
    }

    @Test
    fun theCPathInitializesWithoutJniOnLoad() {
        // libntk.so is opened by the linker only, as with dlopen: JNI_OnLoad has not run, and
        // ntk_android_init must not make it run (it does not call System.loadLibrary).
        NtkTestNative.load()
        val (result, took) = timed { NtkTestNative.init(appContext) }
        assertEquals(AndroidError.NONE, result)
        assertTrue("took $took ms", took < NO_WAIT_MS)
        assertEquals(1, NtkTestNative.isInitialized())
        assertTrue(LibraryRuntime.isInitialized())
        assertTrue(NativeToolkitCApi.isInitialized)
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        assertEquals(0, jniOnLoadRuns())
    }

    @Test
    fun theKotlinPathInitializes() {
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
        NtkTestNative.load()
        assertEquals(1, NtkTestNative.isInitialized())
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
        assertEquals(1, jniOnLoadRuns())
    }

    @Test
    fun aNullEnvOrContextIsAnInvalidParameter() {
        NtkTestNative.load()
        assertEquals(AndroidError.INVALID_PARAMETER, NtkTestNative.init(null))
        assertEquals(AndroidError.INVALID_PARAMETER, NtkTestNative.initWithoutEnv(appContext))
        assertEquals(0, NtkTestNative.isInitialized())
    }

    @Test
    fun theAutomaticAndManualPathsAtOnceNeverWaitAndEndReady() {
        NtkTestNative.load()
        val barrier = CyclicBarrier(3)
        val pool = Executors.newFixedThreadPool(3)
        val automatic = pool.submit<Pair<Any, Long>> { barrier.await(); timed { NtkInitializer().create(appContext) } }
        val c = pool.submit<Pair<Any, Long>> { barrier.await(); timed { NtkTestNative.init(appContext) } }
        val kotlin = pool.submit<Pair<Any, Long>> { barrier.await(); timed { NativeToolkitCApi.init(appContext) } }
        for (future in listOf(automatic, c, kotlin)) {
            val (_, took) = future.get(10, TimeUnit.SECONDS)
            assertTrue("took $took ms", took < NO_WAIT_MS)
        }
        assertTrue(c.get().first in setOf(AndroidError.NONE, AndroidError.IN_PROGRESS))
        assertTrue(kotlin.get().first in setOf(InitResult.INITIALIZED, InitResult.IN_PROGRESS))
        pool.shutdown()
        // Whoever lost a race calls again, as the contract says; the state ends READY.
        assertTrue(waitUntil {
            NtkTestNative.init(appContext) == AndroidError.NONE && NtkTestNative.isInitialized() == 1
        })
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
    }

    @Test
    fun theStateIsNotReadyWhileTheKotlinSideIsInProgress() {
        NtkTestNative.load()
        val latched = LatchedContext(appContext)
        val pool = Executors.newSingleThreadExecutor()
        val held = pool.submit<Int> { NtkTestNative.init(latched) }
        assertTrue(latched.awaitHeld())

        assertEquals(0, NtkTestNative.isInitialized())
        assertFalse(NativeToolkitCApi.isInitialized)
        val (c, tookC) = timed { NtkTestNative.init(appContext) }
        assertEquals(AndroidError.IN_PROGRESS, c)
        assertTrue("took $tookC ms", tookC < NO_WAIT_MS)
        val (kotlin, tookKotlin) = timed { NativeToolkitCApi.init(appContext) }
        assertEquals(InitResult.IN_PROGRESS, kotlin)
        assertTrue("took $tookKotlin ms", tookKotlin < NO_WAIT_MS)
        assertEquals(0, NtkTestNative.isInitialized())

        latched.release()
        assertEquals(AndroidError.NONE, held.get(10, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals(1, NtkTestNative.isInitialized())
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
    }

    @Test
    fun aFailedKotlinSideCanBeRetried() {
        NtkTestNative.load()
        val broken = BrokenContext(appContext)
        assertEquals(AndroidError.JNI_FAILURE, NtkTestNative.init(broken))
        assertEquals(InitResult.RETRYABLE_ERROR, NativeToolkitCApi.init(broken))
        assertFalse(LibraryRuntime.isInitialized())
        assertEquals(0, NtkTestNative.isInitialized())

        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        assertEquals(1, NtkTestNative.isInitialized())
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
    }

    @Test
    fun afterAFailedJniOnLoadKotlinNeedsTheCInit() {
        // Debug builds of libntk.so fail JNI_OnLoad on purpose while this is set.
        Os.setenv("NTK_TEST_FAIL_JNI_ONLOAD", "1", true)
        try {
            assertEquals(InitResult.NATIVE_SETUP_REQUIRED, NativeToolkitCApi.init(appContext))
        } finally {
            Os.unsetenv("NTK_TEST_FAIL_JNI_ONLOAD")
        }
        // The runtime does not run JNI_OnLoad again, so Kotlin alone still cannot help.
        assertEquals(InitResult.NATIVE_SETUP_REQUIRED, NativeToolkitCApi.init(appContext))
        assertFalse(NativeToolkitCApi.isInitialized)

        NtkTestNative.load()
        assertEquals(0, NtkTestNative.isInitialized())
        assertEquals(AndroidError.NONE, NtkTestNative.init(appContext))
        assertEquals(1, NtkTestNative.isInitialized())
        assertEquals(InitResult.INITIALIZED, NativeToolkitCApi.init(appContext))
    }

    @Test
    fun ntkInitializerReachesReadyWhenLibraryInitializerIsStillInProgress() {
        val latched = LatchedContext(appContext)
        val pool = Executors.newSingleThreadExecutor()
        val held = pool.submit<LibraryRuntime.InitState> { LibraryRuntime.ensureInitialized(latched) }
        assertTrue(latched.awaitHeld())

        val (_, took) = timed { NtkInitializer().create(appContext) }
        assertTrue("took $took ms", took < NO_WAIT_MS)
        assertFalse(NativeToolkitCApi.isInitialized)

        latched.release()
        assertEquals(LibraryRuntime.InitState.DONE, held.get(10, TimeUnit.SECONDS))
        pool.shutdown()
        // LibraryRuntime tells the C ABI on the main thread once it is done (design 5.3).
        assertTrue(waitUntil { NativeToolkitCApi.isInitialized })
    }
}
