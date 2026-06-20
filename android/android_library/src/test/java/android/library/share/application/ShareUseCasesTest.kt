package android.library.share.application

import android.library.share.application.usecase.CancelPendingShareCallbackUseCase
import android.library.share.application.usecase.RegisterDirectShareTargetUseCase
import android.library.share.application.usecase.RemoveDirectShareTargetsUseCase
import android.library.share.application.usecase.ShareFileUseCase
import android.library.share.application.usecase.ShareImageUseCase
import android.library.share.application.usecase.ShareMultipleFilesUseCase
import android.library.share.application.usecase.ShareMultipleImagesUseCase
import android.library.share.application.usecase.ShareTextUseCase
import android.library.share.application.usecase.ShareWithCallbackUseCase
import android.library.share.application.port.RichPreviewShareRepository
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.SharePreviewOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ShareUseCasesTest {

    // --- ShareTextUseCase ---

    @Test
    fun shareText_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val content = ShareContent(text = "Hello")
        ShareTextUseCase(repo)(content)
        assertEquals(content, repo.lastSharedTextContent)
    }

    @Test
    fun shareText_emptyText_throwsEmptyContent() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareTextUseCase(repo)(ShareContent(text = ""))
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.EmptyContent)
    }

    @Test
    fun shareText_blankMimeType_throwsInvalidMimeType() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareTextUseCase(repo)(ShareContent(text = "Hi", mimeType = ""))
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.InvalidMimeType)
    }

    @Test
    fun shareText_withPreviewThumbnailPath_passedToRepository() {
        val repo = FakeShareRepository()
        val content = ShareContent(text = "Hello")
        val preview = SharePreviewOptions(title = "My Title", thumbnailPath = "/path/thumb.jpg")
        ShareTextUseCase(repo)(content, "[]", preview)
        assertEquals(content, repo.lastSharedTextContent)
        assertEquals(preview, repo.lastSharedTextPreview)
    }

    // --- ShareImageUseCase ---

    @Test
    fun shareImage_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        ShareImageUseCase(repo)("/path/img.jpg", "image/jpeg")
        assertEquals("/path/img.jpg", repo.lastSharedImagePath)
        assertEquals("image/jpeg", repo.lastSharedImageMimeType)
    }

    @Test
    fun shareImage_blankMimeType_throwsInvalidMimeType() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareImageUseCase(repo)("/path/img.jpg", "")
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.InvalidMimeType)
    }

    // --- ShareMultipleImagesUseCase ---

    @Test
    fun shareImages_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val paths = listOf("/a.jpg", "/b.jpg")
        ShareMultipleImagesUseCase(repo)(paths)
        assertEquals(paths, repo.lastSharedImagePaths)
    }

    @Test
    fun shareImages_emptyList_throwsEmptyFileList() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareMultipleImagesUseCase(repo)(emptyList())
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.EmptyFileList)
    }

    // --- ShareFileUseCase ---

    @Test
    fun shareFile_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val tempFile = File.createTempFile("share_test", ".txt")
        try {
            ShareFileUseCase(repo)(tempFile.absolutePath)
            assertEquals(tempFile.absolutePath, repo.lastSharedFilePath)
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun shareFile_nonExistentPath_throwsFileNotFound() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareFileUseCase(repo)("/nonexistent/file_that_does_not_exist_12345.txt")
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.FileNotFound)
    }

    // --- ShareMultipleFilesUseCase ---

    @Test
    fun shareFiles_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val paths = listOf("/a.pdf", "/b.pdf")
        ShareMultipleFilesUseCase(repo)(paths)
        assertEquals(paths, repo.lastSharedFilePaths)
    }

    @Test
    fun shareFiles_emptyList_throwsEmptyFileList() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareMultipleFilesUseCase(repo)(emptyList())
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.EmptyFileList)
    }

    // --- RegisterDirectShareTargetUseCase ---

    @Test
    fun registerDirectShareTarget_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val target = DirectShareTarget(id = "t1", label = "Alice")
        val icon = byteArrayOf(1, 2, 3)
        RegisterDirectShareTargetUseCase(repo)(target, icon)
        assertEquals(target, repo.lastRegisteredTarget)
    }

    // --- RemoveDirectShareTargetsUseCase ---

    @Test
    fun removeDirectShareTargets_normalPath_delegatesToRepository() {
        val repo = FakeShareRepository()
        val ids = listOf("t1", "t2")
        RemoveDirectShareTargetsUseCase(repo)(ids)
        assertEquals(ids, repo.lastRemovedIds)
    }

    @Test
    fun removeDirectShareTargets_emptyList_throwsEmptyIdList() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            RemoveDirectShareTargetsUseCase(repo)(emptyList())
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.EmptyIdList)
    }

    // --- ShareWithCallbackUseCase ---

    @Test
    fun shareWithCallback_normalPath_callsOnResult() {
        val repo = FakeShareRepository(callbackPackage = "com.example.app")
        val content = ShareContent(text = "Hello")
        var received: String? = "initial"
        ShareWithCallbackUseCase(repo)(content) { received = it }
        assertEquals("com.example.app", received)
    }

    @Test
    fun shareWithCallback_selectedPackageUnavailable_callsOnResultWithNull() {
        val repo = FakeShareRepository(callbackPackage = null)
        val content = ShareContent(text = "Hello")
        var received: String? = "initial"
        ShareWithCallbackUseCase(repo)(content) { received = it }
        assertNull(received)
    }

    @Test
    fun shareWithCallback_emptyText_throwsEmptyContent() {
        val repo = FakeShareRepository()
        val exception = runCatching {
            ShareWithCallbackUseCase(repo)(ShareContent(text = "")) { }
        }.exceptionOrNull()
        assertTrue(exception is ShareDomainError.EmptyContent)
    }

    @Test
    fun shareWithCallback_withPreviewThumbnailPath_passedToRepository() {
        val repo = FakeShareRepository(callbackPackage = "com.example.app")
        val content = ShareContent(text = "Hello")
        val preview = SharePreviewOptions(thumbnailPath = "/path/thumb.jpg")
        ShareWithCallbackUseCase(repo)(content, preview, {})
        assertEquals(preview, repo.lastCallbackPreview)
    }

    // --- CancelPendingShareCallbackUseCase ---

    @Test
    fun cancelPendingCallback_delegatesToRepository() {
        val repo = FakeShareRepository()
        CancelPendingShareCallbackUseCase(repo)()
        assertTrue(repo.cancelPendingCallbackCalled)
    }

    // --- Fake Repository ---

    private class FakeShareRepository(
        private val callbackPackage: String? = "com.example.app"
    ) : RichPreviewShareRepository {
        var lastSharedTextContent: ShareContent? = null
        var lastSharedTextPreview: SharePreviewOptions? = null
        var lastSharedImagePath: String? = null
        var lastSharedImageMimeType: String? = null
        var lastSharedImagePaths: List<String>? = null
        var lastSharedFilePath: String? = null
        var lastSharedFilePaths: List<String>? = null
        var lastRegisteredTarget: DirectShareTarget? = null
        var lastRemovedIds: List<String>? = null
        var lastCallbackPreview: SharePreviewOptions? = null
        var cancelPendingCallbackCalled = false

        override fun shareText(content: ShareContent, chooserActionsJson: String) {
            lastSharedTextContent = content
        }
        override fun shareText(content: ShareContent, chooserActionsJson: String, preview: SharePreviewOptions) {
            lastSharedTextContent = content
            lastSharedTextPreview = preview
        }
        override fun shareImage(filePath: String, mimeType: String) {
            lastSharedImagePath = filePath
            lastSharedImageMimeType = mimeType
        }
        override fun shareImages(filePaths: List<String>) { lastSharedImagePaths = filePaths }
        override fun shareFile(filePath: String) { lastSharedFilePath = filePath }
        override fun shareFiles(filePaths: List<String>) { lastSharedFilePaths = filePaths }
        override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {
            lastRegisteredTarget = target
        }
        override fun removeDirectShareTargets(ids: List<String>) { lastRemovedIds = ids }
        override fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit) {
            onResult(callbackPackage)
        }
        override fun shareWithCallback(
            content: ShareContent,
            preview: SharePreviewOptions,
            onResult: (String?) -> Unit,
            onFinished: () -> Unit
        ) {
            lastCallbackPreview = preview
            onResult(callbackPackage)
            onFinished()
        }
        override fun cancelPendingCallback() { cancelPendingCallbackCalled = true }
    }
}
