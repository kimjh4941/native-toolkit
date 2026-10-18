package com.jonghyunkim.nativetoolkit.common.domain

/**
 * Why a request that needs the screen could not be shown.
 */
enum class UiUnavailableReason {
    /** The library is not initialized (`LibraryRuntime.ensureInitialized` has not succeeded). */
    NOT_INITIALIZED,

    /** No Activity of the app is in the foreground, or it could not show UI any more. */
    NOT_FOREGROUND,

    /** Starting the transparent host Activity failed. */
    HOST_START_FAILED
}

/**
 * Why a request ended without an answer from the user.
 */
enum class CancelReason {
    /** The caller canceled the request. */
    REQUESTED,

    /** The Activity or Fragment that showed the request was destroyed (not by a configuration change). */
    HOST_DESTROYED
}
