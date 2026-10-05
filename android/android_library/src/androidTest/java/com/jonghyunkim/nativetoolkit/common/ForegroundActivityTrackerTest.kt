package com.jonghyunkim.nativetoolkit.common

import android.app.Activity
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import com.jonghyunkim.nativetoolkit.testing.PlainActivity
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// IT-02 of the Kotlin API design (8.2): the foreground Activity after the default Startup path,
// with another Activity on top, after that one closes, and after going home; a seed does not
// override what the lifecycle callbacks reported. Seeding an Activity the tracker has not seen is
// checked by the release probe with Startup disabled (IT-01).
@RunWith(AndroidJUnit4::class)
class ForegroundActivityTrackerTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private var scenario: ActivityScenario<TestFragmentActivity>? = null

    @After
    fun tearDown() {
        scenario?.close()
    }

    private fun current(): Activity? {
        var activity: Activity? = null
        instrumentation.runOnMainSync { activity = ForegroundActivityTracker.current() }
        return activity
    }

    // Waits up to 5 s for current() to satisfy [check].
    private fun waitCurrent(check: (Activity?) -> Boolean): Activity? {
        val deadline = System.currentTimeMillis() + 5_000
        var activity = current()
        while (!check(activity) && System.currentTimeMillis() < deadline) {
            Thread.sleep(100)
            activity = current()
        }
        return activity
    }

    private fun resumed(type: Class<out Activity>): Activity? {
        var found: Activity? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).firstOrNull { type.isInstance(it) }
        }
        return found
    }

    @Test
    fun current_followsTheForegroundActivity_andASeedDoesNotOverrideTheCallbacks() {
        assertTrue(LibraryRuntime.isInitialized())
        scenario = ActivityScenario.launch(TestFragmentActivity::class.java)
        device.wait(Until.hasObject(By.text("TestFragmentActivity")), 5_000)
        var first: Activity? = null
        scenario!!.onActivity { first = it }
        assertSame(first, waitCurrent { it === first })

        // Another Activity on top wins; when it finishes, the first one is the foreground again.
        scenario!!.onActivity { it.startActivity(Intent(it, PlainActivity::class.java)) }
        device.wait(Until.hasObject(By.text("PlainActivity")), 5_000)
        val top = resumed(PlainActivity::class.java)
        assertSame(top, waitCurrent { it is PlainActivity })
        instrumentation.runOnMainSync { top!!.finish() }
        assertSame(first, waitCurrent { it === first })

        // Home: no Activity of the app is in the foreground, and seeding a stopped one changes nothing.
        device.pressHome()
        assertNull(waitCurrent { it == null })
        instrumentation.runOnMainSync { ForegroundActivityTracker.seed(first!!) }
        assertNull(current())
    }
}
