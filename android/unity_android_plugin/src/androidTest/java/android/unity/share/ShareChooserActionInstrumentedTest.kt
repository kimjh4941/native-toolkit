package android.unity.share

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for the dynamic chooser-action receiver registration.
 *
 * These tests require API 34+ to verify the full registration path.
 * On API < 34 the receiver is not registered (SDK gate), so broadcast tests are skipped.
 * Requires a connected device or emulator running API 34+.
 *
 * Note: The full PendingIntent path (real Sharesheet → chooser action tap → listener callback)
 * cannot be automated and requires manual verification on API 34+.
 */
@RunWith(AndroidJUnit4::class)
class ShareChooserActionInstrumentedTest {

    private lateinit var appContext: Context
    private lateinit var registry: AndroidShareChooserActionReceiverRegistry

    // Tracks the last registered token so tearDown can always clean up even after a test failure.
    private var activeToken = 0L

    @Before
    fun setUp() {
        appContext = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        registry = AndroidShareChooserActionReceiverRegistry(appContext)
        activeToken = 0L
    }

    @After
    fun tearDown() {
        // Unregister the active receiver regardless of test outcome.
        registry.unregister(activeToken)
        activeToken = 0L

        // Reset Manager state set by manager-level tests.
        UnityAndroidShareManager.clearShareChooserActionListener()
        UnityAndroidShareManager.clearShareOperationListener()
        UnityAndroidShareManager.chooserActionRegistryFactory =
            { ctx -> AndroidShareChooserActionReceiverRegistry(ctx.applicationContext) }
    }

    // --- Registry-level tests ---

    @Test
    fun register_emptyActionIds_returnsZeroToken() {
        val token = registry.register(emptyList()) { }
        assertEquals(0L, token)
    }

    @Test
    fun register_validActionIds_returnsPositiveToken() {
        val token = registry.register(listOf("com.example.test.ACTION_A")) { }
        activeToken = token
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            assertEquals(0L, token)
        } else {
            assertTrue("Expected positive token on API 34+", token > 0L)
        }
    }

    @Test
    fun register_thenBroadcast_receivesAction() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        var received: String? = null
        val action = "${appContext.packageName}.test.ACTION_SINGLE"
        activeToken = registry.register(listOf(action)) { received = it }
        assertTrue("Expected positive token", activeToken > 0L)

        appContext.sendBroadcast(Intent(action).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertEquals(action, received)
    }

    @Test
    fun register_multipleActions_eachBroadcastReceivedSeparately() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        val received = mutableListOf<String>()
        val actionA = "${appContext.packageName}.test.ACTION_MULTI_A"
        val actionB = "${appContext.packageName}.test.ACTION_MULTI_B"
        activeToken = registry.register(listOf(actionA, actionB)) { received.add(it) }

        appContext.sendBroadcast(Intent(actionA).setPackage(appContext.packageName))
        appContext.sendBroadcast(Intent(actionB).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertEquals(listOf(actionA, actionB), received.sorted())
    }

    @Test
    fun consecutiveRegister_replacesOldReceiver_onlyNewActionReceived() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        val received = mutableListOf<String>()
        val actionA = "${appContext.packageName}.test.ACTION_REPLACE_A"
        val actionB = "${appContext.packageName}.test.ACTION_REPLACE_B"

        registry.register(listOf(actionA)) { received.add(it) }
        activeToken = registry.register(listOf(actionB)) { received.add(it) }

        appContext.sendBroadcast(Intent(actionA).setPackage(appContext.packageName))
        appContext.sendBroadcast(Intent(actionB).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertEquals(listOf(actionB), received)
    }

    @Test
    fun unregister_afterClear_broadcastNotReceived() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        var received: String? = null
        val action = "${appContext.packageName}.test.ACTION_AFTER_CLEAR"
        val token = registry.register(listOf(action)) { received = it }
        // Explicitly unregister; tearDown activeToken stays 0 so no double-unregister.
        registry.unregister(token)

        appContext.sendBroadcast(Intent(action).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertNull(received)
    }

    @Test
    fun unregister_staleToken_doesNotUnregisterCurrentReceiver() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        var received: String? = null
        val action = "${appContext.packageName}.test.ACTION_STALE"

        val token1 = registry.register(listOf(action)) { }
        activeToken = registry.register(listOf(action)) { received = it }

        registry.unregister(token1)  // stale: must not unregister current

        appContext.sendBroadcast(Intent(action).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertEquals(action, received)
    }

    @Test
    fun register_withNoChooserActions_unregistersOldReceiver() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        var received: String? = null
        val action = "${appContext.packageName}.test.ACTION_NO_ACTIONS"
        registry.register(listOf(action)) { received = it }

        // Empty list triggers unregister of previous receiver.
        activeToken = registry.register(emptyList()) { }
        assertEquals(0L, activeToken)

        appContext.sendBroadcast(Intent(action).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertNull(received)
    }

    // --- Manager-level end-to-end test ---

    /**
     * Verifies the full path: setShareChooserActionListener → shareText (with no-op startActivity)
     * → real receiver registration → broadcast → ShareChooserActionListener.onChooserAction.
     *
     * This is the closest automated approximation of the real flow. The actual PendingIntent path
     * (Sharesheet UI → chooser action tap → system broadcast) requires manual verification on API 34+.
     */
    @Test
    fun manager_shareTextThenBroadcast_listenerReceivesAction() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return

        val action = "${appContext.packageName}.test.ACTION_MANAGER_E2E"
        var received: String? = null

        UnityAndroidShareManager.chooserActionRegistryFactory =
            { _ -> AndroidShareChooserActionReceiverRegistry(appContext) }
        UnityAndroidShareManager.setShareOperationListener(
            object : UnityAndroidShareManager.ShareOperationListener {
                override fun onShareOperation(operation: String, isSuccessful: Boolean, errorMessage: String?) {}
                override fun onShareResult(operation: String, selectedPackageName: String?) {}
            }
        )
        UnityAndroidShareManager.setShareChooserActionListener(
            object : UnityAndroidShareManager.ShareChooserActionListener {
                override fun onChooserAction(actionId: String) { received = actionId }
            }
        )

        // A minimal valid 1×1 pixel PNG in Base64, accepted by the library's icon decoder.
        val iconBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        val shareJson = """{"text":"hello","chooserActions":[{"label":"Test","iconBase64":"$iconBase64","intentAction":"$action"}]}"""

        // NoOpStartActivityContext prevents ActivityNotFoundException while keeping the registration.
        UnityAndroidShareManager.shareText(NoOpStartActivityContext(appContext), shareJson)

        // Simulate chooser action tap via direct broadcast (real PendingIntent path needs manual check).
        appContext.sendBroadcast(Intent(action).setPackage(appContext.packageName))
        Thread.sleep(300)

        assertEquals(action, received)
    }

    // --- Helpers ---

    private fun assertTrue(message: String, condition: Boolean) {
        if (!condition) throw AssertionError(message)
    }

    /** Context that silences startActivity so shareText registration survives without a real Sharesheet. */
    private class NoOpStartActivityContext(base: Context) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = this
        override fun startActivity(intent: Intent) { /* no-op: prevents ActivityNotFoundException */ }
    }
}
