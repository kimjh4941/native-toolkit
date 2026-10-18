package com.jonghyunkim.nativetoolkit.share.application

import com.jonghyunkim.nativetoolkit.share.application.port.ShareRepository
import com.jonghyunkim.nativetoolkit.share.application.usecase.CancelShareSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareForSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareTextWithActionsUseCase
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

// The share operations added in 1b (Kotlin API design 8.9): ShareForSelectionUseCase,
// CancelShareSelectionUseCase and ShareTextWithActionsUseCase.
class ShareSelectionUseCasesTest {

    private open class OldRepository : ShareRepository {
        override fun shareText(content: ShareContent) = Unit
        override fun shareImage(filePath: String, mimeType: String) = Unit
        override fun shareImages(filePaths: List<String>) = Unit
        override fun shareFile(filePath: String) = Unit
        override fun shareFiles(filePaths: List<String>) = Unit
        override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) = Unit
        override fun removeDirectShareTargets(ids: List<String>) = Unit
        override fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit) = Unit
    }

    private class FakeRepository : OldRepository() {
        var selectionPreview: SharePreviewOptions? = null
        var canceledToken: Long? = null
        var sharedActions: List<ShareChooserAction>? = null

        override fun shareForSelection(content: ShareContent, preview: SharePreviewOptions): Long {
            selectionPreview = preview
            return 42L
        }
        override fun cancelShareSelection(token: Long) {
            canceledToken = token
        }
        override fun shareTextWithActions(content: ShareContent, actions: List<ShareChooserAction>, preview: SharePreviewOptions) {
            sharedActions = actions
        }
    }

    private val repository = FakeRepository()
    private val icon = byteArrayOf(1, 2, 3)

    private inline fun <reified E : Throwable> assertThrows(block: () -> Unit): E {
        try {
            block()
        } catch (e: Throwable) {
            if (e is E) return e
            throw e
        }
        fail("expected ${E::class.java.simpleName}")
        throw AssertionError()
    }

    @Test
    fun shareForSelection_returnsTheRepositoryToken_withTheDefaultPreview() {
        assertEquals(42L, ShareForSelectionUseCase(repository)(ShareContent(text = "t")))
        assertEquals(SharePreviewOptions(), repository.selectionPreview)
    }

    @Test
    fun shareForSelection_blankText_throwsEmptyContent_withoutOpening() {
        assertThrows<ShareDomainError.EmptyContent> { ShareForSelectionUseCase(repository)(ShareContent(text = " ")) }
        assertNull(repository.selectionPreview)
    }

    @Test
    fun cancelShareSelection_delegates() {
        CancelShareSelectionUseCase(repository)(7L)
        assertEquals(7L, repository.canceledToken)
    }

    @Test
    fun shareTextWithActions_delegates_emptyActionsAllowed() {
        val actions = listOf(ShareChooserAction("a", "A", icon), ShareChooserAction("b", "B", icon))
        ShareTextWithActionsUseCase(repository)(ShareContent(text = "t"), actions)
        assertEquals(actions, repository.sharedActions)
        ShareTextWithActionsUseCase(repository)(ShareContent(text = "t"), emptyList())
        assertEquals(emptyList<ShareChooserAction>(), repository.sharedActions)
    }

    @Test
    fun shareTextWithActions_emptyOrDuplicateId_throwsInvalidChooserAction_withoutOpening() {
        val empty = assertThrows<ShareDomainError.InvalidChooserAction> {
            ShareTextWithActionsUseCase(repository)(ShareContent(text = "t"), listOf(ShareChooserAction("", "A", icon)))
        }
        assertEquals("", empty.id)
        val duplicate = assertThrows<ShareDomainError.InvalidChooserAction> {
            ShareTextWithActionsUseCase(repository)(
                ShareContent(text = "t"),
                listOf(ShareChooserAction("a", "A", icon), ShareChooserAction("a", "B", icon))
            )
        }
        assertEquals("a", duplicate.id)
        assertNull(repository.sharedActions)
    }

    @Test
    fun shareTextWithActions_blankTextOrMimeType_throws() {
        assertThrows<ShareDomainError.EmptyContent> { ShareTextWithActionsUseCase(repository)(ShareContent(text = ""), emptyList()) }
        assertThrows<ShareDomainError.InvalidMimeType> {
            ShareTextWithActionsUseCase(repository)(ShareContent(text = "t", mimeType = " "), emptyList())
        }
    }

    @Test
    fun aRepositoryWrittenBefore1b_compiles_andTheNewFunctionsThrowUnsupported() {
        val old = OldRepository()
        assertThrows<UnsupportedOperationException> { ShareForSelectionUseCase(old)(ShareContent(text = "t")) }
        assertThrows<UnsupportedOperationException> { CancelShareSelectionUseCase(old)(1L) }
        assertThrows<UnsupportedOperationException> { ShareTextWithActionsUseCase(old)(ShareContent(text = "t"), emptyList()) }
    }

    @Test
    fun chooserAction_equalsByValue_andHidesTheIconBytesInToString() {
        assertEquals(ShareChooserAction("a", "A", byteArrayOf(1)), ShareChooserAction("a", "A", byteArrayOf(1)))
        assertEquals(ShareChooserAction("a", "A", byteArrayOf(1)).hashCode(), ShareChooserAction("a", "A", byteArrayOf(1)).hashCode())
        assertNotEquals(ShareChooserAction("a", "A", byteArrayOf(1)), ShareChooserAction("a", "A", byteArrayOf(2)))
        assertTrue(ShareChooserAction("a", "A", byteArrayOf(1, 2)).toString().contains("2 bytes"))
    }
}
