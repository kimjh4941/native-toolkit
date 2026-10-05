package com.jonghyunkim.nativetoolkit.capitest

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Presses the dialogs the C ABI shows, for the GoogleTest cases (through TestSupport.h) and the
 * Kotlin tests: wait for a text, click it, type into an input, Back, Home, and finish the
 * foreground Activity (a dialog host destroyed from outside). Also opens the notification shade,
 * swipes a notification away, and tells which Activity of the app is in the foreground.
 */
object UiDriver {

    private const val TIMEOUT_MS = 10_000L

    private val device: UiDevice
        get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Volatile
    private var created = -1

    /**
     * How many Activities the app has created since the first call, which starts counting. A
     * dialog on the transparent host creates one, however briefly it is up.
     */
    @JvmStatic
    fun activitiesCreated(): Int {
        if (created < 0) {
            created = 0
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application
            app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) { created++ }
                override fun onActivityStarted(activity: Activity) = Unit
                override fun onActivityResumed(activity: Activity) = Unit
                override fun onActivityPaused(activity: Activity) = Unit
                override fun onActivityStopped(activity: Activity) = Unit
                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
                override fun onActivityDestroyed(activity: Activity) = Unit
            })
        }
        return created
    }

    @JvmStatic
    fun waitText(text: String): Boolean = device.wait(Until.hasObject(By.text(text)), TIMEOUT_MS) == true

    /** Whether [text] stays off the screen for [ms]. */
    @JvmStatic
    fun staysAway(text: String, ms: Long): Boolean = device.wait(Until.hasObject(By.text(text)), ms) != true

    @JvmStatic
    fun gone(text: String): Boolean = device.wait(Until.gone(By.text(text)), TIMEOUT_MS) == true

    @JvmStatic
    fun click(text: String): Boolean {
        val target = device.wait(Until.findObject(By.text(text)), TIMEOUT_MS) ?: return false
        target.click()
        return true
    }

    /** Clicks the view with resource id [id] (for the system's permission dialog, whatever its language). */
    @JvmStatic
    fun clickRes(id: String): Boolean {
        val target = device.wait(Until.findObject(By.res(id)), TIMEOUT_MS) ?: return false
        target.click()
        return true
    }

    @JvmStatic
    fun waitRes(id: String): Boolean = device.wait(Until.hasObject(By.res(id)), TIMEOUT_MS) == true

    @JvmStatic
    fun waitGoneRes(id: String): Boolean = device.wait(Until.gone(By.res(id)), TIMEOUT_MS) == true

    /** Types into the [index]th text field of the screen. */
    @JvmStatic
    fun type(index: Int, text: String): Boolean {
        device.wait(Until.hasObject(By.clazz("android.widget.EditText")), TIMEOUT_MS)
        val fields = device.findObjects(By.clazz("android.widget.EditText"))
        if (index >= fields.size) return false
        fields[index].text = text
        return true
    }

    @JvmStatic
    fun back() {
        device.pressBack()
    }

    /** Opens the notification shade and waits for [text] in it. */
    @JvmStatic
    fun openShade(text: String): Boolean {
        device.openNotification()
        return waitText(text)
    }

    /**
     * Swipes the notification showing [text] away and waits until it is gone: a fast fling across
     * the screen at its height (a slow swipe over the text alone is not always taken as a
     * dismissal), tried twice.
     */
    @JvmStatic
    fun swipeAway(text: String): Boolean {
        repeat(2) {
            val target = device.wait(Until.findObject(By.text(text)), TIMEOUT_MS) ?: return false
            val y = target.visibleCenter.y
            device.swipe(device.displayWidth / 10, y, device.displayWidth * 9 / 10, y, 5)
            if (device.wait(Until.gone(By.text(text)), TIMEOUT_MS / 2) == true) return true
        }
        return false
    }

    @JvmStatic
    fun closeShade() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cmd statusbar collapse").close()
    }

    /** The simple class name of the app's foreground Activity once one is there, or "" after the timeout. */
    @JvmStatic
    fun foregroundActivity(): String {
        var name = ""
        waitUntil(TIMEOUT_MS) {
            name = onMain { ForegroundActivityTracker.current()?.javaClass?.simpleName } ?: ""
            name.isNotEmpty()
        }
        return name
    }

    /** Sends the app to the back and waits until no Activity of it is in the foreground. */
    @JvmStatic
    fun home(): Boolean {
        device.pressHome()
        return waitUntil(TIMEOUT_MS) { onMain { ForegroundActivityTracker.current() } == null }
    }

    /** Finishes the foreground Activity, such as the transparent dialog host. */
    @JvmStatic
    fun finishForeground(): Boolean = onMain {
        val current = ForegroundActivityTracker.current()
        current?.finish()
        current != null
    } == true

    private fun <T> onMain(block: () -> T): T? {
        var result: T? = null
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            result = block()
            done.countDown()
        }
        done.await(10, TimeUnit.SECONDS)
        return result
    }
}
