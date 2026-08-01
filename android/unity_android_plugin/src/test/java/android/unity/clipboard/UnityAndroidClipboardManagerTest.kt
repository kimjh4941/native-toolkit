package android.unity.clipboard

import android.content.ContextWrapper
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit tests for [UnityAndroidClipboardManager].
 *
 * Under the local JVM unit test stub (isReturnDefaultValues=true), ContextCompat.getSystemService
 * for ClipboardManager returns null, so all real-clipboard paths deterministically surface
 * [android.library.clipboard.domain.error.ClipboardDomainError.ClipboardUnavailable]. This is used
 * here to verify that the synchronous read()/getDescription() JSON contract surfaces an
 * identifiable error rather than silently collapsing to "null", and that copy() failures are
 * reported through the operation listener without ever logging clipboard content.
 */
class UnityAndroidClipboardManagerTest {

    @After
    fun tearDown() {
        UnityAndroidClipboardManager.clearClipboardOperationListener()
        UnityAndroidClipboardManager.clearClipboardChangeListener()
    }

    @Test
    fun read_clipboardUnavailable_returnsIdentifiableErrorJson() {
        val json = UnityAndroidClipboardManager.read(FakeContext())

        assertFalse("empty-clipboard normal case must not be confused with a failure", json == "null")
        val obj = JSONObject(json)
        assertEquals("CLIPBOARD_UNAVAILABLE", obj.getString("error"))
        assertTrue(obj.getString("message").isNotBlank())
    }

    @Test
    fun getDescription_clipboardUnavailable_returnsIdentifiableErrorJson() {
        val json = UnityAndroidClipboardManager.getDescription(FakeContext())

        assertFalse(json == "null")
        val obj = JSONObject(json)
        assertEquals("CLIPBOARD_UNAVAILABLE", obj.getString("error"))
    }

    @Test
    fun hasClip_clipboardUnavailable_returnsFalse() {
        assertEquals("false", UnityAndroidClipboardManager.hasClip(FakeContext()))
    }

    @Test
    fun copyPlainText_clipboardServiceFailure_notifiesFailureWithoutThrowing() {
        // Under the JVM unit-test stub, Context.getContentResolver() (touched before the
        // ClipboardManager lookup) returns null, so this deterministically fails before reaching
        // the clipboard service. The point under test is that the failure is reported through the
        // listener (never thrown) and never echoes clipboard content in the message.
        val listener = CapturingListener()
        UnityAndroidClipboardManager.setClipboardOperationListener(listener)

        UnityAndroidClipboardManager.copyPlainText(FakeContext(), """{"text":"hello"}""")

        assertEquals(UnityAndroidClipboardManager.OPERATION_COPY_PLAIN_TEXT, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().isNotBlank())
        assertFalse("copied text must not be echoed in the error message", listener.errorMessage.orEmpty().contains("hello"))
    }

    @Test
    fun copyPlainText_invalidJson_notifiesFailureAndDoesNotLeakContentInMessage() {
        val listener = CapturingListener()
        UnityAndroidClipboardManager.setClipboardOperationListener(listener)

        UnityAndroidClipboardManager.copyPlainText(FakeContext(), "not json")

        assertFalse(listener.isSuccessful ?: true)
    }

    @Test
    fun copyUri_blankUri_notifiesInvalidUriFailure() {
        val listener = CapturingListener()
        UnityAndroidClipboardManager.setClipboardOperationListener(listener)

        UnityAndroidClipboardManager.copyUri(FakeContext(), """{"uri":""}""")

        assertEquals(UnityAndroidClipboardManager.OPERATION_COPY_URI, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().startsWith("Invalid URI"))
    }

    private class CapturingListener : UnityAndroidClipboardManager.ClipboardOperationListener {
        var operation: String? = null
        var isSuccessful: Boolean? = null
        var errorMessage: String? = null

        override fun onClipboardOperation(operation: String, isSuccessful: Boolean, errorMessage: String?) {
            this.operation = operation
            this.isSuccessful = isSuccessful
            this.errorMessage = errorMessage
        }
    }

    private class FakeContext : ContextWrapper(null) {
        override fun getPackageName(): String = "com.example.clipboard.test"
        override fun getApplicationContext(): android.content.Context = this
    }
}
