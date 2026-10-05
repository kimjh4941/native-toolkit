package com.jonghyunkim.nativetoolkit.capi.jni

import android.app.ServiceStartNotAllowedException
import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.RemoteViewAction
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCustomViewStyleData
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationMessage
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationProgress
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationStyle
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationShown
import com.jonghyunkim.nativetoolkit.notification.presentation.resource.NotificationResourceResolver
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The C ABI's entry to notifications (C ABI design part 2, 5.1, 6.3). The content and channel
 * builders arrive as the bytes of Encoder.h; this reads them back, resolves names (AP-8), adds
 * the event intents (AP-18), checks the permission first where Kotlin would succeed silently
 * (AP-16), applies the progress corrections (AP-9), and maps failures to `ntk_notification_error`
 * (part 2, 11.2). The settings screen and the permission request complete on the main thread.
 */
internal object NotificationBridge {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.NotificationBridge"

    /** The ledger kinds. */
    const val KIND_PERMISSION = 300
    const val KIND_SETTINGS = 301
    const val KIND_INTERACTION = 302
    const val KIND_SHOWN = 303

    /** How many interactions are kept while no C registration is ACTIVE (part 2, AP-21). */
    private const val RETAINED_CAPACITY = 32

    // ntk_notification_error 6 to 15 (part 2, 11.2).
    private const val CANCELED = 6
    private const val CANCELED_BY_SYSTEM = 7
    private const val NOT_FOREGROUND = 8
    private const val HOST_START_FAILED = 9
    private const val PERMISSION_DENIED = 10
    private const val EXACT_ALARM_NOT_ALLOWED = 11
    private const val RESOURCE_NOT_FOUND = 12
    private const val STORAGE_FAILED = 13
    private const val SERVICE_START_NOT_ALLOWED = 14
    private const val SETTINGS_NOT_OPENED = 15

    // ntk_notification_permission_result and ntk_notification_settings_result.
    private const val GRANTED = 0
    private const val DENIED = 1
    private const val OPENED = 0
    private const val OPENED_FALLBACK = 1

    // ntk_notification_event_kind.
    private const val EVENT_BODY_TAP = 0
    private const val EVENT_ACTION = 1
    private const val EVENT_DISMISS = 2

    // ntk_notification_tap.
    private const val TAP_OPEN_APP = 0
    private const val TAP_EVENT_ONLY = 1

    /** C permission request id to Kotlin request id. Main thread only. */
    private val permissionIds = HashMap<Long, Long>()

    // The one EventHub listener per kind of AP-21, added with the first C registration and never
    // removed, and the interactions kept while no C registration is ACTIVE. Main thread only.
    private var interactionHub: EventHub.Registration? = null
    private var shownHub: EventHub.Registration? = null
    private val retained = ArrayDeque<NotificationInteraction>()
    private var delivering = false

    /** A name the app's resources do not have (part 2, 11.2: RESOURCE_NOT_FOUND). */
    private class ResourceMissing(name: String, type: String) : Exception("$type/$name")

    private fun context(): Context {
        Log.d(TAG, "[context]")
        return NtkRuntime.context()
    }

    private fun manager(): AndroidNotificationManager {
        Log.d(TAG, "[manager]")
        return AndroidNotificationManager.getInstance(context())
    }

    /** The value of ntk_notification_error for a failure (part 2, 11.2). */
    fun errorOf(error: Throwable): Int {
        Log.d(TAG, "[errorOf] error: ${error.javaClass.name}")
        return when (error) {
            is ResourceMissing -> RESOURCE_NOT_FOUND
            is IOException -> STORAGE_FAILED
            is ServiceStartNotAllowedException -> SERVICE_START_NOT_ALLOWED
            else -> Errors.common(error)
        }
    }

    private inline fun guarded(name: String, block: () -> Int): Int {
        return try {
            block()
        } catch (e: Throwable) {
            Log.e(TAG, "[$name] failed: ${e.javaClass.name}")
            errorOf(e)
        }
    }

    private fun Result<Unit>.toError(): Int = exceptionOrNull()?.let(::errorOf) ?: Errors.NONE

    // AP-16: Kotlin shows nothing and succeeds without the permission, so it is checked first.
    private fun allowed(): Boolean {
        Log.d(TAG, "[allowed]")
        val manager = manager()
        return manager.hasPermission() && manager.areNotificationsEnabled()
    }

    // --- show, update, remove (OP-20 to OP-23) ---

    @JvmStatic
    fun show(content: ByteArray): Int {
        Log.d(TAG, "[show] size: ${content.size}")
        return guarded("show") {
            val command = command(content)
            if (!allowed()) PERMISSION_DENIED else manager().show(command).toError()
        }
    }

    @JvmStatic
    fun update(content: ByteArray): Int {
        Log.d(TAG, "[update] size: ${content.size}")
        return guarded("update") {
            val command = command(content)
            if (!allowed()) PERMISSION_DENIED else manager().update(command).toError()
        }
    }

    @JvmStatic
    fun remove(id: Int, tag: ByteArray?): Int {
        Log.d(TAG, "[remove] id: $id")
        return guarded("remove") { manager().cancel(id, Utf8.decodeOrNull(tag)).toError() }
    }

    @JvmStatic
    fun removeAll(): Int {
        Log.d(TAG, "[removeAll]")
        return guarded("removeAll") { manager().cancelAll().toError() }
    }

    // --- channels (OP-24, OP-25) ---

    @JvmStatic
    fun createChannel(channel: ByteArray): Int {
        Log.d(TAG, "[createChannel] size: ${channel.size}")
        return guarded("createChannel") { manager().createChannel(Reader(channel).channel()).toError() }
    }

    @JvmStatic
    fun deleteChannel(id: ByteArray): Int {
        Log.d(TAG, "[deleteChannel] size: ${id.size}")
        return guarded("deleteChannel") { manager().deleteChannel(Utf8.decode(id)).toError() }
    }

    // --- schedules (OP-26 to OP-28) ---

    @JvmStatic
    fun schedule(content: ByteArray, triggerAtMillis: Long, exact: Boolean, allowWhileIdle: Boolean,
                 persistAcrossBoot: Boolean, alarmType: Int): Int {
        Log.d(TAG, "[schedule] triggerAtMillis: $triggerAtMillis, exact: $exact, allowWhileIdle: $allowWhileIdle, " +
            "persistAcrossBoot: $persistAcrossBoot, alarmType: $alarmType")
        return guarded("schedule") {
            val command = command(content)
            val manager = manager()
            // AP-16: a past time is shown at once (permission), a future exact one needs exact alarms.
            val past = triggerAtMillis <= System.currentTimeMillis()
            when {
                past && !allowed() -> PERMISSION_DENIED
                !past && exact && !manager.canScheduleExactAlarms() -> EXACT_ALARM_NOT_ALLOWED
                else -> manager.schedule(
                    command,
                    NotificationSchedule(triggerAtMillis, exact, allowWhileIdle, persistAcrossBoot, alarmType)
                ).toError()
            }
        }
    }

    @JvmStatic
    fun cancelScheduled(id: Int, tag: ByteArray?): Int {
        Log.d(TAG, "[cancelScheduled] id: $id")
        return guarded("cancelScheduled") { manager().cancelScheduled(id, Utf8.decodeOrNull(tag)).toError() }
    }

    @JvmStatic
    fun cancelAllScheduled(): Int {
        Log.d(TAG, "[cancelAllScheduled]")
        return guarded("cancelAllScheduled") { manager().cancelAllScheduled().toError() }
    }

    // --- progress (OP-29 to OP-32). The corrections of AP-9; no permission check (a foreground
    // service notification shows without it). ---

    @JvmStatic
    fun startProgress(content: ByteArray): Int {
        Log.d(TAG, "[startProgress] size: ${content.size}")
        return guarded("startProgress") {
            val command = progressCommand(content, complete = false) ?: return@guarded Errors.INVALID_PARAMETER
            manager().startProgress(command)
            Errors.NONE
        }
    }

    @JvmStatic
    fun updateProgress(content: ByteArray): Int {
        Log.d(TAG, "[updateProgress] size: ${content.size}")
        return guarded("updateProgress") {
            val command = progressCommand(content, complete = false) ?: return@guarded Errors.INVALID_PARAMETER
            manager().updateProgress(command)
            Errors.NONE
        }
    }

    @JvmStatic
    fun completeProgress(content: ByteArray): Int {
        Log.d(TAG, "[completeProgress] size: ${content.size}")
        return guarded("completeProgress") {
            val command = progressCommand(content, complete = true) ?: return@guarded Errors.INVALID_PARAMETER
            manager().completeProgress(command)
            Errors.NONE
        }
    }

    @JvmStatic
    fun stopProgress(): Int {
        Log.d(TAG, "[stopProgress]")
        return guarded("stopProgress") {
            manager().stopProgress()
            Errors.NONE
        }
    }

    // A progress notification needs its progress (AP-9).
    private fun progressCommand(content: ByteArray, complete: Boolean): AndroidNotificationCommand? {
        Log.d(TAG, "[progressCommand] size: ${content.size}, complete: $complete")
        val command = command(content)
        val progress = command.content.progress ?: return null
        val corrected = if (complete) {
            command.content.copy(
                ongoing = false, autoCancel = true, onlyAlertOnce = true,
                progress = progress.copy(current = progress.max)
            )
        } else {
            command.content.copy(ongoing = true, autoCancel = false, onlyAlertOnce = true)
        }
        return command.copy(content = corrected)
    }

    // --- queries (OP-33 to OP-36) ---

    @JvmStatic
    fun hasPermission(out: BooleanArray): Int {
        Log.d(TAG, "[hasPermission] out: $out")
        return guarded("hasPermission") {
            out[0] = manager().hasPermission()
            Errors.NONE
        }
    }

    @JvmStatic
    fun areEnabled(out: BooleanArray): Int {
        Log.d(TAG, "[areEnabled] out: $out")
        return guarded("areEnabled") {
            out[0] = manager().areNotificationsEnabled()
            Errors.NONE
        }
    }

    @JvmStatic
    fun isScheduled(id: Int, tag: ByteArray?, out: BooleanArray): Int {
        Log.d(TAG, "[isScheduled] id: $id, out: $out")
        return guarded("isScheduled") {
            out[0] = manager().isScheduled(id, Utf8.decodeOrNull(tag))
            Errors.NONE
        }
    }

    @JvmStatic
    fun canScheduleExactAlarms(out: BooleanArray): Int {
        Log.d(TAG, "[canScheduleExactAlarms] out: $out")
        return guarded("canScheduleExactAlarms") {
            out[0] = manager().canScheduleExactAlarms()
            Errors.NONE
        }
    }

    // --- the settings screen and the permission (OP-37 to OP-39) ---

    /** Opens a settings screen from the foreground Activity, on the main thread (part 1, 5.8). */
    @JvmStatic
    fun openSettings(id: Long, target: Int): Boolean {
        Log.d(TAG, "[openSettings] id: $id, target: $target")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_SETTINGS)) return@post
            Ledger.remove(id)
            val activity = ForegroundActivityTracker.current()
            if (activity == null) {
                nativeSettingsDone(id, NOT_FOREGROUND, OPENED)
                return@post
            }
            try {
                when (manager().openSettings(NotificationSettingsTarget.entries[target], activity)) {
                    NotificationSettingsOpenResult.OPENED -> nativeSettingsDone(id, Errors.NONE, OPENED)
                    NotificationSettingsOpenResult.OPENED_FALLBACK -> nativeSettingsDone(id, Errors.NONE, OPENED_FALLBACK)
                    NotificationSettingsOpenResult.FAILED -> nativeSettingsDone(id, SETTINGS_NOT_OPENED, OPENED)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "[openSettings] failed: ${e.javaClass.name}")
                nativeSettingsDone(id, errorOf(e), OPENED)
            }
        }
    }

    /**
     * Requests the permission on the main thread. Granted already (or not a runtime permission)
     * completes GRANTED in the foreground or not; otherwise the dialog needs the foreground (part
     * 1, 5.8).
     */
    @JvmStatic
    fun requestPermission(id: Long): Boolean {
        Log.d(TAG, "[requestPermission] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_PERMISSION)) return@post
            try {
                val manager = manager()
                when {
                    manager.hasPermission() -> finishPermission(id) { nativePermissionDone(id, Errors.NONE, GRANTED) }
                    !Foreground.isForeground() -> finishPermission(id) { nativePermissionDone(id, NOT_FOREGROUND, DENIED) }
                    else -> permissionIds[id] = manager.requestPermission { result -> onPermission(id, result) }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "[requestPermission] failed: ${e.javaClass.name}")
                finishPermission(id) { nativePermissionDone(id, errorOf(e), DENIED) }
            }
        }
    }

    /** Cancels the Kotlin request of a C request C has moved to CANCEL_REQUESTED (OP-39). */
    @JvmStatic
    fun cancelPermissionRequest(id: Long): Boolean {
        Log.d(TAG, "[cancelPermissionRequest] id: $id")
        return MainPoster.post {
            permissionIds.remove(id)?.let { manager().cancelPermissionRequest(it) }
        }
    }

    private fun finishPermission(id: Long, complete: () -> Unit) {
        Log.d(TAG, "[finishPermission] id: $id")
        permissionIds.remove(id)
        Ledger.remove(id)
        complete()
    }

    private fun onPermission(id: Long, result: PermissionRequestResult) {
        Log.d(TAG, "[onPermission] id: $id, result: $result")
        finishPermission(id) {
            when (result) {
                PermissionRequestResult.Granted -> nativePermissionDone(id, Errors.NONE, GRANTED)
                PermissionRequestResult.Denied -> nativePermissionDone(id, Errors.NONE, DENIED)
                is PermissionRequestResult.Canceled -> nativePermissionDone(
                    id, if (result.reason == CancelReason.REQUESTED) CANCELED else CANCELED_BY_SYSTEM, DENIED
                )
                is PermissionRequestResult.Failed -> nativePermissionDone(
                    id,
                    when (result.reason) {
                        UiUnavailableReason.NOT_INITIALIZED -> Errors.NOT_INITIALIZED
                        UiUnavailableReason.NOT_FOREGROUND -> NOT_FOREGROUND
                        UiUnavailableReason.HOST_START_FAILED -> HOST_START_FAILED
                    },
                    DENIED
                )
            }
        }
    }

    // --- events (OP-40, OP-41) ---

    /** Accepts an interaction listener: inserts it on the main thread and hands it what was kept. */
    @JvmStatic
    fun addInteractionListener(id: Long): Boolean {
        Log.d(TAG, "[addInteractionListener] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_INTERACTION)) return@post
            // The first one: EventHub hands over what it kept before any listener, synchronously.
            if (interactionHub == null) {
                interactionHub = manager().interactions.addListener { event, _ -> onInteraction(event) }
            }
            deliverRetained()
        }
    }

    /** Accepts a shown listener. Shown events are not kept (Kotlin API design 8.4). */
    @JvmStatic
    fun addShownListener(id: Long): Boolean {
        Log.d(TAG, "[addShownListener] id: $id")
        return MainPoster.post {
            if (!Ledger.insertIfActive(id, KIND_SHOWN)) return@post
            if (shownHub == null) shownHub = manager().shown.addListener { event, _ -> onShown(event) }
        }
    }

    private fun onInteraction(event: NotificationInteraction) {
        Log.d(TAG, "[onInteraction] event: $event")
        retained.addLast(event)
        while (retained.size > RETAINED_CAPACITY) retained.removeFirst()
        deliverRetained()
    }

    // Hands the kept interactions, oldest first, to every ACTIVE registration. When a callback
    // removes the last one (and adds another), the rest stay here for the next insertion (AP-21);
    // an event arriving during a callback is appended and handed on by the same loop.
    private fun deliverRetained() {
        Log.d(TAG, "[deliverRetained] retained: ${retained.size}, delivering: $delivering")
        if (delivering) return
        delivering = true
        try {
            while (retained.isNotEmpty()) {
                val ids = activeIds(KIND_INTERACTION)
                if (ids.isEmpty()) return
                val event = retained.removeFirst()
                val kind = when (event.kind) {
                    NotificationInteraction.Kind.BODY_TAP -> EVENT_BODY_TAP
                    NotificationInteraction.Kind.ACTION -> EVENT_ACTION
                    NotificationInteraction.Kind.DISMISS -> EVENT_DISMISS
                }
                val keys = event.data.keys.toList()
                val tag = Utf8.encodeOrNull(event.tag)
                val actionId = Utf8.encodeOrNull(event.actionId)
                val keyBytes = Array(keys.size) { Utf8.encode(keys[it]) }
                val valueBytes = Array(keys.size) { Utf8.encode(event.data.getValue(keys[it])) }
                for (id in ids) {
                    nativeInteraction(id, kind, event.notificationId, tag, actionId, keyBytes, valueBytes)
                }
            }
        } finally {
            delivering = false
        }
    }

    private fun onShown(event: NotificationShown) {
        Log.d(TAG, "[onShown] event: $event")
        val tag = Utf8.encodeOrNull(event.tag)
        val channelId = Utf8.encode(event.channelId)
        for (id in activeIds(KIND_SHOWN)) nativeShown(id, event.notificationId, tag, channelId)
    }

    // The registrations of a kind that C still delivers to: a removed one stays in the ledger
    // until its removal message runs, but is no longer ACTIVE.
    private fun activeIds(kind: Int): List<Long> {
        Log.d(TAG, "[activeIds] kind: $kind")
        return Ledger.idsOf(kind).filter { Ledger.nativeIsActive(it) }
    }

    /** Delivers an interaction to one C registration. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeInteraction(
        id: Long,
        kind: Int,
        notificationId: Int,
        tag: ByteArray?,
        actionId: ByteArray?,
        keys: Array<ByteArray>,
        values: Array<ByteArray>
    )

    /** Delivers a shown event to one C registration. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeShown(id: Long, notificationId: Int, tag: ByteArray?, channelId: ByteArray)

    @JvmStatic
    external fun nativePermissionDone(id: Long, error: Int, result: Int)

    @JvmStatic
    external fun nativeSettingsDone(id: Long, error: Int, result: Int)

    // --- the builders, back from bytes (Encoder.h) ---

    private fun command(bytes: ByteArray): AndroidNotificationCommand {
        Log.d(TAG, "[command] size: ${bytes.size}")
        return Reader(bytes).command(context())
    }

    /** Reads the bytes of Encoder.h in the same order, resolving names as it goes. */
    private class Reader(bytes: ByteArray) {

        private val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        private fun i32(): Int = buffer.int
        private fun i64(): Long = buffer.long
        private fun bool(): Boolean = buffer.get().toInt() != 0
        private fun str(): String {
            val bytes = ByteArray(i32())
            buffer.get(bytes)
            return Utf8.decode(bytes)
        }
        private fun optStr(): String? = if (bool()) str() else null
        private fun optI32(): Int? = if (bool()) i32() else null
        private fun optI64(): Long? = if (bool()) i64() else null
        private fun optBool(): Boolean? = if (bool()) bool() else null

        fun channel(): NotificationChannel {
            val defaults = NotificationChannel()
            val id = str()
            val name = str()
            val importance = i32()
            val description = optStr()
            val showBadge = optBool() ?: defaults.showBadge
            val enableLights = optBool() ?: defaults.enableLights
            val lightColor = optI32()
            val enableVibration = optBool() ?: defaults.enableVibration
            val pattern = if (bool()) List(i32()) { i64() } else null
            val sound = optStr()
            val lockscreen = optI32() ?: defaults.lockscreenVisibility
            val groupId = optStr()
            val groupName = optStr()
            return NotificationChannel(
                id, name, importance, description, showBadge, enableLights, lightColor, enableVibration, pattern,
                sound, lockscreen, groupId, groupName
            )
        }

        fun command(context: Context): AndroidNotificationCommand {
            val resolver = NotificationResourceResolver(context)
            fun drawable(name: String): Int = resolver.resolve(name) ?: throw ResourceMissing(name, "drawable")
            fun typed(name: String, type: String): Int = resolver.resolve(name, type) ?: throw ResourceMissing(name, type)

            val defaults = NotificationContent(0, "", "")
            val id = i32()
            val title = str()
            val message = str()
            val tag = optStr()
            val channel = if (bool()) channel() else defaults.channel
            val smallIcon = optStr()?.let(::drawable) ?: resolver.defaultSmallIcon()
            val largeIcon = optStr()?.let(::drawable)
            val priority = optI32() ?: defaults.priority
            val autoCancel = optBool() ?: defaults.autoCancel
            val ongoing = optBool() ?: defaults.ongoing
            val subText = optStr()
            val showTimestamp = optBool() ?: defaults.showTimestamp
            val timestamp = optI64()
            val sound = optStr()
            val category = optStr()
            val visibility = optI32() ?: defaults.visibility
            val color = optI32()
            val number = optI32()
            val ticker = optStr()
            val group = optStr()
            val groupSummary = optBool() ?: defaults.isGroupSummary
            val groupAlert = optI32() ?: defaults.groupAlertBehavior
            val sortKey = optStr()
            val onlyAlertOnce = optBool() ?: defaults.onlyAlertOnce
            val localOnly = optBool() ?: defaults.localOnly
            val silent = optBool() ?: defaults.silent
            val usesChronometer = optBool() ?: defaults.usesChronometer
            val timeoutAfter = optI64()
            val progress = if (bool()) NotificationProgress(i32(), i32(), bool()) else null

            var viewClicks: List<Pair<Int, String>> = emptyList()
            val style = when (i32()) {
                1 -> NotificationStyle.BigText(str(), optStr(), optStr())
                2 -> NotificationStyle.Inbox(List(i32()) { str() }, optStr(), optStr())
                3 -> {
                    val pictureName = optStr()
                    val pictureUri = optStr()
                    val summary = optStr()
                    val bigTitle = optStr()
                    val styleLargeIcon = optStr()?.let(::drawable)
                    val hide = bool()
                    // Both given: the name wins (part 2, 6.3).
                    NotificationStyle.BigPicture(
                        pictureResId = pictureName?.let(::drawable),
                        pictureUriString = if (pictureName == null) pictureUri else null,
                        summaryText = summary, bigContentTitle = bigTitle,
                        largeIconResId = styleLargeIcon, hideExpandedLargeIcon = hide
                    )
                }
                4 -> {
                    val user = str()
                    val conversation = optStr()
                    val groupConversation = optBool()
                    val messages = List(i32()) { NotificationMessage(str(), i64(), optStr()) }
                    NotificationStyle.Messaging(user, messages, conversation, groupConversation)
                }
                5 -> {
                    val layout = typed(str(), "layout")
                    val bigLayout = optStr()?.let { typed(it, "layout") }
                    viewClicks = List(i32()) { typed(str(), "id") to str() }
                    NotificationStyle.DecoratedCustomView(NotificationCustomViewStyleData(layout, bigLayout))
                }
                else -> NotificationStyle.Default
            }

            val tap = i32()
            val data = LinkedHashMap<String, String>().apply { repeat(i32()) { put(str(), str()) } }
            val dismissEvent = bool()
            val fullScreen = bool()
            val actions = List(i32()) {
                val actionTitle = str()
                val actionId = str()
                val icon = optStr()?.let(::drawable) ?: 0
                val launchApp = bool()
                val replies = bool()
                val semantic = i32()
                val contextual = bool()
                val showsUi = bool()
                AndroidNotificationAction(
                    actionTitle, NotificationEventIntents.action(context, id, tag, actionId, data, launchApp),
                    icon, replies, semantic, contextual, showsUi
                )
            }

            val content = NotificationContent(
                id, title, message, tag, channel, smallIcon, largeIcon, priority, autoCancel, ongoing, subText,
                showTimestamp, timestamp, sound, category, visibility, color, number, ticker, group, groupSummary,
                groupAlert, sortKey, onlyAlertOnce, localOnly, silent, usesChronometer, timeoutAfter, progress, style
            )
            // The events (AP-18): the body tap, the dismissal, the full screen launch; custom view
            // clicks arrive as ACTION events with the same data, as the bridge sent them.
            val options = AndroidNotificationPlatformOptions(
                contentIntent = when (tap) {
                    TAP_OPEN_APP -> NotificationEventIntents.bodyTap(context, id, tag, data, launchApp = true)
                    TAP_EVENT_ONLY -> NotificationEventIntents.bodyTap(context, id, tag, data, launchApp = false)
                    else -> null
                },
                deleteIntent = if (dismissEvent) NotificationEventIntents.dismiss(context, id, tag, data) else null,
                fullScreenIntent = if (fullScreen) NotificationEventIntents.fullScreenLaunch(context, id, tag) else null,
                actions = actions,
                customViewOptions = viewClicks.takeIf { it.isNotEmpty() }?.let { clicks ->
                    AndroidNotificationCustomViewPlatformOptions(clicks.map { (viewId, actionId) ->
                        RemoteViewAction.SetClickIntent(
                            viewId, NotificationEventIntents.action(context, id, tag, actionId, data, launchApp = false)
                        )
                    })
                }
            )
            return AndroidNotificationCommand(content, options)
        }
    }
}
