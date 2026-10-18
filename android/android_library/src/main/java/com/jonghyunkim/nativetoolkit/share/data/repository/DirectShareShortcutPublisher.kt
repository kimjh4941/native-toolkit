package com.jonghyunkim.nativetoolkit.share.data.repository

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import com.jonghyunkim.nativetoolkit.share.domain.error.ShareDomainError
import com.jonghyunkim.nativetoolkit.share.domain.model.DirectShareTarget
import android.util.Log
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

internal fun interface DirectShareShortcutPublisher {
    fun push(context: Context, target: DirectShareTarget, iconBytes: ByteArray): Boolean
}

internal object AndroidDirectShareShortcutPublisher : DirectShareShortcutPublisher {
    override fun push(context: Context, target: DirectShareTarget, iconBytes: ByteArray): Boolean {
        Log.d(TAG, "[push] context: $context, target: $target, iconBytes.size: ${iconBytes.size}")
        val bitmap = BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size)
            ?: throw ShareDomainError.InvalidBase64Icon(target.id)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_DEFAULT)
        val shortcut = ShortcutInfoCompat.Builder(context, target.id)
            .setShortLabel(target.label)
            .setIcon(IconCompat.createWithBitmap(bitmap))
            .setCategories(setOf(target.category))
            .setIntent(launchIntent)
            .setLongLived(true)
            .build()
        return ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }

    private const val TAG = "AndroidDirectShareShortcutPublisher"
}
