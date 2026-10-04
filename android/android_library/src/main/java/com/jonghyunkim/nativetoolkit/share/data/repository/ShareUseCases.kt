package com.jonghyunkim.nativetoolkit.share.data.repository

import android.content.Context
import com.jonghyunkim.nativetoolkit.share.application.usecase.ShareUseCases

/**
 * Factory function for [ShareUseCases].
 *
 * Builds [ShareUseCases] with [ShareRepositoryImpl].
 *
 * @param context Context converted internally to [Context.getApplicationContext].
 */
fun ShareUseCases(context: Context): ShareUseCases =
    ShareUseCases(ShareRepositoryImpl(context.applicationContext))
