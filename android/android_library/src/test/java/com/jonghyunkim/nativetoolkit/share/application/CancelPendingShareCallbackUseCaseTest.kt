package com.jonghyunkim.nativetoolkit.share.application

import com.jonghyunkim.nativetoolkit.share.application.usecase.CancelPendingShareCallbackUseCase
import com.jonghyunkim.nativetoolkit.share.application.port.RichPreviewShareRepository
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import org.junit.Assert.assertTrue
import org.junit.Test

class CancelPendingShareCallbackUseCaseTest {

    @Test
    fun invoke_callsCancelPendingCallbackOnRepository() {
        val repo = FakeCancelRepository()
        CancelPendingShareCallbackUseCase(repo)()
        assertTrue(repo.cancelCalled)
    }

    private class FakeCancelRepository : RichPreviewShareRepository {
        var cancelCalled = false

        override fun shareText(content: ShareContent) {}
        override fun shareText(content: ShareContent, preview: SharePreviewOptions) {}
        override fun shareImage(filePath: String, mimeType: String) {}
        override fun shareImages(filePaths: List<String>) {}
        override fun shareFile(filePath: String) {}
        override fun shareFiles(filePaths: List<String>) {}
        override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {}
        override fun removeDirectShareTargets(ids: List<String>) {}
        override fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit) {}
        override fun shareWithCallback(
            content: ShareContent,
            preview: SharePreviewOptions,
            onResult: (String?) -> Unit,
            onFinished: () -> Unit
        ) {}
        override fun cancelPendingCallback() { cancelCalled = true }
    }
}
