package android.unity.share

import android.content.ActivityNotFoundException
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
        UnityAndroidShareManager.clearShareChooserActionListener()
        resetChooserActionRegistry()
        UnityAndroidShareManager.chooserActionRegistryFactory =
            { ctx -> AndroidShareChooserActionReceiverRegistry(ctx.applicationContext) }
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

    // --- chooser action listener ---

    @Test
    fun shareText_withChooserActions_registersWithNormalizedActionIds() {
        val registry = FakeRegistry()
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"},{"label":"B","iconBase64":"x","intentAction":"com.example.B"}]}"""
        )

        assertEquals(listOf("com.example.A", "com.example.B"), registry.lastRegisteredActionIds)
    }

    @Test
    fun shareText_withNoChooserActions_registersEmptyActionIds() {
        val registry = FakeRegistry()
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello"}"""
        )

        assertEquals(emptyList<String>(), registry.lastRegisteredActionIds)
    }

    @Test
    fun shareText_launchFailure_unregistersCurrentToken() {
        val registry = FakeRegistry(tokenToReturn = 42L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        // LaunchFailingFakeContext.startActivity throws ActivityNotFoundException → cleanup path triggered.
        UnityAndroidShareManager.shareText(
            context = LaunchFailingFakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"}]}"""
        )

        assertEquals(42L, registry.lastUnregisteredToken)
    }

    @Test
    fun dispatchChooserAction_forwardsToListener() {
        val registry = FakeRegistry(tokenToReturn = 1L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        var receivedActionId: String? = null
        UnityAndroidShareManager.setShareChooserActionListener(object : UnityAndroidShareManager.ShareChooserActionListener {
            override fun onChooserAction(actionId: String) { receivedActionId = actionId }
        })
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.ACTION"}]}"""
        )

        // Simulate tap via the onAction lambda captured by registry.
        registry.simulateTap("com.example.ACTION")

        assertEquals("com.example.ACTION", receivedActionId)
    }

    @Test
    fun dispatchChooserAction_listenerNotSet_doesNotThrow() {
        val registry = FakeRegistry(tokenToReturn = 1L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.clearShareChooserActionListener()
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"}]}"""
        )

        registry.simulateTap("com.example.A")
        // No exception = pass.
    }

    @Test
    fun dispatchChooserAction_listenerThrows_doesNotPropagateException() {
        val registry = FakeRegistry(tokenToReturn = 1L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareChooserActionListener(object : UnityAndroidShareManager.ShareChooserActionListener {
            override fun onChooserAction(actionId: String) { throw RuntimeException("Unity crash") }
        })
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"}]}"""
        )

        // Should not throw.
        registry.simulateTap("com.example.A")
    }

    @Test
    fun clearShareChooserActionListener_unregistersCurrentToken() {
        val registry = FakeRegistry()
        // Inject registry and token directly to test clearShareChooserActionListener in isolation,
        // avoiding the shareText flow which may throw in a JVM stub environment.
        setChooserActionRegistryForTest(registry)
        setChooserActionTokenForTest(7L)

        // clearShareChooserActionListener uses runOnMain. In the JVM stub environment,
        // Looper.myLooper() == Looper.getMainLooper() (both resolve to the same stub instance),
        // so the block runs synchronously — the assertion below is safe.
        UnityAndroidShareManager.clearShareChooserActionListener()

        assertEquals(7L, registry.lastUnregisteredToken)
    }

    @Test
    fun shareText_withNoChooserActions_replacesExistingRegistration() {
        val registry = FakeRegistry(tokenToReturn = 1L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        // First share with actions.
        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"}]}"""
        )

        // Second share without chooserActions: registry.register([]) must be called so the real
        // AndroidShareChooserActionReceiverRegistry unregisters the previous receiver.
        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello"}"""
        )

        assertEquals(emptyList<String>(), registry.lastRegisteredActionIds)
    }

    @Test
    fun consecutiveShareText_replacesRegistration() {
        val registry = FakeRegistry(tokenToReturn = 1L)
        UnityAndroidShareManager.chooserActionRegistryFactory = { registry }
        UnityAndroidShareManager.setShareOperationListener(CapturingListener())

        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"A","iconBase64":"x","intentAction":"com.example.A"}]}"""
        )

        // Second share: register is called again with new action.
        UnityAndroidShareManager.shareText(
            context = FakeContext(),
            shareJson = """{"text":"hello","chooserActions":[{"label":"B","iconBase64":"x","intentAction":"com.example.B"}]}"""
        )

        assertEquals(listOf("com.example.B"), registry.lastRegisteredActionIds)
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

    private class LaunchFailingFakeContext : FakeContext() {
        override fun startActivity(intent: Intent) {
            throw ActivityNotFoundException("simulated launch failure")
        }
    }

    private class FakeRegistry(
        private val tokenToReturn: Long = 1L
    ) : ShareChooserActionReceiverRegistry {
        var lastRegisteredActionIds: List<String> = emptyList()
        var lastUnregisteredToken: Long? = null
        private var capturedOnAction: ((String) -> Unit)? = null

        override fun register(actionIds: List<String>, onAction: (String) -> Unit): Long {
            lastRegisteredActionIds = actionIds
            capturedOnAction = onAction
            return tokenToReturn
        }

        override fun unregister(token: Long) {
            lastUnregisteredToken = token
        }

        fun simulateTap(actionId: String) {
            capturedOnAction?.invoke(actionId)
        }
    }

    private fun resetChooserActionRegistry() {
        val field = UnityAndroidShareManager::class.java.getDeclaredField("chooserActionRegistry")
        field.isAccessible = true
        field.set(UnityAndroidShareManager, null)
    }

    private fun setChooserActionRegistryForTest(registry: ShareChooserActionReceiverRegistry) {
        val field = UnityAndroidShareManager::class.java.getDeclaredField("chooserActionRegistry")
        field.isAccessible = true
        field.set(UnityAndroidShareManager, registry)
    }

    private fun setChooserActionTokenForTest(token: Long) {
        val field = UnityAndroidShareManager::class.java.getDeclaredField("chooserActionToken")
        field.isAccessible = true
        field.set(UnityAndroidShareManager, token)
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
