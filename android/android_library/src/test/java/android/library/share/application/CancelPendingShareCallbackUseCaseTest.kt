package android.library.share.application

import android.library.share.application.usecase.CancelPendingShareCallbackUseCase
import android.library.share.application.port.RichPreviewShareRepository
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.SharePreviewOptions
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

        override fun shareText(content: ShareContent, chooserActionsJson: String) {}
        override fun shareText(content: ShareContent, chooserActionsJson: String, preview: SharePreviewOptions) {}
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
