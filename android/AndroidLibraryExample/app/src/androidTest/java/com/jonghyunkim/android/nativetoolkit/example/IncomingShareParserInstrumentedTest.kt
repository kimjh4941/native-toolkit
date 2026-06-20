package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IncomingShareParserInstrumentedTest {

    @Test
    fun parse_actionSendText_returnsTextContent() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Hello from test")
        }

        val result = IncomingShareParser.parse(intent)

        assertNotNull(result)
        assertEquals(Intent.ACTION_SEND, result!!.action)
        assertEquals("text/plain", result.mimeType)
        assertEquals("Hello from test", result.text)
        assertTrue(result.streamUris.isEmpty())
        assertNull(result.shortcutId)
    }

    @Test
    fun parse_actionSendText_charSequenceExtraText_convertedToString() {
        val charSequence: CharSequence = StringBuilder("Spanned text")
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, charSequence)
        }

        val result = IncomingShareParser.parse(intent)

        assertNotNull(result)
        assertEquals("Spanned text", result!!.text)
    }

    @Test
    fun parse_actionSendStream_returnsSingleUri() {
        val uri = Uri.parse("content://com.example/image/1")
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
        }

        val result = IncomingShareParser.parse(intent)

        assertNotNull(result)
        assertEquals(Intent.ACTION_SEND, result!!.action)
        assertEquals("image/jpeg", result.mimeType)
        assertNull(result.text)
        assertEquals(1, result.streamUris.size)
        assertEquals(uri, result.streamUris[0])
    }

    @Test
    fun parse_actionSendMultiple_returnsMultipleUris() {
        val uri1 = Uri.parse("content://com.example/image/1")
        val uri2 = Uri.parse("content://com.example/image/2")
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "image/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(uri1, uri2))
        }

        val result = IncomingShareParser.parse(intent)

        assertNotNull(result)
        assertEquals(Intent.ACTION_SEND_MULTIPLE, result!!.action)
        assertEquals("image/*", result.mimeType)
        assertNull(result.text)
        assertEquals(2, result.streamUris.size)
        assertEquals(uri1, result.streamUris[0])
        assertEquals(uri2, result.streamUris[1])
    }

    @Test
    fun parse_directShare_returnsShortcutId() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Direct share text")
            putExtra(Intent.EXTRA_SHORTCUT_ID, "sample_1")
        }

        val result = IncomingShareParser.parse(intent)

        assertNotNull(result)
        assertEquals("sample_1", result!!.shortcutId)
        assertEquals("Direct share text", result.text)
    }

    @Test
    fun parse_unsupportedAction_returnsNull() {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            type = "text/plain"
        }

        val result = IncomingShareParser.parse(intent)

        assertNull(result)
    }

    @Test
    fun parse_nullIntent_returnsNull() {
        val result = IncomingShareParser.parse(null)
        assertNull(result)
    }
}
