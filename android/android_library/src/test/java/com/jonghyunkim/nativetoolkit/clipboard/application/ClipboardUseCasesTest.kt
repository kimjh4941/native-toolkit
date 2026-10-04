package com.jonghyunkim.nativetoolkit.clipboard.application

import com.jonghyunkim.nativetoolkit.clipboard.application.port.ClipboardRepository
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.ClearClipboardUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyHtmlTextUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyMultipleTextUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyPlainTextUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.CopyUriUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.GetClipDescriptionUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.HasClipUseCase
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.ReadClipboardUseCase
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardDomainError
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipDescriptionInfo
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipItemData
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipReadResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipboardUseCasesTest {

    // --- CopyPlainTextUseCase ---

    @Test
    fun copyPlainText_normalPath_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.PlainText(text = "hello")
        CopyPlainTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
        assertEquals(1, repo.copyCallCount)
    }

    @Test
    fun copyPlainText_blankText_isAllowed() {
        val repo = MockClipboardRepository()
        val content = ClipContent.PlainText(text = "")
        CopyPlainTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    // --- CopyHtmlTextUseCase ---

    @Test
    fun copyHtmlText_normalPath_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.HtmlText(plainText = "hi", htmlText = "<b>hi</b>")
        CopyHtmlTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    @Test
    fun copyHtmlText_emptyHtml_throwsEmptyContent() {
        val repo = MockClipboardRepository()
        val exception = runCatching {
            CopyHtmlTextUseCase(repo)(ClipContent.HtmlText(plainText = "hi", htmlText = ""))
        }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.EmptyContent)
        assertEquals(0, repo.copyCallCount)
    }

    @Test
    fun copyHtmlText_emptyPlainWithNonEmptyHtml_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.HtmlText(plainText = "", htmlText = "<b>hi</b>")
        CopyHtmlTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    // --- CopyUriUseCase ---

    @Test
    fun copyUri_normalPath_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.UriContent(uri = "content://media/external/images/1")
        CopyUriUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    @Test
    fun copyUri_blankUri_throwsInvalidUri() {
        val repo = MockClipboardRepository()
        val exception = runCatching {
            CopyUriUseCase(repo)(ClipContent.UriContent(uri = ""))
        }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.InvalidUri)
        assertEquals(0, repo.copyCallCount)
    }

    @Test
    fun copyUri_fileScheme_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.UriContent(uri = "file:///storage/emulated/0/test.jpg")
        CopyUriUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    @Test
    fun copyUri_unsupportedScheme_throwsInvalidUri() {
        val repo = MockClipboardRepository()
        val exception = runCatching {
            CopyUriUseCase(repo)(ClipContent.UriContent(uri = "http://example.com/x"))
        }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.InvalidUri)
        assertEquals(0, repo.copyCallCount)
    }

    @Test
    fun copyUri_noScheme_throwsInvalidUri() {
        val repo = MockClipboardRepository()
        val exception = runCatching {
            CopyUriUseCase(repo)(ClipContent.UriContent(uri = "not-a-uri"))
        }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.InvalidUri)
        assertEquals(0, repo.copyCallCount)
    }

    // --- CopyMultipleTextUseCase ---

    @Test
    fun copyMultipleText_normalPath_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.MultipleText(texts = listOf("a", "b"))
        CopyMultipleTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    @Test
    fun copyMultipleText_emptyList_throwsEmptyItemList() {
        val repo = MockClipboardRepository()
        val exception = runCatching {
            CopyMultipleTextUseCase(repo)(ClipContent.MultipleText(texts = emptyList()))
        }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.EmptyItemList)
        assertEquals(0, repo.copyCallCount)
    }

    @Test
    fun copyMultipleText_singleItem_delegatesToRepository() {
        val repo = MockClipboardRepository()
        val content = ClipContent.MultipleText(texts = listOf("only"))
        CopyMultipleTextUseCase(repo)(content)
        assertEquals(content, repo.lastCopiedContent)
    }

    // --- ReadClipboardUseCase ---

    @Test
    fun read_normalPath_returnsClipReadResult() {
        val result = ClipReadResult(label = "l", mimeTypes = listOf("text/plain"), items = listOf(ClipItemData(text = "hi")))
        val repo = MockClipboardRepository(stubbedReadResult = result)
        assertEquals(result, ReadClipboardUseCase(repo)())
    }

    @Test
    fun read_emptyClipboard_returnsNull() {
        val repo = MockClipboardRepository(stubbedReadResult = null)
        assertNull(ReadClipboardUseCase(repo)())
    }

    @Test
    fun read_securityException_propagatesReadNotAllowed() {
        val repo = MockClipboardRepository(readThrows = ClipboardDomainError.ReadNotAllowed)
        val exception = runCatching { ReadClipboardUseCase(repo)() }.exceptionOrNull()
        assertTrue(exception is ClipboardDomainError.ReadNotAllowed)
    }

    @Test
    fun read_multipleItems_returnsAllItems() {
        val result = ClipReadResult(
            label = null,
            mimeTypes = listOf("text/plain"),
            items = listOf(ClipItemData(text = "a"), ClipItemData(text = "b"))
        )
        val repo = MockClipboardRepository(stubbedReadResult = result)
        assertEquals(2, ReadClipboardUseCase(repo)()?.items?.size)
    }

    // --- HasClipUseCase ---

    @Test
    fun hasClip_true_returnsTrue() {
        val repo = MockClipboardRepository(stubbedHasClip = true)
        assertTrue(HasClipUseCase(repo)())
    }

    @Test
    fun hasClip_false_returnsFalse() {
        val repo = MockClipboardRepository(stubbedHasClip = false)
        assertFalse(HasClipUseCase(repo)())
    }

    // --- GetClipDescriptionUseCase ---

    @Test
    fun getDescription_normalPath_returnsMetadata() {
        val info = ClipDescriptionInfo(label = "l", mimeTypes = listOf("text/plain"), isStyledText = false, classificationStatus = null)
        val repo = MockClipboardRepository(stubbedDescription = info)
        assertEquals(info, GetClipDescriptionUseCase(repo)())
    }

    @Test
    fun getDescription_emptyClipboard_returnsNull() {
        val repo = MockClipboardRepository(stubbedDescription = null)
        assertNull(GetClipDescriptionUseCase(repo)())
    }

    @Test
    fun getDescription_styledTextTrue_returnsTrue() {
        val info = ClipDescriptionInfo(label = null, mimeTypes = emptyList(), isStyledText = true, classificationStatus = 1)
        val repo = MockClipboardRepository(stubbedDescription = info)
        assertTrue(GetClipDescriptionUseCase(repo)()?.isStyledText == true)
    }

    @Test
    fun getDescription_styledTextFalse_returnsFalse() {
        val info = ClipDescriptionInfo(label = null, mimeTypes = emptyList(), isStyledText = false, classificationStatus = null)
        val repo = MockClipboardRepository(stubbedDescription = info)
        assertFalse(GetClipDescriptionUseCase(repo)()?.isStyledText == true)
    }

    // --- ClearClipboardUseCase ---

    @Test
    fun clear_delegatesToRepository() {
        val repo = MockClipboardRepository()
        ClearClipboardUseCase(repo)()
        assertTrue(repo.clearCalled)
    }

    // --- Mock Repository ---

    private class MockClipboardRepository(
        private val stubbedReadResult: ClipReadResult? = null,
        private val stubbedHasClip: Boolean = false,
        private val stubbedDescription: ClipDescriptionInfo? = null,
        private val readThrows: ClipboardDomainError? = null
    ) : ClipboardRepository {
        var lastCopiedContent: ClipContent? = null
        var copyCallCount = 0
        var clearCalled = false

        override fun copy(content: ClipContent) {
            lastCopiedContent = content
            copyCallCount++
        }

        override fun read(): ClipReadResult? {
            readThrows?.let { throw it }
            return stubbedReadResult
        }

        override fun hasClip(): Boolean = stubbedHasClip

        override fun getDescription(): ClipDescriptionInfo? = stubbedDescription

        override fun clear() {
            clearCalled = true
        }
    }
}
