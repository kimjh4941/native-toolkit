package com.jonghyunkim.nativetoolkit.common

import com.jonghyunkim.nativetoolkit.common.event.EventHub
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// UT-02 of the Kotlin API design: delivery, retention and removal during delivery.
class EventHubTest {

    private fun retainingHub(capacity: Int = 32) =
        EventHub<Int>(EventHub.Retention.UntilFirstListener(capacity)) { }

    private fun plainHub() = EventHub<Int>(EventHub.Retention.None) { }

    @Test
    fun emitWithListeners_deliversToEveryListenerInOrder() {
        val hub = plainHub()
        val a = mutableListOf<Int>()
        val b = mutableListOf<Int>()
        hub.addListener { e, _ -> a += e }
        hub.addListener { e, _ -> b += e }
        hub.emit(1)
        hub.emit(2)
        assertEquals(listOf(1, 2), a)
        assertEquals(listOf(1, 2), b)
    }

    @Test
    fun nonRetainingHub_dropsEventsWithoutListeners() {
        val hub = plainHub()
        hub.emit(1)
        val got = mutableListOf<Int>()
        hub.addListener { e, _ -> got += e }
        assertTrue(got.isEmpty())
    }

    @Test
    fun retainedEvents_goToTheFirstListenerInsideAddListener_inArrivalOrder() {
        val hub = retainingHub()
        hub.emit(1)
        hub.emit(2)
        val first = mutableListOf<Int>()
        hub.addListener { e, _ -> first += e }
        assertEquals(listOf(1, 2), first)
        val second = mutableListOf<Int>()
        hub.addListener { e, _ -> second += e }
        assertTrue(second.isEmpty())
    }

    @Test
    fun retention_dropsTheOldestBeyondCapacity() {
        val hub = retainingHub(capacity = 32)
        (1..40).forEach { hub.emit(it) }
        val got = mutableListOf<Int>()
        hub.addListener { e, _ -> got += e }
        assertEquals((9..40).toList(), got)
    }

    @Test
    fun listenerRemovingItselfDuringRetainedDelivery_leavesTheRestRetained() {
        val hub = retainingHub()
        (1..3).forEach { hub.emit(it) }
        val first = mutableListOf<Int>()
        hub.addListener { e, registration ->
            first += e
            registration.remove()
        }
        assertEquals(listOf(1), first)
        val next = mutableListOf<Int>()
        hub.addListener { e, _ -> next += e }
        assertEquals(listOf(2, 3), next)
    }

    @Test
    fun listenerAddedInsideRetainedDelivery_getsTheRestAfterTheFirstRemovesItself() {
        val hub = retainingHub()
        (1..3).forEach { hub.emit(it) }
        val inner = mutableListOf<Int>()
        val outer = mutableListOf<Int>()
        hub.addListener { e, registration ->
            outer += e
            hub.addListener { e2, _ -> inner += e2 }
            registration.remove()
        }
        assertEquals(listOf(1), outer)
        assertEquals(listOf(2, 3), inner)
    }

    @Test
    fun listenerAddedInsideRetainedDelivery_doesNotTakeTheRestFromTheFirst() {
        val hub = retainingHub()
        (1..3).forEach { hub.emit(it) }
        val inner = mutableListOf<Int>()
        val outer = mutableListOf<Int>()
        var added = false
        hub.addListener { e, _ ->
            outer += e
            if (!added) {
                added = true
                hub.addListener { e2, _ -> inner += e2 }
            }
        }
        assertEquals(listOf(1, 2, 3), outer)
        assertTrue(inner.isEmpty())
    }

    @Test
    fun removedListenerIsNotCalledEvenWithinTheSameEmit() {
        val hub = plainHub()
        val got = mutableListOf<String>()
        lateinit var second: EventHub.Registration
        hub.addListener { e, _ ->
            got += "a$e"
            second.remove()
        }
        second = hub.addListener { e, _ -> got += "b$e" }
        hub.emit(1)
        assertEquals(listOf("a1"), got)
    }

    @Test
    fun throwingListener_doesNotStopTheOthers() {
        val hub = plainHub()
        val got = mutableListOf<Int>()
        hub.addListener { _, _ -> throw IllegalStateException("boom") }
        hub.addListener { e, _ -> got += e }
        hub.emit(7)
        assertEquals(listOf(7), got)
    }

    @Test
    fun removeTwice_doesNothing() {
        val hub = plainHub()
        val got = mutableListOf<Int>()
        val registration = hub.addListener { e, _ -> got += e }
        registration.remove()
        registration.remove()
        hub.emit(1)
        assertTrue(got.isEmpty())
    }

    @Test
    fun removeOffTheMainThread_throws_andTheListenerStaysRegistered() {
        var onMain = true
        val hub = EventHub<Int>(EventHub.Retention.None) { name -> check(onMain) { "$name must be called on the main thread" } }
        val got = mutableListOf<Int>()
        val registration = hub.addListener { e, _ -> got += e }
        onMain = false
        val error = runCatching { registration.remove() }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertEquals("EventHub.Registration.remove must be called on the main thread", error?.message)
        onMain = true
        hub.emit(1)
        assertEquals(listOf(1), got)
        registration.remove()
        hub.emit(2)
        assertEquals(listOf(1), got)
    }
}
