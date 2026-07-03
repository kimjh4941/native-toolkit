package android.library.share.data

import android.content.Intent
import android.library.share.data.repository.CallbackResult
import android.library.share.data.repository.ShareCallbackResultParser
import android.os.Build
import android.service.chooser.ChooserResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareCallbackResultParserTest {

    // JVM-only tests cover the pre-35 branch (Build.VERSION.SDK_INT == 0).
    // API 35 path (ChooserResult) requires instrumented tests on real hardware.

    @Test
    fun parse_nullIntent_returnsSelectedWithNullOnPre35() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val result = ShareCallbackResultParser.parse(null)
        assertTrue(result is CallbackResult.Selected)
        assertNull((result as CallbackResult.Selected).packageName)
    }

    @Test
    fun parse_intentWithoutChosenComponent_returnsSelectedWithNull() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val result = ShareCallbackResultParser.parse(Intent())
        assertTrue(result is CallbackResult.Selected)
        assertNull((result as CallbackResult.Selected).packageName)
    }

    @Test
    fun parse_anyIntentOnPre35_returnsSelected() {
        // On pre-35, all intents (regardless of content) map to Selected since there is no
        // non-selection action type in the old callback API.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val result = ShareCallbackResultParser.parse(Intent("some.action"))
        assertTrue("Expected Selected on pre-35 path", result is CallbackResult.Selected)
    }

    @Test
    fun mapApi35Result_selectedComponent_returnsSelectedPackage() {
        val result = ShareCallbackResultParser.mapApi35Result(
            ChooserResult.CHOOSER_RESULT_SELECTED_COMPONENT,
            "com.example.target"
        )

        assertEquals(CallbackResult.Selected("com.example.target"), result)
    }

    @Test
    fun mapApi35Result_copyEditAndUnknown_returnIgnored() {
        val nonSelectionTypes = listOf(
            ChooserResult.CHOOSER_RESULT_COPY,
            ChooserResult.CHOOSER_RESULT_EDIT,
            ChooserResult.CHOOSER_RESULT_UNKNOWN
        )

        nonSelectionTypes.forEach { type ->
            assertEquals(CallbackResult.Ignored, ShareCallbackResultParser.mapApi35Result(type, null))
        }
    }
}
