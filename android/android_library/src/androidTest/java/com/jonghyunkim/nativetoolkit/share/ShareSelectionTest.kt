package com.jonghyunkim.nativetoolkit.share

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Parcel
import android.service.chooser.ChooserAction
import android.service.chooser.ChooserResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.common.runtime.ProcessNonce
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareCallbackCoordinator
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareRepositoryImpl
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareResultIntents
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareChooserAction
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import com.jonghyunkim.nativetoolkit.share.domain.model.SharePreviewOptions
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection
import com.jonghyunkim.nativetoolkit.share.presentation.ShareChooserActionReceiver
import com.jonghyunkim.nativetoolkit.share.presentation.ShareEvents
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-15 and IT-16 of the Kotlin API design (8.9): the share wait and typed chooser actions, plus
// the share part of IT-20 (the receiver's IntentFilter). The Sharesheet is not shown: a recording
// Context keeps the chooser Intent, and the test sends what the system would send. The chooser
// action tests also stand for the bridge's chooser action tests (T-22; the mapping is in the
// stage 1b implementation result).
@RunWith(AndroidJUnit4::class)
class ShareSelectionTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val recorder = RecordingContext(context)
    private val repository = ShareRepositoryImpl(recorder)
    private val coordinator = ShareCallbackCoordinator.get(context)
    private val selections = LinkedBlockingQueue<ShareSelection>()
    private val actions = LinkedBlockingQueue<String>()
    private val registrations = mutableListOf<EventHub.Registration>()
    private val content = ShareContent(text = "IT-15")

    private class RecordingContext(base: Context) : ContextWrapper(base) {
        val started = mutableListOf<Intent>()
        override fun getApplicationContext(): Context = baseContext.applicationContext
        override fun startActivity(intent: Intent) {
            started += intent
        }
    }

    @Before
    fun setUp() {
        instrumentation.runOnMainSync {
            registrations += ShareEvents.selections.addListener { event, _ -> selections.add(event) }
            registrations += ShareEvents.chooserActions.addListener { id, _ -> actions.add(id) }
        }
    }

    @After
    fun tearDown() {
        coordinator.cancel()
        instrumentation.runOnMainSync { registrations.forEach { it.remove() } }
    }

    // What the Sharesheet reports for a pick (API 35+ adds a ChooserResult; older ones only the component).
    private fun pickResult(packageName: String): Intent {
        val component = ComponentName(packageName, "$packageName.ShareActivity")
        val fillIn = Intent().putExtra(Intent.EXTRA_CHOSEN_COMPONENT, component)
        if (Build.VERSION.SDK_INT >= 35) fillIn.putExtra("android.intent.extra.CHOOSER_RESULT", chooserResult(ChooserResult.CHOOSER_RESULT_SELECTED_COMPONENT, component))
        return fillIn
    }

    private fun copyResult(): Intent {
        val fillIn = Intent()
        if (Build.VERSION.SDK_INT >= 35) fillIn.putExtra("android.intent.extra.CHOOSER_RESULT", chooserResult(ChooserResult.CHOOSER_RESULT_COPY, null))
        return fillIn
    }

    // ChooserResult has no public constructor; build it from its Parcel form.
    private fun chooserResult(type: Int, component: ComponentName?): ChooserResult {
        val parcel = Parcel.obtain()
        try {
            parcel.writeInt(type)
            ComponentName.writeToParcel(component, parcel)
            parcel.writeBoolean(false)
            parcel.setDataPosition(0)
            return ChooserResult.CREATOR.createFromParcel(parcel).also {
                check(it.type == type && it.selectedComponent == component) { "unexpected ChooserResult layout: $it" }
            }
        } finally {
            parcel.recycle()
        }
    }

    // The result PendingIntent the Sharesheet holds for the request with [token].
    private fun sendResult(token: Long, fillIn: Intent, nonce: Long = coordinator.nonce) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            ShareResultIntents.intent(context, nonce, token),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE
        )
        if (pendingIntent != null) {
            pendingIntent.send(context, 0, fillIn)
        } else {
            // A request of another process: no PendingIntent of this process has that URI.
            context.sendBroadcast(ShareResultIntents.intent(context, nonce, token).putExtras(fillIn))
        }
    }

    private fun waitMain() {
        Thread.sleep(500)
        instrumentation.waitForIdleSync()
    }

    // --- IT-15: the share wait ---

    @Test
    fun shareForSelection_deliversThePickWithItsToken() {
        val token = repository.shareForSelection(content, SharePreviewOptions())
        assertEquals(1, recorder.started.size)
        sendResult(token, pickResult("com.example.target"))
        assertEquals(ShareSelection(token, "com.example.target"), selections.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun aPickInTheEarlierSharesheet_isNotDelivered() {
        val first = repository.shareForSelection(content, SharePreviewOptions())
        val second = repository.shareForSelection(content, SharePreviewOptions())
        sendResult(first, pickResult("com.example.first"))
        waitMain()
        assertNull(selections.poll())
        sendResult(second, pickResult("com.example.second"))
        assertEquals(ShareSelection(second, "com.example.second"), selections.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun cancelShareSelection_dropsThePick_butCancelingAnOlderTokenKeepsTheNewWait() {
        val first = repository.shareForSelection(content, SharePreviewOptions())
        repository.cancelShareSelection(first)
        sendResult(first, pickResult("com.example.target"))
        waitMain()
        assertNull(selections.poll())

        val older = repository.shareForSelection(content, SharePreviewOptions())
        val newer = repository.shareForSelection(content, SharePreviewOptions())
        repository.cancelShareSelection(older)
        sendResult(newer, pickResult("com.example.target"))
        assertEquals(ShareSelection(newer, "com.example.target"), selections.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun aPickOfAnEarlierProcess_isNotDelivered() {
        val token = repository.shareForSelection(content, SharePreviewOptions())
        sendResult(token, pickResult("com.example.target"), nonce = coordinator.nonce + 1)
        waitMain()
        assertNull(selections.poll())
    }

    @Test
    fun aNonSelectionResult_sendsNoSelectionEvent() {
        val token = repository.shareForSelection(content, SharePreviewOptions())
        sendResult(token, copyResult())
        waitMain()
        assertNull(selections.poll())
    }

    @Test
    fun shareWithCallback_pickCallsOnResultAndOnFinishedOnce_copyCallsOnlyOnFinished() {
        val results = LinkedBlockingQueue<String?>()
        val finished = java.util.concurrent.atomic.AtomicInteger(0)
        repository.shareWithCallback(content, SharePreviewOptions(), { results.add(it) }, { finished.incrementAndGet() })
        val token = latestToken()
        sendResult(token, pickResult("com.example.target"))
        assertEquals("com.example.target", results.poll(5, TimeUnit.SECONDS))
        sendResult(token, pickResult("com.example.again"))
        waitMain()
        assertNull(results.poll())
        assertEquals(1, finished.get())

        repository.shareWithCallback(content, SharePreviewOptions(), { results.add(it) }, { finished.incrementAndGet() })
        sendResult(latestToken(), copyResult())
        waitMain()
        assertNull(results.poll())
        assertEquals(2, finished.get())
    }

    @Test
    fun shareWithCallback_aPickInTheEarlierSharesheet_doesNotReachTheNewCallback() {
        val results = LinkedBlockingQueue<String>()
        repository.shareWithCallback(content, SharePreviewOptions(), { results.add("first:$it") }, {})
        val first = latestToken()
        repository.shareWithCallback(content, SharePreviewOptions(), { results.add("second:$it") }, {})
        val second = latestToken()
        sendResult(first, pickResult("com.example.old"))
        waitMain()
        assertNull(results.poll())
        sendResult(second, pickResult("com.example.new"))
        assertEquals("second:com.example.new", results.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun launchFailure_throws_andKeepsNoWait() {
        val failing = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = context.applicationContext
            override fun startActivity(intent: Intent) = throw android.content.ActivityNotFoundException()
        }
        val previous = repository.shareForSelection(content, SharePreviewOptions())
        val error = runCatching { ShareRepositoryImpl(failing).shareForSelection(content, SharePreviewOptions()) }.exceptionOrNull()
        assertEquals(ShareDomainError.NoShareTarget, error)
        // The failed request replaced the previous wait and then removed itself.
        sendResult(previous, pickResult("com.example.target"))
        waitMain()
        assertNull(selections.poll())
    }

    @Test
    fun resultFilter_matchesOnlyTheResultIntentsOfThisPackage() {
        val filter = ShareResultIntents.filter(context)
        val good = ShareResultIntents.intent(context, 1L, 2L)
        assertTrue(filter.match(context.contentResolver, good, false, "test") >= 0)
        val otherAuthority = Intent(ShareResultIntents.ACTION_RESULT, android.net.Uri.parse("ntk-share-result://other.app/1/2"))
        assertTrue(filter.match(context.contentResolver, otherAuthority, false, "test") < 0)
        val otherScheme = Intent(ShareResultIntents.ACTION_RESULT, android.net.Uri.parse("other://${context.packageName}/1/2"))
        assertTrue(filter.match(context.contentResolver, otherScheme, false, "test") < 0)
        val otherAction = Intent("other.ACTION", good.data)
        assertTrue(filter.match(context.contentResolver, otherAction, false, "test") < 0)
        assertEquals(context.packageName, good.`package`)
    }

    private fun latestToken(): Long = coordinator.currentToken() ?: throw AssertionError("no wait")

    // --- IT-16: typed chooser actions ---

    private fun png(): ByteArray {
        val out = ByteArrayOutputStream()
        Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun lastChooserActions(): List<ChooserAction> {
        val chooser = recorder.started.last()
        @Suppress("DEPRECATION")
        val array = chooser.getParcelableArrayExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS) ?: return emptyList()
        return array.map { it as ChooserAction }
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun aTypedActionArrivesWithItsId() {
        repository.shareTextWithActions(content, listOf(ShareChooserAction("save", "Save", png()), ShareChooserAction("open", "Open", png())), SharePreviewOptions())
        val shown = lastChooserActions()
        assertEquals(listOf("Save", "Open"), shown.map { it.label.toString() })
        // Every action has its own PendingIntent, although they share request code 0.
        shown[1].action.send()
        assertEquals("open", actions.poll(5, TimeUnit.SECONDS))
        shown[0].action.send()
        assertEquals("save", actions.poll(5, TimeUnit.SECONDS))
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun anIdThatLooksLikeTheSendAction_isAnOrdinaryId() {
        // The bridge dropped this id, because the id was the Intent action; here it is in the data URI.
        repository.shareTextWithActions(content, listOf(ShareChooserAction(Intent.ACTION_SEND, "Send", png())), SharePreviewOptions())
        lastChooserActions().single().action.send()
        assertEquals(Intent.ACTION_SEND, actions.poll(5, TimeUnit.SECONDS))
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun aLaunchFailure_throws_andTheActionsOfTheEarlierShareStopWorking() {
        repository.shareTextWithActions(content, listOf(ShareChooserAction("keep", "Keep", png())), SharePreviewOptions())
        val keep = lastChooserActions().single()
        val failing = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = context.applicationContext
            override fun startActivity(intent: Intent) = throw android.content.ActivityNotFoundException()
        }
        val error = runCatching {
            ShareRepositoryImpl(failing).shareTextWithActions(content, listOf(ShareChooserAction("new", "New", png())), SharePreviewOptions())
        }.exceptionOrNull()
        assertEquals(ShareDomainError.NoShareTarget, error)
        // The generation changes before the launch, as the bridge removed its receiver first.
        keep.action.send()
        waitMain()
        assertNull(actions.poll())
    }

    @Test
    fun malformedActionIntents_andActionsOfAnEarlierProcess_areDropped() {
        val generation = ShareChooserActionReceiver.nextGeneration(context)
        val base = "${ShareChooserActionReceiver.SCHEME_ACTION}://${context.packageName}"
        fun broadcast(uri: String) = context.sendBroadcast(
            Intent(ShareChooserActionReceiver.ACTION_CHOOSER_ACTION, android.net.Uri.parse(uri)).setPackage(context.packageName)
        )
        broadcast("$base/${ProcessNonce.value}/$generation")
        broadcast("$base/${ProcessNonce.value}/x/id")
        broadcast("$base/x/$generation/id")
        broadcast("$base/${ProcessNonce.value + 1}/$generation/id")
        waitMain()
        assertNull(actions.poll())
        context.sendBroadcast(ShareChooserActionReceiver.intent(context, generation, "x"))
        assertEquals("x", actions.poll(5, TimeUnit.SECONDS))
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun anActionWithoutAListener_isNotKeptForALaterListener() {
        repository.shareTextWithActions(content, listOf(ShareChooserAction("late", "Late", png())), SharePreviewOptions())
        val late = lastChooserActions().single()
        instrumentation.runOnMainSync { registrations.forEach { it.remove() } }
        late.action.send()
        waitMain()
        instrumentation.runOnMainSync {
            registrations += ShareEvents.chooserActions.addListener { id, _ -> actions.add(id) }
        }
        waitMain()
        assertNull(actions.poll())
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun actionsOfAnEarlierShare_doNotArrive_evenAfterAShareWithoutActions() {
        repository.shareTextWithActions(content, listOf(ShareChooserAction("old", "Old", png())), SharePreviewOptions())
        val old = lastChooserActions().single()
        repository.shareTextWithActions(content, listOf(ShareChooserAction("new", "New", png())), SharePreviewOptions())
        val new = lastChooserActions().single()
        old.action.send()
        waitMain()
        assertNull(actions.poll())
        new.action.send()
        assertEquals("new", actions.poll(5, TimeUnit.SECONDS))

        repository.shareTextWithActions(content, emptyList(), SharePreviewOptions())
        assertTrue(lastChooserActions().isEmpty())
        new.action.send()
        waitMain()
        assertNull(actions.poll())
    }

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun aRejectedShare_keepsThePreviousActionsWorking() {
        repository.shareTextWithActions(content, listOf(ShareChooserAction("keep", "Keep", png())), SharePreviewOptions())
        val keep = lastChooserActions().single()
        val started = recorder.started.size
        val badIcon = runCatching {
            repository.shareTextWithActions(content, listOf(ShareChooserAction("bad", "Bad", byteArrayOf(1, 2, 3))), SharePreviewOptions())
        }.exceptionOrNull()
        assertEquals(ShareDomainError.InvalidChooserAction("bad"), badIcon)
        val duplicate = runCatching {
            repository.shareTextWithActions(content, listOf(ShareChooserAction("d", "A", png()), ShareChooserAction("d", "B", png())), SharePreviewOptions())
        }.exceptionOrNull()
        assertEquals(ShareDomainError.InvalidChooserAction("d"), duplicate)
        assertEquals(started, recorder.started.size)
        keep.action.send()
        assertEquals("keep", actions.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun theTextIntentIsTheSameAsShareText() {
        repository.shareTextWithActions(ShareContent(text = "body", title = "T", subject = "S"), emptyList(), SharePreviewOptions(title = "P"))
        val target = recorder.started.last().let {
            @Suppress("DEPRECATION")
            it.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        }
        assertNotNull(target)
        assertEquals(Intent.ACTION_SEND, target!!.action)
        assertEquals("body", target.getStringExtra(Intent.EXTRA_TEXT))
        assertEquals("S", target.getStringExtra(Intent.EXTRA_SUBJECT))
        assertEquals("P", target.getStringExtra(Intent.EXTRA_TITLE))
        assertFalse(recorder.started.last().hasExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS) && Build.VERSION.SDK_INT < 34)
    }
}
