package android.unity.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareChooserActionInputsTest {

    private fun spec(intentAction: String) =
        UnityChooserActionSpec(label = "Label", iconBase64 = "abc", intentAction = intentAction)

    @Test
    fun normalizeActionIds_blankActionsAreExcluded() {
        val specs = listOf(spec(""), spec("  "), spec("com.example.ACTION"))
        val result = ShareChooserActionInputs.normalizeActionIds(specs)
        assertEquals(listOf("com.example.ACTION"), result)
    }

    @Test
    fun normalizeActionIds_duplicatesAreRemoved() {
        val specs = listOf(spec("com.example.A"), spec("com.example.A"), spec("com.example.B"))
        val result = ShareChooserActionInputs.normalizeActionIds(specs)
        assertEquals(listOf("com.example.A", "com.example.B"), result)
    }

    @Test
    fun normalizeActionIds_defaultSendActionIsExcluded() {
        val specs = listOf(spec("android.intent.action.SEND"), spec("com.example.ACTION"))
        val result = ShareChooserActionInputs.normalizeActionIds(specs)
        // SEND is excluded because it is not a reliable callback identifier.
        assertEquals(listOf("com.example.ACTION"), result)
    }

    @Test
    fun normalizeActionIds_onlySendActionReturnsEmpty() {
        val specs = listOf(spec("android.intent.action.SEND"))
        val result = ShareChooserActionInputs.normalizeActionIds(specs)
        assertTrue(result.isEmpty())
    }

    @Test
    fun normalizeActionIds_emptyListReturnsEmpty() {
        val result = ShareChooserActionInputs.normalizeActionIds(emptyList())
        assertTrue(result.isEmpty())
    }
}
