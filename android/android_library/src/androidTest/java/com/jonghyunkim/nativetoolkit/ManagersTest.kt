package com.jonghyunkim.nativetoolkit

import android.content.Context
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.clipboard.application.port.ClipboardRepository
import com.jonghyunkim.nativetoolkit.clipboard.application.usecase.ClipboardUseCases
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardDomainError
import com.jonghyunkim.nativetoolkit.clipboard.domain.error.ClipboardErrorCode
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipDescriptionInfo
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipReadResult
import com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager
import com.jonghyunkim.nativetoolkit.clipboard.presentation.ClipboardEvents
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationPermissionPort
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationSettingsPort
import com.jonghyunkim.nativetoolkit.notification.application.usecase.CancelNotificationPermissionRequestUseCase
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.application.usecase.RequestNotificationPermissionUseCase
import com.jonghyunkim.nativetoolkit.notification.domain.error.PermissionRequestDomainError
import com.jonghyunkim.nativetoolkit.notification.domain.model.ActiveNotification
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.share.application.port.RichPreviewShareRepository
import com.jonghyunkim.nativetoolkit.share.application.usecase.CancelShareSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareForSelectionUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareTextWithActionsUseCase
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareUseCases
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager
import com.jonghyunkim.nativetoolkit.share.presentation.ShareEvents
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.lang.ref.WeakReference

// IT-27 of the Kotlin API design (6.3): every Manager operation gives the same result, exception
// and thread as what it delegates to; getInstance returns one instance per process and keeps no
// Activity.
@RunWith(AndroidJUnit4::class)
class ManagersTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext

    private val calls = mutableListOf<String>()

    private inline fun <reified E : Throwable> assertThrows(block: () -> Unit): E {
        try {
            block()
        } catch (e: Throwable) {
            if (e is E) return e
            throw AssertionError("expected ${E::class.java.simpleName}, got $e", e)
        }
        fail("expected ${E::class.java.simpleName}")
        throw AssertionError()
    }

    // --- notification ---

    private val command = AndroidNotificationCommand(NotificationContent(id = 2701, title = "t", message = "m"))
    private val channel = NotificationChannel(id = "it27", name = "IT-27")
    private val active = listOf(ActiveNotification(id = 1, tag = null, channelId = "c", title = "t", message = "x", isOngoing = false, groupKey = null))
    private var notificationFails = false

    private val notificationRepository = object : NotificationCommandRepository {
        private fun call(name: String) {
            calls += name
            if (notificationFails) throw IllegalStateException(name)
        }
        override fun send(command: AndroidNotificationCommand) = call("send:${command.content.id}")
        override fun update(command: AndroidNotificationCommand) = call("update:${command.content.id}")
        override fun cancel(id: Int, tag: String?) = call("cancel:$id:$tag")
        override fun cancelAll() = call("cancelAll")
        override fun createChannel(channel: NotificationChannel) = call("createChannel:${channel.id}")
        override fun createChannels(channels: List<NotificationChannel>) = call("createChannels:${channels.size}")
        override fun deleteChannel(channelId: String) = call("deleteChannel:$channelId")
        override fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean {
            call("schedule:${command.content.id}:${schedule.triggerAtMillis}")
            return true
        }
        override fun cancelScheduled(id: Int, tag: String?) = call("cancelScheduled:$id:$tag")
        override fun cancelAllScheduled() = call("cancelAllScheduled")
        override fun restoreScheduled() = call("restoreScheduled")
        override fun getActive(): List<ActiveNotification> {
            call("getActive")
            return active
        }
        override fun hasPermission(): Boolean {
            call("hasPermission")
            return true
        }
        override fun areNotificationsEnabled(): Boolean {
            call("areNotificationsEnabled")
            return false
        }
    }

    private var permissionAnswer: PermissionRequestResult = PermissionRequestResult.Granted
    private val permissionPort = object : NotificationPermissionPort {
        override fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit) {
            calls += "request"
            onResult(permissionAnswer)
        }
        override fun cancel(requestId: Long) {
            calls += "cancelRequest:$requestId"
        }
    }

    private val settingsFrom = mutableListOf<Context>()
    private val settingsPort: (Context) -> NotificationSettingsPort = { from ->
        settingsFrom += from
        object : NotificationSettingsPort {
            override fun canScheduleExactAlarms(): Boolean = true
            override fun open(target: NotificationSettingsTarget): NotificationSettingsOpenResult {
                calls += "open:$target"
                return NotificationSettingsOpenResult.OPENED_FALLBACK
            }
        }
    }

    private fun notificationManager() = AndroidNotificationManager(
        appContext = context.applicationContext,
        useCases = NotificationUseCases(notificationRepository),
        requestPermissionUseCase = RequestNotificationPermissionUseCase(permissionPort),
        cancelPermissionRequestUseCase = CancelNotificationPermissionRequestUseCase(permissionPort),
        settingsPort = settingsPort
    )

    @Test
    fun notification_existingOperations_delegateWithTheSameResults() {
        val manager = notificationManager()
        val schedule = NotificationSchedule(triggerAtMillis = 99L)
        assertTrue(manager.show(command).isSuccess)
        assertTrue(manager.update(command).isSuccess)
        assertTrue(manager.cancel(1, "t").isSuccess)
        assertTrue(manager.cancelAll().isSuccess)
        assertTrue(manager.createChannel(channel).isSuccess)
        assertTrue(manager.createChannels(listOf(channel, channel)).isSuccess)
        assertTrue(manager.deleteChannel("c").isSuccess)
        assertTrue(manager.schedule(command, schedule).isSuccess)
        assertTrue(manager.cancelScheduled(2, null).isSuccess)
        assertTrue(manager.cancelAllScheduled().isSuccess)
        assertTrue(manager.restoreScheduled().isSuccess)
        assertEquals(active, manager.getActive())
        assertTrue(manager.hasPermission())
        assertFalse(manager.areNotificationsEnabled())
        assertEquals(
            listOf(
                "send:2701", "update:2701", "cancel:1:t", "cancelAll", "createChannel:it27", "createChannels:2",
                "deleteChannel:c", "schedule:2701:99", "cancelScheduled:2:null", "cancelAllScheduled",
                "restoreScheduled", "getActive", "hasPermission", "areNotificationsEnabled"
            ),
            calls
        )
    }

    @Test
    fun notification_failuresComeBackAsTheUseCasesReturnThem() {
        notificationFails = true
        val manager = notificationManager()
        val expected = NotificationUseCases(notificationRepository).show(command).exceptionOrNull()
        val actual = manager.show(command).exceptionOrNull()
        assertEquals(expected?.javaClass, actual?.javaClass)
        assertEquals(expected?.message, actual?.message)
        assertTrue(manager.schedule(command, NotificationSchedule(1L)).exceptionOrNull() is IllegalStateException)
    }

    @Test
    fun notification_isScheduled_readsTheLibraryStore_whateverTheRepository() {
        val manager = notificationManager()
        assertEquals(NotificationUseCases(notificationRepository).isScheduled(context, 2799, null), manager.isScheduled(2799))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun notification_permission_callbackAndSuspendVersions() {
        val manager = notificationManager()
        val results = mutableListOf<PermissionRequestResult>()
        val id = manager.requestPermission { results += it }
        assertTrue(id > 0)
        // The use case completes on the main thread, never inside the call.
        instrumentation.waitForIdleSync()
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Granted), results)

        assertTrue(runBlocking { manager.requestPermission() })
        permissionAnswer = PermissionRequestResult.Denied
        assertFalse(runBlocking { manager.requestPermission() })
        permissionAnswer = PermissionRequestResult.Canceled(com.jonghyunkim.nativetoolkit.common.domain.CancelReason.HOST_DESTROYED)
        assertThrows<PermissionRequestDomainError.Canceled> { runBlocking { manager.requestPermission() } }
        permissionAnswer = PermissionRequestResult.Failed(com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason.NOT_FOREGROUND)
        val failed = assertThrows<PermissionRequestDomainError.Unavailable> { runBlocking { manager.requestPermission() } }
        assertEquals(com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason.NOT_FOREGROUND, failed.reason)

        manager.cancelPermissionRequest(5L)
        assertTrue("cancelRequest:5" in calls)
    }

    @Test
    fun notification_cancellingTheCoroutine_cancelsTheRequest() {
        val hanging = object : NotificationPermissionPort {
            override fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit) {
                calls += "request:$requestId"
            }
            override fun cancel(requestId: Long) {
                calls += "cancelRequest:$requestId"
            }
        }
        val manager = AndroidNotificationManager(
            context.applicationContext, NotificationUseCases(notificationRepository),
            RequestNotificationPermissionUseCase(hanging), CancelNotificationPermissionRequestUseCase(hanging), settingsPort
        )
        runBlocking {
            val deferred = async { manager.requestPermission() }
            while (calls.none { it.startsWith("request:") }) kotlinx.coroutines.delay(10)
            deferred.cancel()
            assertThrows<CancellationException> { runBlocking { deferred.await() } }
        }
        val id = calls.first { it.startsWith("request:") }.removePrefix("request:")
        assertTrue("cancelRequest:$id" in calls)
    }

    @Test
    fun notification_settings_openFromTheGivenContext_orTheApplication() {
        val manager = notificationManager()
        assertTrue(manager.canScheduleExactAlarms())
        assertEquals(NotificationSettingsOpenResult.OPENED_FALLBACK, manager.openSettings(NotificationSettingsTarget.EXACT_ALARM))
        val from = object : android.content.ContextWrapper(context) {}
        manager.openSettings(NotificationSettingsTarget.NOTIFICATIONS, from)
        assertEquals(listOf(context.applicationContext, context.applicationContext, from), settingsFrom)
        assertEquals(listOf("open:EXACT_ALARM", "open:NOTIFICATIONS"), calls)
    }

    @Test
    fun notification_eventsAreTheLibraryHubs() {
        val manager = notificationManager()
        assertSame(NotificationEvents.interactions, manager.interactions)
        assertSame(NotificationEvents.shown, manager.shown)
    }

    // --- share ---

    private val shareRepository = object : RichPreviewShareRepository {
        override fun shareText(content: ShareContent) {
            calls += "shareText"
        }
        override fun shareText(content: ShareContent, preview: SharePreviewOptions) {
            calls += "shareTextPreview:${preview.title}"
        }
        override fun shareImage(filePath: String, mimeType: String) {
            calls += "shareImage:$filePath:$mimeType"
        }
        override fun shareImages(filePaths: List<String>) {
            calls += "shareImages:${filePaths.size}"
        }
        override fun shareFile(filePath: String) {
            calls += "shareFile:$filePath"
        }
        override fun shareFiles(filePaths: List<String>) {
            calls += "shareFiles:${filePaths.size}"
        }
        override fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray) {
            calls += "register:${target.id}:${iconBytes.size}"
        }
        override fun removeDirectShareTargets(ids: List<String>) {
            calls += "remove:$ids"
        }
        override fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit) = Unit
        override fun shareWithCallback(content: ShareContent, preview: SharePreviewOptions, onResult: (String?) -> Unit, onFinished: () -> Unit) {
            calls += "shareWithCallback"
            onResult("pkg")
            onFinished()
        }
        override fun cancelPendingCallback() {
            calls += "cancelPendingCallback"
        }
        override fun shareForSelection(content: ShareContent, preview: SharePreviewOptions): Long {
            calls += "shareForSelection"
            return 9L
        }
        override fun cancelShareSelection(token: Long) {
            calls += "cancelShareSelection:$token"
        }
        override fun shareTextWithActions(content: ShareContent, actions: List<ShareChooserAction>, preview: SharePreviewOptions) {
            calls += "shareTextWithActions:${actions.map { it.id }}"
        }
    }

    private fun shareManager() = AndroidShareManager(
        ShareUseCases(shareRepository),
        ShareForSelectionUseCase(shareRepository),
        CancelShareSelectionUseCase(shareRepository),
        ShareTextWithActionsUseCase(shareRepository)
    )

    @Test
    fun share_operationsDelegate_andShareTextIsTheUseCaseWithEmptyActions() {
        val manager = shareManager()
        val content = ShareContent(text = "t")
        val preview = SharePreviewOptions(title = "P")
        manager.shareText(content, preview)
        ShareUseCases(shareRepository).shareText(content, preview)
        assertEquals(calls[0], calls[1])
        calls.clear()

        manager.shareImage("/a.png", "image/png")
        manager.shareImages(listOf("/a", "/b"))
        val file = java.io.File(context.cacheDir, "it27.txt").apply { writeText("x") }
        manager.shareFile(file.absolutePath)
        manager.shareFiles(listOf("/f"))
        manager.registerDirectShareTarget(DirectShareTarget(id = "d", label = "D"), byteArrayOf(1, 2))
        manager.removeDirectShareTargets(listOf("d"))
        var picked: String? = null
        var finished = 0
        manager.shareWithCallback(content, onResult = { picked = it }, onFinished = { finished++ })
        manager.cancelPendingCallback()
        manager.shareTextWithActions(content, listOf(ShareChooserAction("x", "X", byteArrayOf(1))))
        assertEquals(9L, manager.shareForSelection(content))
        manager.cancelShareSelection(9L)
        assertEquals("pkg", picked)
        assertEquals(1, finished)
        assertEquals(
            listOf(
                "shareImage:/a.png:image/png", "shareImages:2", "shareFile:${java.io.File(context.cacheDir, "it27.txt").absolutePath}", "shareFiles:1", "register:d:2", "remove:[d]",
                "shareWithCallback", "cancelPendingCallback", "shareTextWithActions:[x]", "shareForSelection",
                "cancelShareSelection:9"
            ),
            calls
        )
        assertSame(ShareEvents.selections, manager.selections)
        assertSame(ShareEvents.chooserActions, manager.chooserActions)
    }

    @Test
    fun share_validationExceptionsAreTheUseCases() {
        val manager = shareManager()
        assertThrows<ShareDomainError.EmptyContent> { manager.shareText(ShareContent(text = "")) }
        assertThrows<ShareDomainError.EmptyContent> { manager.shareForSelection(ShareContent(text = " ")) }
        assertThrows<ShareDomainError.EmptyFileList> { manager.shareFiles(emptyList()) }
        assertThrows<ShareDomainError.FileNotFound> { manager.shareFile("/no/such/file") }
        assertThrows<ShareDomainError.InvalidChooserAction> {
            manager.shareTextWithActions(ShareContent(text = "t"), listOf(ShareChooserAction("", "X", byteArrayOf(1))))
        }
        assertTrue(calls.isEmpty())
    }

    // --- clipboard ---

    private var clipboardError: Exception? = null
    private val clip = ClipReadResult(label = "l", mimeTypes = listOf("text/plain"), items = emptyList())
    private val description = ClipDescriptionInfo(label = "l", mimeTypes = listOf("text/plain"), isStyledText = false, classificationStatus = null)
    private val clipboardRepository = object : ClipboardRepository {
        override fun copy(content: ClipContent) {
            clipboardError?.let { throw it }
            calls += "copy:${content.javaClass.simpleName}"
        }
        override fun read(): ClipReadResult? {
            calls += "read"
            return clip
        }
        override fun hasClip(): Boolean {
            calls += "hasClip"
            return true
        }
        override fun getDescription(): ClipDescriptionInfo? {
            calls += "getDescription"
            return description
        }
        override fun clear() {
            calls += "clear"
        }
    }

    @Test
    fun clipboard_operationsDelegate_withTheSameResultsAndExceptions() {
        val manager = AndroidClipboardManager(context.applicationContext, ClipboardUseCases(clipboardRepository))
        manager.copyPlainText(ClipContent.PlainText("p"))
        manager.copyHtmlText(ClipContent.HtmlText("p", "<b>p</b>"))
        manager.copyUri(ClipContent.UriContent("content://x/1"))
        manager.copyMultipleText(ClipContent.MultipleText(listOf("a", "b")))
        manager.clear()
        assertEquals(clip, manager.read())
        assertTrue(manager.hasClip())
        assertEquals(description, manager.getDescription())
        assertEquals(
            listOf("copy:PlainText", "copy:HtmlText", "copy:UriContent", "copy:MultipleText", "clear", "read", "hasClip", "getDescription"),
            calls
        )
        assertThrows<ClipboardDomainError.EmptyContent> { manager.copyHtmlText(ClipContent.HtmlText("p", " ")) }
        assertThrows<ClipboardDomainError.EmptyItemList> { manager.copyMultipleText(ClipContent.MultipleText(emptyList())) }
        assertThrows<ClipboardDomainError.InvalidUri> { manager.copyUri(ClipContent.UriContent("javascript:x")) }
        clipboardError = SecurityException("denied")
        val error = assertThrows<SecurityException> { manager.copyPlainText(ClipContent.PlainText("p")) }
        assertEquals(ClipboardErrorCode.SECURITY, manager.errorCodeOf(error))
        assertEquals(ClipboardErrorCode.of(ClipboardDomainError.EmptyItemList), manager.errorCodeOf(ClipboardDomainError.EmptyItemList))
        assertSame(ClipboardEvents.changes, manager.changes)
    }

    @Test
    fun clipboard_observation_isMainThreadOnly() {
        val manager = AndroidClipboardManager.getInstance(context)
        assertThrows<IllegalStateException> { manager.startObserving() }
        instrumentation.runOnMainSync {
            manager.startObserving()
            assertTrue(manager.isObserving())
            manager.stopObserving()
            assertFalse(manager.isObserving())
        }
    }

    // --- getInstance ---

    @Test
    fun getInstance_isOnePerProcess_andKeepsNoActivity() {
        val scenario = ActivityScenario.launch(TestFragmentActivity::class.java)
        var weak: WeakReference<TestFragmentActivity>? = null
        val managers = mutableListOf<Any>()
        scenario.onActivity { activity ->
            weak = WeakReference(activity)
            managers += AndroidNotificationManager.getInstance(activity)
            managers += AndroidShareManager.getInstance(activity)
            managers += AndroidClipboardManager.getInstance(activity)
            managers += AndroidDialogManager.getInstance(activity)
        }
        assertSame(managers[0], AndroidNotificationManager.getInstance(context))
        assertSame(managers[1], AndroidShareManager.getInstance(context))
        assertSame(managers[2], AndroidClipboardManager.getInstance(context))
        assertSame(managers[3], AndroidDialogManager.getInstance(context))
        scenario.close()
        instrumentation.waitForIdleSync()

        val deadline = System.currentTimeMillis() + 10_000
        while (weak!!.get() != null && System.currentTimeMillis() < deadline) {
            Runtime.getRuntime().gc()
            System.runFinalization()
            Thread.sleep(100)
        }
        assertNull("the closed Activity is still reachable", weak!!.get())
        assertEquals(4, managers.size)
    }
}
