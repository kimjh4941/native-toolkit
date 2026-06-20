package android.unity.share

import android.content.ContextWrapper
import android.content.Intent
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UnityAndroidShareManagerTest {

    @After
    fun tearDown() {
        UnityAndroidShareManager.clearShareOperationListener()
    }

    // --- shareText ---

    @Test
    fun shareText_emptyText_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        // empty text triggers parser-level validation: "text is required"
        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":""}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_SHARE_TEXT, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("text is required"))
    }

    @Test
    fun shareText_invalidJson_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = "{invalid json}"
        )

        assertEquals(UnityAndroidShareManager.OPERATION_SHARE_TEXT, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
    }

    @Test
    fun shareText_missingTextField_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"title":"Only title"}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_SHARE_TEXT, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
    }

    // --- shareFile ---

    @Test
    fun shareFile_nonExistentPath_notifiesFileNotFoundFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        UnityAndroidShareManager.shareFile(
            context = FakeContext(),
            shareJson = """{"filePath":"/nonexistent/file_share_test_99999.txt"}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_SHARE_FILE, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("File not found"))
    }

    // --- shareFiles ---

    @Test
    fun shareFiles_emptyFilePaths_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        // empty array triggers parser-level validation
        UnityAndroidShareManager.shareFiles(
            context = FakeContext(),
            shareJson = """{"filePaths":[]}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_SHARE_FILES, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("filePaths must not be empty"))
    }

    // --- removeDirectShareTargets ---

    @Test
    fun removeDirectShareTargets_emptyIds_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        // empty array triggers parser-level validation
        UnityAndroidShareManager.removeDirectShareTargets(
            context = FakeContext(),
            shareJson = """{"ids":[]}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_REMOVE_DIRECT_SHARE_TARGETS, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
        assertTrue(listener.errorMessage.orEmpty().contains("ids must not be empty"))
    }

    // --- registerDirectShareTarget ---

    @Test
    fun registerDirectShareTarget_missingIconBase64_notifiesFailure() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        // missing iconBase64 field triggers JSONException from parser
        UnityAndroidShareManager.registerDirectShareTarget(
            context = FakeContext(),
            shareJson = """{"id":"t1","label":"Alice"}"""
        )

        assertEquals(UnityAndroidShareManager.OPERATION_REGISTER_DIRECT_SHARE_TARGET, listener.operation)
        assertFalse(listener.isSuccessful ?: true)
    }

    // --- callback lifecycle ---

    @Test
    fun shareWithCallback_launchFailure_clearsPendingContext() {
        val listener = CapturingListener()
        UnityAndroidShareManager.setShareOperationListener(listener)

        UnityAndroidShareManager.shareWithCallback(
            context = FakeContext(),
            shareJson = """{"text":"Hello"}"""
        )

        assertNull(pendingCallbackContext())
        assertFalse(listener.isSuccessful ?: true)
    }

    @Test
    fun cancelPendingShareCallback_clearsPendingContext() {
        val context = FakeContext()
        setPendingCallbackContext(context)

        UnityAndroidShareManager.cancelPendingShareCallback(context)

        assertNull(pendingCallbackContext())
    }

    // --- listener not set ---

    @Test
    fun shareText_emptyText_withoutListener_doesNotThrow() {
        UnityAndroidShareManager.clearShareOperationListener()

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":""}"""
        )
    }

    // --- Helpers ---

    private class CapturingListener : UnityAndroidShareManager.ShareOperationListener {
        var operation: String? = null
        var isSuccessful: Boolean? = null
        var errorMessage: String? = null
        var resultPackageName: String? = null

        override fun onShareOperation(operation: String, isSuccessful: Boolean, errorMessage: String?) {
            this.operation = operation
            this.isSuccessful = isSuccessful
            this.errorMessage = errorMessage
        }

        override fun onShareResult(operation: String, selectedPackageName: String?) {
            this.operation = operation
            this.resultPackageName = selectedPackageName
        }
    }

    private open class FakeContext : ContextWrapper(null) {
        override fun getPackageName(): String = "com.example.share.test"
        override fun getApplicationContext(): android.content.Context = this
        override fun startActivity(intent: Intent) { /* no-op for local JVM tests */ }
    }

    private fun pendingCallbackContext(): android.content.Context? {
        val field = UnityAndroidShareManager::class.java.getDeclaredField("pendingCallbackContext")
        field.isAccessible = true
        return field.get(UnityAndroidShareManager) as android.content.Context?
    }

    private fun setPendingCallbackContext(context: android.content.Context) {
        val field = UnityAndroidShareManager::class.java.getDeclaredField("pendingCallbackContext")
        field.isAccessible = true
        field.set(UnityAndroidShareManager, context)
    }
}
