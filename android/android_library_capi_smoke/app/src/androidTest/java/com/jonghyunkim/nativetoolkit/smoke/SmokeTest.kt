package com.jonghyunkim.nativetoolkit.smoke

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The smoke of the C ABI (C ABI design part 1, chapter 6; part 2, 12.4), against the R8 release
 * build of an app that takes the AARs from the Maven repository only. Which path, STL and keep
 * rules the build used is in BuildConfig.
 */
@RunWith(AndroidJUnit4::class)
class SmokeTest {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val device: UiDevice
        get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test
    fun aCConsumerInitializesNotifiesCopiesAndShowsADialog() {
        assumeFalse("the build without the keep rules has its own test", BuildConfig.NO_KEEP)
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            Smoke.load()
            if (BuildConfig.MANUAL) {
                // Startup is off, so nothing has followed the foreground Activity yet: the manual
                // path passes the Activity, which becomes the first foreground one (part 1, 1.4).
                var activity: MainActivity? = null
                scenario.onActivity { activity = it }
                assertEquals("ntk_android_init", 0, Smoke.init(activity!!))
            }
            assertTrue("not READY", waitUntil { Smoke.isInitialized() == 1 })

            assertEquals("ntk_notification_show", 0, Smoke.notify(SMOKE_ID))
            assertTrue("the notification is not shown", waitUntil {
                context.getSystemService(NotificationManager::class.java).activeNotifications.any { it.id == SMOKE_ID }
            })

            // Reading the clipboard needs the window focus, which the Activity gets shortly.
            assertTrue("the clipboard text did not come back", waitUntil { Smoke.clipboardRoundTrip("ntk smoke") == 0 })

            if (BuildConfig.STL != "none") assertEquals(35, Smoke.cxxLength())

            assertEquals("ntk_dialog_show_alert_async", 0, Smoke.showAlert())
            val ok = device.wait(Until.findObject(By.text(Pattern.compile("OK", Pattern.CASE_INSENSITIVE))), TIMEOUT_MS)
            assertTrue("the alert is not shown", ok != null)
            ok.click()
            // [error, answer]: NONE, and the button.
            assertEquals(listOf(0, 0), Smoke.awaitAlert(TIMEOUT_MS.toInt()).toList())
        }
    }

    @Test
    fun withoutTheKeepRulesTheInitializationFailsAndTheAppKeepsRunning() {
        // Part 1, chapter 6: R8 renamed or removed the C ABI's Kotlin classes. Both entries say
        // CLASS_NOT_FOUND (2 in C), and nothing crashes, the automatic path at start included.
        assumeTrue(BuildConfig.NO_KEEP)
        ActivityScenario.launch(MainActivity::class.java).use {
            Smoke.load()
            assertEquals(0, Smoke.isInitialized())
            assertEquals("ntk_android_init", 2, Smoke.init(context))
            assertEquals("CLASS_NOT_FOUND", Smoke.kotlinInit(context))
            assertEquals(0, Smoke.isInitialized())
        }
    }

    private fun waitUntil(condition: () -> Boolean): Boolean {
        val until = SystemClock.uptimeMillis() + TIMEOUT_MS
        while (SystemClock.uptimeMillis() < until) {
            if (condition()) return true
            SystemClock.sleep(100)
        }
        return condition()
    }

    private companion object {
        const val SMOKE_ID = 71
        const val TIMEOUT_MS = 10_000L
    }
}
