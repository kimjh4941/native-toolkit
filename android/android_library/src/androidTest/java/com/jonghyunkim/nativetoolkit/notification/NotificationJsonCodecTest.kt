package com.jonghyunkim.nativetoolkit.notification

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.os.Parcel
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCallPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import com.jonghyunkim.nativetoolkit.notification.application.model.RemoteViewAction
import com.jonghyunkim.nativetoolkit.notification.data.repository.JsonNotificationScheduleStore
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationJsonCodec
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduleIdentity
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledAlarmExtras
import com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationEntry
import com.jonghyunkim.nativetoolkit.notification.data.repository.StoredBinarySlots
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCallPerson
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCallType
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCustomViewStyleData
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationMessage
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationProgress
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationStyle
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

// IT-25 of the Kotlin API design: the codec in the Alarm form and the storage form, and the
// version rule of the storage file (8.6).
@RunWith(AndroidJUnit4::class)
class NotificationJsonCodecTest {

    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val directory = File(context.filesDir, "ntk")
    private val file = File(directory, JsonNotificationScheduleStore.FILE_NAME)

    @Before
    fun setUp() {
        directory.listFiles()?.filter { it.name.startsWith("notification_schedules") }?.forEach { it.delete() }
    }

    @After
    fun tearDown() = setUp()

    private fun bitmap(color: Int) = Bitmap.createBitmap(3, 2, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }

    // Only extras that toUri keeps, so that both forms give back the same command.
    private fun userIntent(n: Int) = Intent("user.ACTION_$n")
        .setClassName(context, "com.example.Target$n")
        .addCategory("user.CATEGORY")
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        .putExtra("s", "v$n").putExtra("i", n).putExtra("b", true).putExtra("l", 7L)

    private fun request(n: Int, type: AndroidPendingIntentType = AndroidPendingIntentType.BROADCAST) =
        AndroidPendingIntentRequest(intent = userIntent(n), requestCode = n, type = type, flags = 0x08000000, mutable = n % 2 == 0)

    private fun content(style: NotificationStyle) = NotificationContent(
        id = 42, title = "Title", message = "Message", tag = "tag/1",
        channel = NotificationChannel(
            id = "c", name = "C", importance = 4, description = "d", showBadge = false, enableLights = false,
            lightColor = Color.RED, enableVibration = false, vibrationPattern = listOf(0L, 100L, 50L),
            soundUri = "content://sound", lockscreenVisibility = -1, groupId = "g", groupName = "G"
        ),
        smallIconResId = 11, largeIconResId = 12, priority = 2, autoCancel = false, ongoing = true,
        subText = "sub", showTimestamp = false, timestampMillis = 123L, soundUri = "content://s",
        category = "msg", visibility = 0, color = Color.BLUE, number = 3, ticker = "tick",
        groupKey = "gk", isGroupSummary = true, groupAlertBehavior = 1, sortKey = "sk",
        onlyAlertOnce = true, localOnly = true, silent = true, usesChronometer = true,
        timeoutAfterMillis = 9_000L, progress = NotificationProgress(100, 40, indeterminate = true),
        style = style
    )

    private val styles = listOf(
        NotificationStyle.Default,
        NotificationStyle.BigText("big", "sum", "bct"),
        NotificationStyle.Inbox(listOf("a", "b"), "sum", "bct"),
        NotificationStyle.BigPicture(13, "content://p", "sum", "bct", 14, hideExpandedLargeIcon = true),
        NotificationStyle.Messaging("me", listOf(NotificationMessage("hi", 5L, "you"), NotificationMessage("yo", 6L)), "conv", true),
        NotificationStyle.Messaging("me", listOf(NotificationMessage("hi", 5L)), null, null),
        NotificationStyle.Media(listOf(0, 1)),
        NotificationStyle.DecoratedCustomView(NotificationCustomViewStyleData(15, 16)),
        NotificationStyle.DecoratedMediaCustomView(NotificationCustomViewStyleData(17), listOf(2)),
        NotificationStyle.Call(NotificationCallType.SCREENING, NotificationCallPerson("caller", 18), isVideo = true, verificationText = "v")
    )

    private fun fullCommand(style: NotificationStyle) = AndroidNotificationCommand(
        content = content(style),
        platformOptions = AndroidNotificationPlatformOptions(
            largeIconBitmap = bitmap(Color.GREEN),
            contentIntent = request(1, AndroidPendingIntentType.ACTIVITY),
            deleteIntent = request(2),
            fullScreenIntent = request(3, AndroidPendingIntentType.ACTIVITY),
            actions = listOf(
                AndroidNotificationAction("A", request(4), iconResId = 19, allowGeneratedReplies = true, semanticAction = 2, contextual = true, showsUserInterface = false),
                AndroidNotificationAction("B", request(5, AndroidPendingIntentType.SERVICE))
            ),
            callStyleOptions = AndroidNotificationCallPlatformOptions(request(6), request(7), request(8, AndroidPendingIntentType.FOREGROUND_SERVICE)),
            customViewOptions = AndroidNotificationCustomViewPlatformOptions(
                listOf(RemoteViewAction.SetText(1, "t"), RemoteViewAction.SetImage(2, 20), RemoteViewAction.SetClickIntent(3, request(9)))
            )
        )
    )

    // --- comparison: Intents by filterEquals and extras, Bitmaps by sameAs ---

    private fun assertIntentEquals(expected: Intent, actual: Intent) {
        assertTrue("$expected vs $actual", expected.filterEquals(actual))
        assertEquals(expected.flags, actual.flags)
        val e = expected.extras ?: Bundle()
        val a = actual.extras ?: Bundle()
        assertEquals(e.keySet(), a.keySet())
        @Suppress("DEPRECATION")
        e.keySet().forEach { assertEquals(it, e.get(it), a.get(it)) }
    }

    private fun assertRequestEquals(expected: AndroidPendingIntentRequest?, actual: AndroidPendingIntentRequest?) {
        if (expected == null) {
            assertNull(actual)
            return
        }
        assertIntentEquals(expected.intent, actual!!.intent)
        assertEquals(expected.copy(intent = Intent()).let { listOf(it.requestCode, it.type, it.flags, it.mutable) }, listOf(actual.requestCode, actual.type, actual.flags, actual.mutable))
    }

    private fun assertCommandEquals(expected: AndroidNotificationCommand, actual: AndroidNotificationCommand) {
        assertEquals(expected.content, actual.content)
        val e = expected.platformOptions
        val a = actual.platformOptions
        if (e.largeIconBitmap == null) assertNull(a.largeIconBitmap) else assertTrue(e.largeIconBitmap!!.sameAs(a.largeIconBitmap))
        assertRequestEquals(e.contentIntent, a.contentIntent)
        assertRequestEquals(e.deleteIntent, a.deleteIntent)
        assertRequestEquals(e.fullScreenIntent, a.fullScreenIntent)
        assertEquals(e.actions.size, a.actions.size)
        e.actions.zip(a.actions).forEach { (x, y) ->
            assertEquals(x.copy(pendingIntent = y.pendingIntent), y)
            assertRequestEquals(x.pendingIntent, y.pendingIntent)
        }
        assertEquals(e.callStyleOptions == null, a.callStyleOptions == null)
        e.callStyleOptions?.let { x ->
            val y = a.callStyleOptions!!
            assertRequestEquals(x.answerIntent, y.answerIntent)
            assertRequestEquals(x.declineIntent, y.declineIntent)
            assertRequestEquals(x.hangUpIntent, y.hangUpIntent)
        }
        assertEquals(e.customViewOptions == null, a.customViewOptions == null)
        e.customViewOptions?.viewActions?.zip(a.customViewOptions!!.viewActions)?.forEach { (x, y) ->
            if (x is RemoteViewAction.SetClickIntent) {
                assertEquals(x.viewId, (y as RemoteViewAction.SetClickIntent).viewId)
                assertRequestEquals(x.pendingIntent, y.pendingIntent)
            } else {
                assertEquals(x, y)
            }
        }
    }

    // The Alarm form, marshalled through a Parcel as the Alarm delivers it.
    private fun throughAlarm(command: AndroidNotificationCommand): AndroidNotificationCommand {
        val extras = ScheduledAlarmExtras.intent(context, command, 1L).extras!!
        val parcel = Parcel.obtain()
        try {
            extras.writeToParcel(parcel, 0)
            val bytes = parcel.marshall()
            val back = Parcel.obtain()
            try {
                back.unmarshall(bytes, 0, bytes.size)
                back.setDataPosition(0)
                return ScheduledAlarmExtras.commandOf(Intent().putExtras(Bundle.CREATOR.createFromParcel(back)))
            } finally {
                back.recycle()
            }
        } finally {
            parcel.recycle()
        }
    }

    // The storage form, through the file.
    private fun throughStore(command: AndroidNotificationCommand): AndroidNotificationCommand {
        val store = JsonNotificationScheduleStore(context)
        store.clear()
        store.put(ScheduledNotificationEntry(command, NotificationSchedule(triggerAtMillis = 1_000L), generation = 3L))
        return JsonNotificationScheduleStore(context).loadAll().single().command
    }

    @Test
    fun everyFieldAndStyle_roundTripsInTheAlarmForm() {
        styles.forEach { style -> fullCommand(style).let { assertCommandEquals(it, throughAlarm(it)) } }
    }

    @Test
    fun everyFieldAndStyle_roundTripsInTheStorageForm() {
        styles.forEach { style -> fullCommand(style).let { assertCommandEquals(it, throughStore(it)) } }
    }

    @Test
    fun aMinimalCommand_roundTripsWithDefaults_inBothForms() {
        val command = AndroidNotificationCommand(NotificationContent(id = 1, title = "t", message = "m"))
        assertCommandEquals(command, throughAlarm(command))
        assertCommandEquals(command, throughStore(command))
    }

    @Test
    fun severalBitmapsAndIntents_keepTheirOrder() {
        val command = AndroidNotificationCommand(
            NotificationContent(id = 2, title = "t", message = "m"),
            AndroidNotificationPlatformOptions(
                largeIconBitmap = bitmap(Color.YELLOW),
                actions = (1..4).map { AndroidNotificationAction("a$it", request(it)) }
            )
        )
        assertCommandEquals(command, throughAlarm(command))
        assertCommandEquals(command, throughStore(command))
    }

    @Test
    fun missingFields_takeTheModelDefaults() {
        val json = JSONObject().put("content", JSONObject().put("id", 3).put("title", "t").put("message", "m"))
        val decoded = NotificationJsonCodec.decodeCommand(json, StoredBinarySlots())
        assertEquals(AndroidNotificationCommand(NotificationContent(id = 3, title = "t", message = "m")).content, decoded.content)
        assertEquals(AndroidNotificationPlatformOptions(), decoded.platformOptions)
        assertEquals(
            NotificationSchedule(triggerAtMillis = 5L),
            NotificationJsonCodec.decodeSchedule(JSONObject().put("triggerAtMillis", 5L))
        )
    }

    @Test
    fun aCommandOfAnotherVersion_isNotDecoded() {
        // The Alarm form has no file to move aside: a later version's command is refused, and the
        // receiver, which catches the failure, shows nothing (design 8.6, review of stage 1b).
        val command = AndroidNotificationCommand(NotificationContent(id = 5, title = "t", message = "m"))
        val json = NotificationJsonCodec.encodeCommand(command, StoredBinarySlots())
        assertEquals(NotificationJsonCodec.VERSION, json.getInt("v"))
        for (other in listOf<Any>(NotificationJsonCodec.VERSION + 1, JSONObject(), "x", 1.5)) {
            json.put("v", other)
            assertTrue("v=$other", runCatching { NotificationJsonCodec.decodeCommand(json, StoredBinarySlots()) }.exceptionOrNull() is org.json.JSONException)
        }
        json.remove("v")
        assertEquals(command.content, NotificationJsonCodec.decodeCommand(json, StoredBinarySlots()).content)
    }

    @Test
    fun unknownFields_areIgnored() {
        val command = AndroidNotificationCommand(NotificationContent(id = 4, title = "t", message = "m", style = NotificationStyle.BigText("b")))
        val json = NotificationJsonCodec.encodeCommand(command, StoredBinarySlots())
        json.put("future", 1)
        json.getJSONObject("content").put("futureField", JSONArray(listOf(1, 2)))
        json.getJSONObject("content").getJSONObject("style").put("futureStyleField", "x")
        assertEquals(command.content, NotificationJsonCodec.decodeCommand(json, StoredBinarySlots()).content)
    }

    @Test
    fun aVersion1FileWithAnAddedField_isRead() {
        throughStore(AndroidNotificationCommand(NotificationContent(id = 5, title = "t", message = "m")))
        val root = JSONObject(file.readText())
        root.put("addedRootField", true)
        root.getJSONArray("entries").getJSONObject(0).put("addedEntryField", "x")
        file.writeText(root.toString())
        assertEquals(5, JsonNotificationScheduleStore(context).loadAll().single().command.content.id)
    }

    @Test
    fun anUnknownVersionFile_isKeptAside_andTreatedAsEmpty() {
        directory.mkdirs()
        file.writeText(JSONObject().put("v", 2).put("entries", JSONArray()).toString())
        val store = JsonNotificationScheduleStore(context)
        assertTrue(store.loadAll().isEmpty())
        assertTrue(File(directory, "notification_schedules.v2.json").exists())
        assertFalse(file.exists())
    }

    @Test
    fun aCorruptFile_isMovedAside_andTreatedAsEmpty() {
        directory.mkdirs()
        file.writeText("{not json")
        assertTrue(JsonNotificationScheduleStore(context).loadAll().isEmpty())
        assertTrue(File(directory, "notification_schedules.corrupt.json").exists())
    }

    @Test
    fun anUnreadableEntry_isSkipped_andKeptWhenTheFileIsRewritten() {
        throughStore(AndroidNotificationCommand(NotificationContent(id = 6, title = "t", message = "m")))
        val root = JSONObject(file.readText())
        val broken = JSONObject().put("id", 99).put("command", JSONObject().put("content", JSONObject()))
        root.getJSONArray("entries").put(broken)
        file.writeText(root.toString())

        val store = JsonNotificationScheduleStore(context)
        assertEquals(listOf(6), store.loadAll().map { it.command.content.id })
        store.put(ScheduledNotificationEntry(AndroidNotificationCommand(NotificationContent(id = 7, title = "t", message = "m")), NotificationSchedule(1_000L)))
        val entries = JSONObject(file.readText()).getJSONArray("entries")
        assertEquals(3, entries.length())
        assertTrue((0 until entries.length()).any { entries.getJSONObject(it).optInt("id") == 99 })
        store.clear()
        assertEquals(0, JSONObject(file.readText()).getJSONArray("entries").length())
    }

    @Test
    fun entryFields_roundTrip() {
        val command = AndroidNotificationCommand(NotificationContent(id = 8, title = "t", message = "m", tag = "x"))
        val schedule = NotificationSchedule(triggerAtMillis = 77L, exact = false, allowWhileIdle = false, persistAcrossBoot = true, alarmType = 1)
        val store = JsonNotificationScheduleStore(context)
        store.put(ScheduledNotificationEntry(command, schedule, generation = 123L, lossy = true, installId = "i", bootCount = 4))
        val entry = JsonNotificationScheduleStore(context).get(8, "x")!!
        assertEquals(ScheduledNotificationEntry(command, schedule, 123L, true, "i", 4), entry)
        assertEquals(ScheduleIdentity.installId(context), JsonNotificationScheduleStore.newEntry(context, command, schedule, 1L).installId)
    }
}
