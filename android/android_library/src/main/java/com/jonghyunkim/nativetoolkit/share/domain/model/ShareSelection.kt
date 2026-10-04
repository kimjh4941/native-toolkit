package com.jonghyunkim.nativetoolkit.share.domain.model

/**
 * The app the user picked in a Sharesheet opened by `AndroidShareManager.shareForSelection`.
 *
 * @property token The value `shareForSelection` returned for that Sharesheet.
 * @property packageName The package of the picked app, or `null` when Android did not report it.
 */
data class ShareSelection(val token: Long, val packageName: String?)
