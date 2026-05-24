package android.unity.share

import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UnityShareJsonParserTest {

    // --- parseShareText ---

    @Test
    fun parseShareText_allFields_parsedCorrectly() {
        val json = """{"text":"Hello","title":"Share","subject":"Subject","mimeType":"text/html"}"""
        val spec = UnityShareJsonParser.parseShareText(json)
        assertEquals("Hello", spec.text)
        assertEquals("Share", spec.title)
        assertEquals("Subject", spec.subject)
        assertEquals("text/html", spec.mimeType)
    }

    @Test
    fun parseShareText_titleNull_returnsNullTitle() {
        val json = """{"text":"Hello"}"""
        val spec = UnityShareJsonParser.parseShareText(json)
        assertNull(spec.title)
    }

    @Test
    fun parseShareText_mimeTypeOmitted_defaultsToTextPlain() {
        val json = """{"text":"Hello"}"""
        val spec = UnityShareJsonParser.parseShareText(json)
        assertEquals("text/plain", spec.mimeType)
    }

    @Test
    fun parseShareText_emptyText_throwsIllegalArgumentException() {
        val json = """{"text":""}"""
        val exception = runCatching { UnityShareJsonParser.parseShareText(json) }.exceptionOrNull()
        assertTrue(exception is IllegalArgumentException)
        assertTrue(exception!!.message!!.contains("text is required"))
    }

    @Test
    fun parseShareText_chooserActionsArray_parsedCorrectly() {
        val json = """{"text":"Hi","chooserActions":[{"label":"Copy","iconBase64":"abc","intentAction":"android.intent.action.COPY"}]}"""
        val spec = UnityShareJsonParser.parseShareText(json)
        assertEquals(1, spec.chooserActions.size)
        assertEquals("Copy", spec.chooserActions[0].label)
        assertEquals("abc", spec.chooserActions[0].iconBase64)
        assertEquals("android.intent.action.COPY", spec.chooserActions[0].intentAction)
    }

    @Test
    fun parseShareText_invalidJson_throwsJSONException() {
        val exception = runCatching { UnityShareJsonParser.parseShareText("{invalid}") }.exceptionOrNull()
        assertTrue(exception is JSONException)
    }

    // --- parseShareImage ---

    @Test
    fun parseShareImage_allFields_parsedCorrectly() {
        val json = """{"filePath":"/sdcard/img.jpg","mimeType":"image/jpeg"}"""
        val spec = UnityShareJsonParser.parseShareImage(json)
        assertEquals("/sdcard/img.jpg", spec.filePath)
        assertEquals("image/jpeg", spec.mimeType)
    }

    @Test
    fun parseShareImage_mimeTypeOmitted_defaultsToImageWildcard() {
        val json = """{"filePath":"/sdcard/img.jpg"}"""
        val spec = UnityShareJsonParser.parseShareImage(json)
        assertEquals("image/*", spec.mimeType)
    }

    @Test
    fun parseShareImage_emptyFilePath_throwsIllegalArgumentException() {
        val json = """{"filePath":""}"""
        val exception = runCatching { UnityShareJsonParser.parseShareImage(json) }.exceptionOrNull()
        assertTrue(exception is IllegalArgumentException)
    }

    // --- parseShareImages ---

    @Test
    fun parseShareImages_filePathsArray_parsedCorrectly() {
        val json = """{"filePaths":["/a.jpg","/b.jpg"]}"""
        val spec = UnityShareJsonParser.parseShareImages(json)
        assertEquals(listOf("/a.jpg", "/b.jpg"), spec.filePaths)
    }

    @Test
    fun parseShareImages_emptyArray_throwsIllegalArgumentException() {
        val json = """{"filePaths":[]}"""
        val exception = runCatching { UnityShareJsonParser.parseShareImages(json) }.exceptionOrNull()
        assertTrue(exception is IllegalArgumentException)
    }

    // --- parseShareFile ---

    @Test
    fun parseShareFile_filePath_parsedCorrectly() {
        val json = """{"filePath":"/sdcard/file.pdf"}"""
        val spec = UnityShareJsonParser.parseShareFile(json)
        assertEquals("/sdcard/file.pdf", spec.filePath)
    }

    @Test
    fun parseShareFile_emptyFilePath_throwsIllegalArgumentException() {
        val json = """{"filePath":""}"""
        val exception = runCatching { UnityShareJsonParser.parseShareFile(json) }.exceptionOrNull()
        assertTrue(exception is IllegalArgumentException)
    }

    // --- parseShareFiles ---

    @Test
    fun parseShareFiles_filePathsArray_parsedCorrectly() {
        val json = """{"filePaths":["/a.pdf","/b.pdf"]}"""
        val spec = UnityShareJsonParser.parseShareFiles(json)
        assertEquals(listOf("/a.pdf", "/b.pdf"), spec.filePaths)
    }

    // --- parseRegisterDirectShareTarget ---

    @Test
    fun parseRegisterDirectShareTarget_allFields_parsedCorrectly() {
        val json = """{"id":"t1","label":"Alice","iconBase64":"abc=","category":"android.shortcut.conversation"}"""
        val spec = UnityShareJsonParser.parseRegisterDirectShareTarget(json)
        assertEquals("t1", spec.id)
        assertEquals("Alice", spec.label)
        assertEquals("abc=", spec.iconBase64)
        assertEquals("android.shortcut.conversation", spec.category)
    }

    @Test
    fun parseRegisterDirectShareTarget_categoryOmitted_usesDefault() {
        val json = """{"id":"t1","label":"Alice","iconBase64":"abc="}"""
        val spec = UnityShareJsonParser.parseRegisterDirectShareTarget(json)
        assertEquals("android.shortcut.conversation", spec.category)
    }

    @Test
    fun parseRegisterDirectShareTarget_idMissing_throwsIllegalArgumentException() {
        val json = """{"label":"Alice","iconBase64":"abc="}"""
        val exception = runCatching {
            UnityShareJsonParser.parseRegisterDirectShareTarget(json)
        }.exceptionOrNull()
        assertTrue(exception is Exception)
    }

    // --- parseRemoveDirectShareTargets ---

    @Test
    fun parseRemoveDirectShareTargets_idsArray_parsedCorrectly() {
        val json = """{"ids":["t1","t2"]}"""
        val spec = UnityShareJsonParser.parseRemoveDirectShareTargets(json)
        assertEquals(listOf("t1", "t2"), spec.ids)
    }

    @Test
    fun parseRemoveDirectShareTargets_emptyArray_throwsIllegalArgumentException() {
        val json = """{"ids":[]}"""
        val exception = runCatching {
            UnityShareJsonParser.parseRemoveDirectShareTargets(json)
        }.exceptionOrNull()
        assertTrue(exception is IllegalArgumentException)
    }
}
