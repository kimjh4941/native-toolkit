package android.library.clipboard.data.repository

import android.content.Context
import android.library.clipboard.application.usecase.ClipboardUseCases

/**
 * Factory function for [ClipboardUseCases].
 *
 * Builds [ClipboardUseCases] with [ClipboardRepositoryImpl].
 *
 * @param context Context converted internally to [Context.getApplicationContext].
 */
fun ClipboardUseCases(context: Context): ClipboardUseCases =
    ClipboardUseCases(ClipboardRepositoryImpl(context.applicationContext))
