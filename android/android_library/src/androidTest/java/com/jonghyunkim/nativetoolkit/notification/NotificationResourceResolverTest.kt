package com.jonghyunkim.nativetoolkit.notification

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.notification.presentation.resource.NotificationResourceResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

// Resource names, moved from the Unity bridge (Kotlin API design 8.5).
@RunWith(AndroidJUnit4::class)
class NotificationResourceResolverTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val resolver = NotificationResourceResolver(context)

    @Test
    fun explicitType_findsTheLibraryLayout() {
        val expected = context.resources.getIdentifier("fragment_native_dialog", "layout", context.packageName)
        assertNotEquals(0, expected)
        assertEquals(expected, resolver.resolve("fragment_native_dialog", "layout"))
    }

    @Test
    fun noType_triesDrawableThenMipmap_only() {
        assertNull(resolver.resolve("fragment_native_dialog"))
    }

    @Test
    fun unsupportedType_orUnknownName_isNull() {
        assertNull(resolver.resolve("NativeToolkit.Theme.Host", "style"))
        assertNull(resolver.resolve("no_such_resource_ntk", "drawable"))
    }

    @Test
    fun defaultSmallIcon_fallsBackWhenTheAppHasNoIcon() {
        val expected = context.applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info
        assertEquals(expected, resolver.defaultSmallIcon())
    }
}
