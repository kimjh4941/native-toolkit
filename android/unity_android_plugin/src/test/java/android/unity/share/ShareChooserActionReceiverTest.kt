package android.unity.share

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ShareChooserActionReceiverTest {

    @Test
    fun onReceive_withAction_forwardsToOnAction() {
        var received: String? = null
        val receiver = ShareChooserActionReceiver { received = it }

        receiver.onReceive(null, FakeIntent("com.example.ACTION_EDIT"))

        assertEquals("com.example.ACTION_EDIT", received)
    }

    @Test
    fun onReceive_nullAction_doesNotCallOnAction() {
        var received: String? = null
        val receiver = ShareChooserActionReceiver { received = it }

        receiver.onReceive(null, FakeIntent(null))

        assertNull(received)
    }

    @Test
    fun onReceive_nullIntent_doesNotCallOnAction() {
        var received: String? = null
        val receiver = ShareChooserActionReceiver { received = it }

        receiver.onReceive(null, null)

        assertNull(received)
    }

    @Test
    fun onReceive_onActionThrows_propagatesToCaller() {
        val receiver = ShareChooserActionReceiver { throw RuntimeException("Unity error") }

        // ShareChooserActionReceiver itself does not catch; encapsulation is in dispatchChooserAction.
        // This test confirms the receiver propagates so the Manager can wrap with try/catch.
        var threw = false
        try {
            receiver.onReceive(null, FakeIntent("com.example.ACTION"))
        } catch (_: RuntimeException) {
            threw = true
        }
        assertEquals(true, threw)
    }

    // Intent stub's getAction() returns null on JVM; override to return the desired action.
    private class FakeIntent(private val fakeAction: String?) : Intent() {
        override fun getAction(): String? = fakeAction
    }
}
