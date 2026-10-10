package com.jonghyunkim.nativetoolkit.capitest

import androidx.test.core.app.ActivityScenario
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * The GoogleTest cases of libntk_test.so, one JUnit case each (AC-14), so that a failure names the
 * case and test_android.sh can count them. A failure's detail is in logcat under the tag ntk_test.
 */
@RunWith(Parameterized::class)
class NtkGoogleTest(private val case: String) {

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<String> {
            NtkTestNative.load()
            return NtkTestNative.listCases().toList()
        }
    }

    private var scenario: ActivityScenario<FocusActivity>? = null

    // The clipboard cases read the clipboard and wait for its change events, which need the
    // window focus (design part 1, 5.8). Every case gets it; the others do not mind.
    @Before
    fun focus() {
        ClipboardControl.context = appContext
        val launched = ActivityScenario.launch(FocusActivity::class.java)
        scenario = launched
        assertTrue("the test Activity did not get the window focus", waitUntil {
            var focused = false
            launched.onActivity { focused = it.hasWindowFocus() }
            focused
        })
    }

    // A case that opened another app's screen (the settings, the Sharesheet) closes it with Back.
    // The next case must not start while that screen is still closing: once, its task was removed
    // with the next case's process in it ("remove task"), and that case's result was lost.
    @After
    fun closeFocus() {
        UiDriver.backToApp()
        for (pkg in listOf("com.android.settings", "com.android.intentresolver")) UiDriver.packageGone(pkg)
        scenario?.close()
    }

    @Test
    fun run() {
        NtkTestNative.load()
        assertTrue("GoogleTest case $case failed; see logcat tag ntk_test", NtkTestNative.runCase(case))
    }
}
