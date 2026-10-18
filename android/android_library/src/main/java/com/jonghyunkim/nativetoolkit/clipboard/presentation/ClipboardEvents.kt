package com.jonghyunkim.nativetoolkit.clipboard.presentation

import com.jonghyunkim.nativetoolkit.common.event.EventHub

/**
 * The clipboard event hub (Kotlin API design 8.4). `AndroidClipboardManager` exposes it.
 */
internal object ClipboardEvents {

    /** The primary clip changed while [ClipboardObserver] was observing. Not kept. */
    val changes: EventHub<Unit> = EventHub(EventHub.Retention.None)
}
