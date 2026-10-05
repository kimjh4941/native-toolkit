package com.jonghyunkim.nativetoolkit.common

import com.jonghyunkim.nativetoolkit.common.logging.LogRedaction
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.logSafeDescription
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// UT-07 of the Kotlin API design: secret values never appear in log text.
class LogRedactionTest {

    private val sentinel = "SENTINEL-secret-9f3c"

    @Test
    fun redact_hidesTheValueAndKeepsTheLength() {
        val redacted = LogRedaction.redact(sentinel)
        assertFalse(redacted.contains(sentinel))
        assertEquals("<redacted, length=${sentinel.length}>", redacted)
    }

    @Test
    fun redact_null_isNull() {
        assertEquals("null", LogRedaction.redact(null))
    }

    @Test
    fun shareContentLogSafeDescription_hidesTextAndSubject() {
        val content = ShareContent(text = sentinel, title = "title", subject = "$sentinel-subject")
        val description = content.logSafeDescription()
        assertFalse(description.contains(sentinel))
        assertTrue(description.contains("textLength: ${sentinel.length}"))
        assertTrue(description.contains("hasSubject: true"))
    }

    @Test
    fun shareContentToString_isUnchanged() {
        // The public data class keeps its generated toString (K-9); only the log sites change.
        val content = ShareContent(text = "hello")
        assertTrue(content.toString().contains("hello"))
    }

    @Test
    fun newTypesToString_hideTheValues() {
        val texts = listOf(
            DialogValue.Text(sentinel).toString(),
            DialogValue.Login("user-$sentinel", "pw-$sentinel").toString(),
            NotificationInteraction(NotificationInteraction.Kind.ACTION, 7, "t", "a", mapOf("key" to sentinel)).toString()
        )
        texts.forEach { assertFalse(it, it.contains(sentinel)) }
        assertTrue(texts[0].contains("length=${sentinel.length}"))
        assertTrue(texts[2].contains("key"))
    }
}
