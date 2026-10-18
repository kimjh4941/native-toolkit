package com.jonghyunkim.nativetoolkit.capitest

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiObject2
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

    /** The Sharesheet's package on API 34 and later. */
    private const val RESOLVER = "com.android.intentresolver"

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
    fun waitText(text: String): Boolean {
        if (device.wait(Until.hasObject(label(text)), TIMEOUT_MS) == true) return true
        logScreen("waitText", text)
        return false
    }

    // A text whatever its case: a dialog button can be shown in capitals (seen in the HWASan
    // build, whose process wrap.sh starts), and the accessibility text then has them too.
    private fun label(text: String) =
        By.text(java.util.regex.Pattern.compile(java.util.regex.Pattern.quote(text), java.util.regex.Pattern.CASE_INSENSITIVE))

    // What the screen shows instead of [text], for the failure's logcat.
    private fun logScreen(where: String, text: String) {
        val shown = device.findObjects(By.textStartsWith("")).mapNotNull { "${it.text}(${it.applicationPackage})" }
        android.util.Log.e("UiDriver", "[$where] \"$text\" not found; the screen shows: $shown")
    }

    /** Whether [text] stays off the screen for [ms]. */
    @JvmStatic
    fun staysAway(text: String, ms: Long): Boolean = device.wait(Until.hasObject(label(text)), ms) != true

    @JvmStatic
    fun gone(text: String): Boolean = device.wait(Until.gone(label(text)), TIMEOUT_MS) == true

    @JvmStatic
    fun click(text: String): Boolean {
        if (device.wait(Until.hasObject(label(text)), TIMEOUT_MS) != true) {
            logScreen("click", text)
            return false
        }
        // A dialog still animating in can drop a click (seen once on the emulator): wait for the
        // screen to settle, then find the object again.
        device.waitForIdle()
        val target = device.findObject(label(text)) ?: return false
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

    /**
     * Clicks the Sharesheet entry (an app, a chooser action) showing [text] and waits until the
     * Sharesheet closes. As the sample's Sharesheet helper: the targets load asynchronously and a
     * device with many apps lists the test target further down, so it waits, scrolls down and
     * up, and retries a click that landed while the list moved.
     */
    @JvmStatic
    fun pick(text: String): Boolean {
        if (!device.wait(Until.hasObject(By.pkg(RESOLVER)), TIMEOUT_MS)) return false
        repeat(3) { attempt ->
            if (attempt > 0 && !device.hasObject(By.pkg(RESOLVER))) return true
            val target = findInSharesheet(text) ?: return false
            try {
                target.click()
            } catch (e: StaleObjectException) {
                return@repeat
            }
            device.waitForIdle()
            if (device.wait(Until.gone(By.pkg(RESOLVER)), 5_000L) == true) return true
        }
        return !device.hasObject(By.pkg(RESOLVER))
    }

    /**
     * Waits for a screen of [pkg] that is about to open, then presses Back until it is gone: a
     * screen opened by a call that returned before it showed. False when it never showed or stayed.
     */
    @JvmStatic
    fun closePackage(pkg: String): Boolean {
        if (device.wait(Until.hasObject(By.pkg(pkg)), TIMEOUT_MS) != true) return false
        repeat(4) {
            device.pressBack()
            if (device.wait(Until.gone(By.pkg(pkg)), 2_000L) == true) {
                device.waitForIdle()
                return true
            }
        }
        return false
    }

    /** Waits until no window of [pkg] is on the screen, then for the screen to settle. */
    @JvmStatic
    fun packageGone(pkg: String): Boolean {
        val gone = device.wait(Until.gone(By.pkg(pkg)), TIMEOUT_MS) == true
        device.waitForIdle()
        return gone
    }

    /** Whether the Sharesheet is on the screen (within the timeout). */
    @JvmStatic
    fun sharesheetShown(): Boolean = device.wait(Until.hasObject(By.pkg(RESOLVER)), TIMEOUT_MS) == true

    private fun findInSharesheet(text: String): UiObject2? {
        device.wait(Until.findObject(By.pkg(RESOLVER).text(text)), 5_000L)?.let { return it }
        // Swipe up through the middle of the screen: the first swipe expands the sheet, the next
        // ones scroll its list. Never down: at the top that pulls the sheet closed, and a swipe
        // from the bottom edge lands on the taskbar.
        val x = device.displayWidth / 2
        repeat(8) {
            if (!device.hasObject(By.pkg(RESOLVER))) return null
            device.swipe(x, device.displayHeight * 3 / 4, x, device.displayHeight / 4, 20)
            device.wait(Until.findObject(By.pkg(RESOLVER).text(text)), 1_500L)?.let { return it }
        }
        // What the screen shows instead, for the failure's logcat.
        val shown = device.findObjects(By.textStartsWith("")).mapNotNull { it.text }
        android.util.Log.e("UiDriver", "[pick] \"$text\" not found; the screen shows: $shown")
        return null
    }

    /**
     * Presses Back until the app is in front again (a Sharesheet or the settings left open). The
     * Sharesheet is translucent, so the app's Activity under it is still started: in front means
     * that the active window is the app's as well.
     */
    @JvmStatic
    fun backToApp(): Boolean {
        repeat(4) {
            if (appInFront()) return true
            device.pressBack()
            waitUntil(1_000) { appInFront() }
        }
        return appInFront()
    }

    private fun appInFront(): Boolean =
        onMain { ForegroundActivityTracker.current() } != null && device.currentPackageName == appContext.packageName

    /**
     * Brings the app to the front again with the window focus: Back first (a screen left open),
     * then, after Home, the test Activity reordered to the front (the instrumented app may start
     * an Activity from the back).
     */
    @JvmStatic
    fun toFront(): Boolean {
        if (!backToApp()) {
            appContext.startActivity(
                Intent(appContext, FocusActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            )
        }
        return waitUntil(TIMEOUT_MS) { onMain { ForegroundActivityTracker.current()?.hasWindowFocus() } == true }
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
