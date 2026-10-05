package com.jonghyunkim.nativetoolkit.share

import android.content.BroadcastReceiver
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.service.chooser.ChooserAction
import android.util.Base64
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareUseCases
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareRepositoryImpl
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// IT-23 of the Kotlin API design (share part): the deprecated JSON form of ShareUseCases.shareText
// behaves as in 1.x, as the stage 0c UI tests used it (ShareUiTest before the sample moved to
// typed actions): each entry with a label and a readable icon becomes a chooser action that
// broadcasts its intentAction to this package; other entries are skipped; JSON that does not parse
// opens the Sharesheet without actions. The Sharesheet is not shown: a recording Context keeps the
// chooser Intent.
@RunWith(AndroidJUnit4::class)
@Suppress("DEPRECATION")
class ExistingShareApiTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val recorder = RecordingContext(context)
    private val useCases = ShareUseCases(ShareRepositoryImpl(recorder))
    private val received = LinkedBlockingQueue<String>()
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            received.add(intent.action ?: "")
        }
    }

    private class RecordingContext(base: Context) : ContextWrapper(base) {
        val started = mutableListOf<Intent>()
        override fun getApplicationContext(): Context = baseContext.applicationContext
        override fun startActivity(intent: Intent) {
            started += intent
        }
    }

    @After
    fun tearDown() {
        runCatching { context.unregisterReceiver(receiver) }
    }

    private fun iconBase64(): String {
        val out = ByteArrayOutputStream()
        Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    private fun entry(label: String, icon: String, intentAction: String? = null) = JSONObject()
        .put("label", label).put("iconBase64", icon).apply { if (intentAction != null) put("intentAction", intentAction) }

    private fun lastActions(): List<ChooserAction> =
        recorder.started.last().getParcelableArrayExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS)?.map { it as ChooserAction } ?: emptyList()

    @Test
    @SdkSuppress(minSdkVersion = 34)
    fun jsonActions_becomeChooserActions_thatBroadcastTheirIntentAction() {
        val first = "${context.packageName}.it23.FIRST"
        val second = "${context.packageName}.it23.SECOND"
        ContextCompat.registerReceiver(
            context, receiver, IntentFilter().apply { addAction(first); addAction(second) }, ContextCompat.RECEIVER_NOT_EXPORTED
        )
        val json = JSONArray()
            .put(entry("First", iconBase64(), first))
            .put(entry("", iconBase64(), "skipped.blank.label"))
            .put(entry("Unreadable", "AAAA", "skipped.bad.icon"))
            .put(entry("Second", iconBase64(), second))
        useCases.shareText(ShareContent(text = "IT-23"), json.toString())
        val actions = lastActions()
        assertEquals(listOf("First", "Second"), actions.map { it.label.toString() })
        actions[1].action.send()
        assertEquals(second, received.poll(5, TimeUnit.SECONDS))
        actions[0].action.send()
        assertEquals(first, received.poll(5, TimeUnit.SECONDS))
    }

    @Test
    fun emptyOrBrokenJson_opensTheSharesheetWithoutActions() {
        useCases.shareText(ShareContent(text = "IT-23"), "[]")
        assertFalse(recorder.started.last().hasExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS))
        useCases.shareText(ShareContent(text = "IT-23"), "{not json")
        assertEquals(2, recorder.started.size)
        assertFalse(recorder.started.last().hasExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS))
        val target = recorder.started.last().getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        assertEquals(Intent.ACTION_SEND, target?.action)
        assertEquals("IT-23", target?.getStringExtra(Intent.EXTRA_TEXT))
        assertTrue(recorder.started.last().action == Intent.ACTION_CHOOSER)
    }
}
