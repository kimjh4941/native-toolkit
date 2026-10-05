package com.jonghyunkim.nativetoolkit.capitest

import android.content.Context
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareContent
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * What the Share cases need around the C ABI (through TestSupport.h): an image as bytes, files to
 * share, the Direct Share shortcuts, and a share opened from Kotlin directly.
 */
object ShareInspector {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    /** A small PNG: a readable icon. */
    @JvmStatic
    fun pngBytes(): ByteArray {
        val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }

    /** Writes [name] in the cache directory (inside the FileProvider paths) and returns its path. */
    @JvmStatic
    fun makeFile(name: String, image: Boolean): String {
        val file = File(context.cacheDir, name)
        if (image) file.writeBytes(pngBytes()) else file.writeText("ntk share test")
        return file.absolutePath
    }

    /** The IDs of the dynamic shortcuts (the Direct Share targets), sorted and joined by "|". */
    @JvmStatic
    fun dynamicShortcutIds(): String =
        context.getSystemService(ShortcutManager::class.java).dynamicShortcuts.map { it.id }.sorted().joinToString("|")

    @JvmStatic
    fun packageName(): String = context.packageName

    /** Opens a Sharesheet for selection from Kotlin directly, on the main thread; its token has no C request. */
    @JvmStatic
    fun shareFromKotlin(text: String) {
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            AndroidShareManager.getInstance(context).shareForSelection(ShareContent(text))
            done.countDown()
        }
        done.await(10, TimeUnit.SECONDS)
    }
}
