package com.example.capitest

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

object NtkGTest {
    @JvmStatic external fun runAll(): Int
}

/** Runs the GoogleTest cases in libntk_test.so; each case is logged under the tag ntk_test. */
@RunWith(AndroidJUnit4::class)
class NtkGTestRunner {
    @Test
    fun googleTests() {
        System.loadLibrary("ntk_test")
        assertEquals("GoogleTest failures (see logcat tag ntk_test)", 0, NtkGTest.runAll())
    }
}
