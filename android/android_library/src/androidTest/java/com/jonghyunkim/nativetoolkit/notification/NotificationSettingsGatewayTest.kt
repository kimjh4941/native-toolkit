package com.jonghyunkim.nativetoolkit.notification

import android.app.Activity
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.notification.data.repository.AndroidNotificationSettingsGateway
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.testing.PlainActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// IT-08 of the Kotlin API design: settings screens from an Activity and from the Application.
@RunWith(AndroidJUnit4::class)
class NotificationSettingsGatewayTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private var scenario: ActivityScenario<PlainActivity>? = null

    @After
    fun tearDown() {
        device.pressBack()
        device.waitForIdle()
        scenario?.close()
    }

    private fun settingsInFront(): Boolean =
        device.wait(Until.hasObject(By.pkg("com.android.settings").depth(0)), 10_000)

    @Test
    fun fromTheApplicationContext_opensTheNotificationSettingsInANewTask() {
        val result = AndroidNotificationSettingsGateway(context).open(NotificationSettingsTarget.NOTIFICATIONS)
        assertEquals(NotificationSettingsOpenResult.OPENED, result)
        assertTrue("the settings app did not come to the front", settingsInFront())
    }

    @Test
    fun fromAnActivity_opensTheAppDetails() {
        scenario = ActivityScenario.launch(PlainActivity::class.java)
        var result: NotificationSettingsOpenResult? = null
        scenario!!.onActivity { activity: Activity ->
            result = AndroidNotificationSettingsGateway(activity).open(NotificationSettingsTarget.APP_DETAILS)
        }
        assertEquals(NotificationSettingsOpenResult.OPENED, result)
        assertTrue("the settings app did not come to the front", settingsInFront())
    }

    @Test
    fun exactAlarmScreen_opens() {
        val result = AndroidNotificationSettingsGateway(context).open(NotificationSettingsTarget.EXACT_ALARM)
        // The settings app accepts this action with a package: URI (checked on API 35 and 36).
        assertEquals(NotificationSettingsOpenResult.OPENED, result)
        assertTrue("the settings app did not come to the front", settingsInFront())
    }

    @Test
    fun canScheduleExactAlarms_matchesAlarmManager() {
        val alarmManager = context.getSystemService(android.app.AlarmManager::class.java)
        assertEquals(alarmManager.canScheduleExactAlarms(), AndroidNotificationSettingsGateway(context).canScheduleExactAlarms())
    }
}
