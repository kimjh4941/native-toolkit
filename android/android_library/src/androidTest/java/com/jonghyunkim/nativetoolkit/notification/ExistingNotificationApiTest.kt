package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.testing.ScheduleTestSupport
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.lang.reflect.Proxy
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases as UseCasesWithRepository

// IT-23 of the Kotlin API design (notification part): NotificationUseCases built with an app's own
// NotificationCommandRepository answers isScheduled(context, ...) from the library's store, as in
// 1.x (8.6), and never calls that repository for it.
@RunWith(AndroidJUnit4::class)
class ExistingNotificationApiTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val library = NotificationUseCases(context)
    private val channel = NotificationChannel(id = "ntk_it23", name = "IT-23", importance = 4)

    // An app's own repository; any call fails the test.
    private val ownRepository = Proxy.newProxyInstance(
        NotificationCommandRepository::class.java.classLoader,
        arrayOf(NotificationCommandRepository::class.java)
    ) { _, method, _ -> throw AssertionError("the app's repository was called: ${method.name}") } as NotificationCommandRepository

    @Before
    fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        ScheduleTestSupport(instrumentation).shell("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow")
        library.createChannel(channel)
        library.cancelAllScheduled()
    }

    @After
    fun tearDown() {
        library.cancelAllScheduled()
    }

    @Test
    fun anOwnRepository_readsTheLibrarysStoreForIsScheduled() {
        val own = UseCasesWithRepository(ownRepository)
        assertFalse(own.isScheduled(context, 2301, "it23"))
        val command = AndroidNotificationCommand(NotificationContent(id = 2301, title = "IT-23", message = "m", tag = "it23", channel = channel))
        assertTrue(library.schedule(command, NotificationSchedule(System.currentTimeMillis() + 600_000, persistAcrossBoot = true)).isSuccess)
        assertTrue(own.isScheduled(context, 2301, "it23"))
        assertFalse(own.isScheduled(context, 2301, null))
        assertFalse(own.isScheduled(context, 2302, "it23"))
        library.cancelAllScheduled()
        assertFalse(own.isScheduled(context, 2301, "it23"))
    }
}
