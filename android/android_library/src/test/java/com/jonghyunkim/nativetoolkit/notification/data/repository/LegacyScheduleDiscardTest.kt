package com.jonghyunkim.nativetoolkit.notification.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// UT-05 of the Kotlin API design: the 1.x key parsing and the discard states of 8.6.
class LegacyScheduleDiscardTest {

    private class FakeEnv(var keys: List<String?> = emptyList()) : LegacyScheduleEnvironment {
        var marked = false
        var preferencesPresent = true
        val canceled = mutableListOf<Pair<Int, String?>>()
        val failingCancels = mutableSetOf<Int>()
        var deleteFails = false
        var markFails = false
        var keysThrow: Exception? = null
        var onCancel: (() -> Unit)? = null
        var keyReads = 0

        override fun isMarked() = marked
        override fun legacyKeys(): List<String?> {
            keyReads++
            keysThrow?.let { throw it }
            return if (preferencesPresent) keys else emptyList()
        }
        override fun cancelAlarm(id: Int, tag: String?) {
            onCancel?.invoke()
            if (id in failingCancels) throw IllegalStateException("cancel $id")
            canceled += id to tag
        }
        override fun deletePreferences(): Boolean {
            if (deleteFails) return false
            preferencesPresent = false
            return true
        }
        override fun mark(): Boolean {
            if (markFails) return false
            marked = true
            return true
        }
    }

    private val discard = LegacyScheduleDiscard()

    @Test
    fun parse_untagged_isNoTag() {
        assertEquals(1 to null, LegacyScheduleDiscard.parseLegacyKey("untagged::1"))
    }

    @Test
    fun parse_splitsAtTheLastSeparator() {
        assertEquals(2 to "a::b", LegacyScheduleDiscard.parseLegacyKey("a::b::2"))
    }

    @Test
    fun parse_tagWithoutSeparator() {
        assertEquals(-5 to "news", LegacyScheduleDiscard.parseLegacyKey("news::-5"))
    }

    @Test
    fun parse_notAnInteger_orNoSeparator_isNull() {
        assertNull(LegacyScheduleDiscard.parseLegacyKey("a::b"))
        assertNull(LegacyScheduleDiscard.parseLegacyKey("a::"))
        assertNull(LegacyScheduleDiscard.parseLegacyKey("12"))
        assertNull(LegacyScheduleDiscard.parseLegacyKey(""))
    }

    @Test
    fun allCanceled_deletesThePreferences_marks_andIsDone() {
        val env = FakeEnv(listOf("untagged::1", "t::2"))
        assertTrue(discard.runOnce(env))
        assertEquals(listOf(1 to null, 2 to "t"), env.canceled)
        assertFalse(env.preferencesPresent)
        assertTrue(env.marked)
        assertTrue(discard.isDone())
    }

    @Test
    fun done_doesNotRunAgain() {
        val env = FakeEnv(listOf("untagged::1"))
        discard.runOnce(env)
        assertTrue(discard.runOnce(env))
        assertEquals(1, env.keyReads)
    }

    @Test
    fun marked_isDoneWithoutReadingTheEntries() {
        val env = FakeEnv(listOf("untagged::1")).apply { marked = true }
        assertTrue(discard.runOnce(env))
        assertEquals(0, env.keyReads)
        assertTrue(env.preferencesPresent)
    }

    @Test
    fun unparsableOrUnreadableEntries_areSkipped_withoutCountingAsFailures() {
        val env = FakeEnv(listOf("bad", null, "untagged::3"))
        assertTrue(discard.runOnce(env))
        assertEquals(listOf(3 to null), env.canceled)
        assertTrue(env.marked)
    }

    @Test
    fun aFailedCancel_goesOnWithTheRest_keepsThePreferences_doesNotMark_andRetries() {
        val env = FakeEnv(listOf("untagged::1", "untagged::2", "untagged::3")).apply { failingCancels += 2 }
        assertFalse(discard.runOnce(env))
        assertEquals(listOf(1 to null, 3 to null), env.canceled)
        assertTrue(env.preferencesPresent)
        assertFalse(env.marked)
        assertFalse(discard.isDone())

        env.failingCancels.clear()
        assertTrue(discard.runOnce(env))
        assertTrue(env.marked)
        assertFalse(env.preferencesPresent)
    }

    @Test
    fun deleteFails_doesNotMark_andRetries() {
        val env = FakeEnv(listOf("untagged::1")).apply { deleteFails = true }
        assertFalse(discard.runOnce(env))
        assertFalse(env.marked)
        env.deleteFails = false
        assertTrue(discard.runOnce(env))
        assertTrue(env.marked)
    }

    @Test
    fun onlyTheMarkFails_theRetryGoesOnWithNoEntries() {
        val env = FakeEnv(listOf("untagged::1")).apply { markFails = true }
        assertFalse(discard.runOnce(env))
        assertFalse(env.preferencesPresent)
        assertFalse(discard.isDone())

        env.markFails = false
        assertTrue(discard.runOnce(env))
        assertEquals(listOf(1 to null), env.canceled)
        assertTrue(env.marked)
    }

    @Test
    fun anExceptionWhileReading_goesBackToNotStarted() {
        val env = FakeEnv(listOf("untagged::1")).apply { keysThrow = IllegalStateException("read") }
        assertFalse(discard.runOnce(env))
        assertFalse(discard.isDone())
        env.keysThrow = null
        assertTrue(discard.runOnce(env))
    }

    @Test
    fun whileRunning_anotherCallDoesNothing() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val env = FakeEnv(listOf("untagged::1")).apply {
            onCancel = {
                entered.countDown()
                release.await(5, TimeUnit.SECONDS)
            }
        }
        val first = Thread { discard.runOnce(env) }.apply { start() }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val second = FakeEnv(listOf("untagged::9"))
        assertFalse(discard.runOnce(second))
        assertEquals(0, second.keyReads)
        release.countDown()
        first.join(5_000)
        assertTrue(discard.isDone())
    }
}
