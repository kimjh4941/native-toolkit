package com.jonghyunkim.nativetoolkit.kotlinconsumer

import android.content.Context
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi
import com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager

/**
 * Calls into both AARs, so that compiling it reads their Kotlin metadata and links against the
 * Kotlin core libraries their POMs ask for. Compiling is the check; nothing runs this.
 */
object Uses {
    fun touch(context: Context): String {
        val capi: NativeToolkitCApi.InitResult = NativeToolkitCApi.init(context)
        AndroidClipboardManager.getInstance(context).copyPlainText(ClipContent.PlainText("kotlin consumer"))
        val permitted = AndroidNotificationManager.getInstance(context).hasPermission()
        return "$capi $permitted"
    }
}
