package android.library.clipboard.data

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.library.clipboard.data.repository.ClipboardRepositoryImpl
import android.library.clipboard.domain.model.ClipContent
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for [ClipboardRepositoryImpl] against the real system ClipboardManager.
 *
 * Covers copy/read round trips, clear, empty-clipboard normal case, and the sensitive-content
 * flag (API 33+). Clipboard change observation is verified separately in the unity plugin module
 * (ClipboardChangeMonitor), since RepositoryImpl does not own the system listener.
 */
@RunWith(AndroidJUnit4::class)
class ClipboardRepositoryImplTest {

    private val appContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun copyPlainText_thenRead_roundTrips() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "hello instrumented"))

        val result = repository.read()

        assertEquals("hello instrumented", result?.items?.firstOrNull()?.text)
    }

    @Test
    fun copyHtmlText_thenRead_roundTrips() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.HtmlText(plainText = "hi", htmlText = "<b>hi</b>"))

        val result = repository.read()

        assertEquals("<b>hi</b>", result?.items?.firstOrNull()?.htmlText)
    }

    @Test
    fun copyUri_thenRead_roundTrips() {
        val repository = ClipboardRepositoryImpl(appContext)
        val uri = "content://${appContext.packageName}.native_toolkit.share.fileprovider/test"
        repository.copy(ClipContent.UriContent(uri = uri))

        val result = repository.read()

        assertEquals(uri, result?.items?.firstOrNull()?.uri)
    }

    @Test
    fun copyMultipleText_thenRead_returnsAllItems() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.MultipleText(texts = listOf("a", "b", "c")))

        val result = repository.read()

        assertEquals(listOf("a", "b", "c"), result?.items?.map { it.text })
    }

    @Test
    fun clear_thenHasClip_isFalse() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "to be cleared"))

        repository.clear()

        assertFalse(repository.hasClip())
    }

    @Test
    fun read_afterClear_returnsNull() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "to be cleared"))
        repository.clear()

        assertNull(repository.read())
    }

    @Test
    fun getDescription_afterClear_returnsNull() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "to be cleared"))
        repository.clear()

        assertNull(repository.getDescription())
    }

    @Test
    fun copyPlainText_thenHasClip_isTrue() {
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "present"))

        assertTrue(repository.hasClip())
    }

    @Test
    fun copySensitiveContent_onApi33Plus_setsExtraIsSensitive() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val repository = ClipboardRepositoryImpl(appContext)
        repository.copy(ClipContent.PlainText(text = "secret", isSensitive = true))

        val clipboardManager = ContextCompat.getSystemService(appContext, ClipboardManager::class.java)!!
        val extras = clipboardManager.primaryClipDescription?.extras

        assertTrue(extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true)
    }
}
