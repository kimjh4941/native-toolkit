package com.jonghyunkim.nativetoolkit.capitest

import org.junit.Assert.assertTrue
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

    @Test
    fun run() {
        NtkTestNative.load()
        assertTrue("GoogleTest case $case failed; see logcat tag ntk_test", NtkTestNative.runCase(case))
    }
}
