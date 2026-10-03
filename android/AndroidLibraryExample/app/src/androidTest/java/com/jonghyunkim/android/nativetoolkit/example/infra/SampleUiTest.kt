package com.jonghyunkim.android.nativetoolkit.example.infra

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.jonghyunkim.android.nativetoolkit.example.MainActivity
import org.junit.After
import org.junit.Before
import org.junit.Rule

/**
 * Base class of the sample's UI tests: launches [MainActivity], prepares the device state and
 * cleans up before and after each test (sections 3.5 and 4 of the UI test design).
 */
abstract class SampleUiTest {

    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    protected val instrumentation = InstrumentationRegistry.getInstrumentation()
    protected val context = instrumentation.targetContext
    protected val device: UiDevice = UiDevice.getInstance(instrumentation)

    protected val app by lazy { SampleApp(compose) }
    protected val notifications by lazy { ActiveNotifications(context) }
    protected val shade by lazy { NotificationShade(instrumentation, device) }
    protected val toasts by lazy { Toasts(instrumentation) }
    protected val dialogs by lazy { ViewDialogs(instrumentation, device) }
    protected val sharesheet by lazy { Sharesheet(device) }
    protected val shareTarget by lazy { ShareTargetApp(device) }
    protected val state by lazy { DeviceState(instrumentation, device) }

    /** False for the host-state cases, whose permissions the host has revoked on purpose. */
    protected open val grantPermissions: Boolean = true

    @Before
    fun prepareDevice() {
        if (grantPermissions) state.allowAll()
        state.cleanup()
        toasts.start()
    }

    @After
    fun restoreDevice() {
        toasts.stop()
        state.cleanup()
    }
}
