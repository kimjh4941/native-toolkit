package com.jonghyunkim.nativetoolkit.capi.jni

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** The Kotlin to C direction of the strings (C ABI design part 1, 5.10, AC-19). */
class Utf8Test {

    @Test
    fun anUnpairedSurrogateBecomesTheReplacementCharacter() {
        assertEquals("a�b", Utf8.replaceForC("a\uD800b"))
        assertEquals("a�b", Utf8.replaceForC("a\uDC00b"))
        assertEquals("�", Utf8.replaceForC("\uD800"))
        // A low surrogate before a high one is two unpaired ones.
        assertEquals("��", Utf8.replaceForC("\uDC00\uD800"))
    }

    @Test
    fun aPairIsKept() {
        val emoji = "😀"
        assertEquals(emoji, Utf8.replaceForC(emoji))
        assertArrayEquals(byteArrayOf(0xF0.toByte(), 0x9F.toByte(), 0x98.toByte(), 0x80.toByte()), Utf8.encode(emoji))
    }

    @Test
    fun theNullCharacterBecomesTheReplacementCharacter() {
        assertEquals("a�b", Utf8.replaceForC("a\u0000b"))
        assertArrayEquals(byteArrayOf('a'.code.toByte(), 0xEF.toByte(), 0xBF.toByte(), 0xBD.toByte()), Utf8.encode("a\u0000"))
    }

    @Test
    fun plainTextIsUnchangedAndRoundTrips() {
        val text = "plain éあ"
        assertEquals(text, Utf8.replaceForC(text))
        assertEquals(text, Utf8.decode(Utf8.encode(text)))
        assertEquals(null, Utf8.encodeOrNull(null))
        assertEquals(null, Utf8.decodeOrNull(null))
    }
}
