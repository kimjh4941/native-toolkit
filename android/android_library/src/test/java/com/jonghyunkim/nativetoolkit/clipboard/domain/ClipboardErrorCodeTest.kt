package com.jonghyunkim.nativetoolkit.clipboard.domain

import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardDomainError
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardErrorCode
import org.junit.Assert.assertEquals
import org.junit.Test

// UT-04 of the Kotlin API design: the seven clipboard error codes (8.10), the same table as the
// Unity bridge's errorInfoOf.
class ClipboardErrorCodeTest {

    @Test
    fun domainErrors_mapToTheirCodes() {
        assertEquals(ClipboardErrorCode.EMPTY_CONTENT, ClipboardErrorCode.of(ClipboardDomainError.EmptyContent))
        assertEquals(ClipboardErrorCode.EMPTY_ITEMS, ClipboardErrorCode.of(ClipboardDomainError.EmptyItemList))
        assertEquals(ClipboardErrorCode.INVALID_URI, ClipboardErrorCode.of(ClipboardDomainError.InvalidUri("::")))
        assertEquals(ClipboardErrorCode.UNAVAILABLE, ClipboardErrorCode.of(ClipboardDomainError.ClipboardUnavailable))
        assertEquals(ClipboardErrorCode.READ_NOT_ALLOWED, ClipboardErrorCode.of(ClipboardDomainError.ReadNotAllowed))
    }

    @Test
    fun securityException_isSecurity_includingSubclasses() {
        assertEquals(ClipboardErrorCode.SECURITY, ClipboardErrorCode.of(SecurityException("denied")))
        assertEquals(ClipboardErrorCode.SECURITY, ClipboardErrorCode.of(object : SecurityException() {}))
    }

    @Test
    fun anythingElse_isUnknown() {
        assertEquals(ClipboardErrorCode.UNKNOWN, ClipboardErrorCode.of(IllegalStateException()))
        assertEquals(ClipboardErrorCode.UNKNOWN, ClipboardErrorCode.of(RuntimeException(SecurityException())))
        assertEquals(ClipboardErrorCode.UNKNOWN, ClipboardErrorCode.of(OutOfMemoryError()))
    }

    @Test
    fun thereAreExactlySevenCodes() {
        assertEquals(
            listOf("EMPTY_CONTENT", "EMPTY_ITEMS", "INVALID_URI", "UNAVAILABLE", "READ_NOT_ALLOWED", "SECURITY", "UNKNOWN"),
            ClipboardErrorCode.entries.map { it.name }
        )
    }
}
