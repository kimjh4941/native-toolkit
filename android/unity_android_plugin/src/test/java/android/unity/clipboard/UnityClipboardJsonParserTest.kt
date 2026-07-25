package android.unity.clipboard

import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UnityClipboardJsonParserTest {

    // --- parseCopyPlainText ---

    @Test
    fun parseCopyPlainText_fullJson_parsesAllFields() {
        val spec = UnityClipboardJsonParser.parseCopyPlainText(
            """{"text":"hello","label":"l","isSensitive":true}"""
        )
        assertEquals("hello", spec.text)
        assertEquals("l", spec.label)
        assertTrue(spec.isSensitive)
    }

    @Test
    fun parseCopyPlainText_missingOptionalFields_usesDefaults() {
        val spec = UnityClipboardJsonParser.parseCopyPlainText("""{"text":"hello"}""")
        assertEquals("", spec.label)
        assertEquals(false, spec.isSensitive)
    }

    @Test
    fun parseCopyPlainText_emptyTextField_isAllowed() {
        val spec = UnityClipboardJsonParser.parseCopyPlainText("""{"text":""}""")
        assertEquals("", spec.text)
    }

    @Test(expected = JSONException::class)
    fun parseCopyPlainText_missingTextKey_throwsJsonException() {
        UnityClipboardJsonParser.parseCopyPlainText("""{"label":"l"}""")
    }

    @Test(expected = JSONException::class)
    fun parseCopyPlainText_invalidJson_throwsJsonException() {
        UnityClipboardJsonParser.parseCopyPlainText("not json")
    }

    // --- parseCopyHtmlText ---

    @Test
    fun parseCopyHtmlText_fullJson_parsesAllFields() {
        val spec = UnityClipboardJsonParser.parseCopyHtmlText(
            """{"plainText":"hi","htmlText":"<b>hi</b>","label":"l","isSensitive":true}"""
        )
        assertEquals("hi", spec.plainText)
        assertEquals("<b>hi</b>", spec.htmlText)
        assertTrue(spec.isSensitive)
    }

    @Test(expected = JSONException::class)
    fun parseCopyHtmlText_missingHtmlTextKey_throwsJsonException() {
        UnityClipboardJsonParser.parseCopyHtmlText("""{"plainText":"hi"}""")
    }

    // --- parseCopyUri ---

    @Test
    fun parseCopyUri_fullJson_parsesAllFields() {
        val spec = UnityClipboardJsonParser.parseCopyUri(
            """{"uri":"content://media/1","label":"l","isSensitive":false}"""
        )
        assertEquals("content://media/1", spec.uri)
        assertEquals("l", spec.label)
    }

    @Test(expected = JSONException::class)
    fun parseCopyUri_missingUriKey_throwsJsonException() {
        UnityClipboardJsonParser.parseCopyUri("""{"label":"l"}""")
    }

    // --- parseCopyMultipleText ---

    @Test
    fun parseCopyMultipleText_fullJson_parsesAllFields() {
        val spec = UnityClipboardJsonParser.parseCopyMultipleText(
            """{"texts":["a","b"],"label":"l"}"""
        )
        assertEquals(listOf("a", "b"), spec.texts)
    }

    @Test
    fun parseCopyMultipleText_emptyArray_returnsEmptyList() {
        val spec = UnityClipboardJsonParser.parseCopyMultipleText("""{"texts":[]}""")
        assertTrue(spec.texts.isEmpty())
    }

    @Test(expected = JSONException::class)
    fun parseCopyMultipleText_missingTextsKey_throwsJsonException() {
        UnityClipboardJsonParser.parseCopyMultipleText("""{"label":"l"}""")
    }
}
