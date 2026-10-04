package com.jonghyunkim.nativetoolkit.share.presentation

import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection

/**
 * The share event hubs (Kotlin API design 8.4). `AndroidShareManager` exposes them.
 */
internal object ShareEvents {

    /** Taps on custom Sharesheet actions, as the action ID. Not kept. */
    val chooserActions: EventHub<String> = EventHub(EventHub.Retention.None)

    /** Apps picked in Sharesheets opened by `shareForSelection`. Not kept. */
    val selections: EventHub<ShareSelection> = EventHub(EventHub.Retention.None)
}
