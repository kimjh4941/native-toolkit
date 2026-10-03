package com.jonghyunkim.android.nativetoolkit.example.infra

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.After
import org.junit.Before

/**
 * Base class of the tests that send the sample to the background or reach the running
 * `MainActivity` with an intent from outside (see [UiApp]): received shares, the Sharesheet (it
 * opens in its own task), notification taps. No Compose rule, because the rule loses the activity
 * in those cases: the sample is launched and driven through UiAutomator, and finished after each
 * test so the next one starts from a fresh task.
 */
abstract class ExternalLaunchUiTest {

    protected val instrumentation = InstrumentationRegistry.getInstrumentation()
    protected val context = instrumentation.targetContext
    protected val device: UiDevice = UiDevice.getInstance(instrumentation)

    protected val app by lazy { UiApp(context, device) }
    protected val notifications by lazy { ActiveNotifications(context) }
    protected val shade by lazy { NotificationShade(instrumentation, device) }
    protected val toasts by lazy { Toasts(instrumentation) }
    protected val sharesheet by lazy { Sharesheet(device) }
    protected val shareTarget by lazy { ShareTargetApp(device) }
    protected val state by lazy { DeviceState(instrumentation, device) }

    @Before
    fun prepareDevice() {
        state.allowAll()
        state.cleanup()
        toasts.start()
        app.launch()
    }

    @After
    fun restoreDevice() {
        toasts.stop()
        state.cleanup()
        app.finish()
    }
}
