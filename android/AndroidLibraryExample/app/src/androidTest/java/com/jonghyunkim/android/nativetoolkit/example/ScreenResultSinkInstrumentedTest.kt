package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * [ScreenResultSink] (implementation review I-X2, I-X3): a result goes to the screen attached
 * last, also when the previous screen detaches after the next one attached, as happens when
 * MainActivity is recreated. Runs on the main thread, as the sink requires.
 */
@RunWith(AndroidJUnit4::class)
class ScreenResultSinkInstrumentedTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test
    fun theLaterScreenGetsTheResult_whenTheEarlierOneDetachesAfterIt() {
        val sink = ScreenResultSink("test")
        val old = mutableListOf<String>()
        val new = mutableListOf<String>()
        onMain {
            val detachOld = sink.attach { old += it }
            sink.attach { new += it }
            detachOld()
            sink.deliver("result")
        }
        assertEquals(emptyList<String>(), old)
        assertEquals(listOf("result"), new)
    }

    @Test
    fun theEarlierScreenDetachingFirst_thenTheLaterOneAttaching_alsoWorks() {
        val sink = ScreenResultSink("test")
        val old = mutableListOf<String>()
        val new = mutableListOf<String>()
        onMain {
            val detachOld = sink.attach { old += it }
            detachOld()
            sink.attach { new += it }
            sink.deliver("result")
        }
        assertEquals(emptyList<String>(), old)
        assertEquals(listOf("result"), new)
    }

    @Test
    fun noScreenAttached_dropsTheResult() {
        val sink = ScreenResultSink("test")
        val seen = mutableListOf<String>()
        onMain {
            sink.attach { seen += it }()
            sink.deliver("result")
        }
        assertEquals(emptyList<String>(), seen)
    }
}
