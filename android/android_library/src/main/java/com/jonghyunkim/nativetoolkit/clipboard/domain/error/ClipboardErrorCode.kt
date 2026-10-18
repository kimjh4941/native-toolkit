package com.jonghyunkim.nativetoolkit.clipboard.domain.error

/**
 * Classifies clipboard failures into seven codes (Kotlin API design 8.10). The table is the same
 * as the Unity bridge's error codes, so native callers report the same codes on every platform.
 */
enum class ClipboardErrorCode {
    /** [ClipboardDomainError.EmptyContent]. */
    EMPTY_CONTENT,

    /** [ClipboardDomainError.EmptyItemList]. */
    EMPTY_ITEMS,

    /** [ClipboardDomainError.InvalidUri]. */
    INVALID_URI,

    /** [ClipboardDomainError.ClipboardUnavailable]. */
    UNAVAILABLE,

    /** [ClipboardDomainError.ReadNotAllowed]. */
    READ_NOT_ALLOWED,

    /** A [SecurityException] from the system. */
    SECURITY,

    /** Anything else. */
    UNKNOWN;

    companion object {
        /**
         * Returns the code of [error]. The thrown types are not changed; this only reads them.
         *
         * @param error A failure of a clipboard operation.
         */
        fun of(error: Throwable): ClipboardErrorCode = when (error) {
            is ClipboardDomainError.EmptyContent -> EMPTY_CONTENT
            is ClipboardDomainError.EmptyItemList -> EMPTY_ITEMS
            is ClipboardDomainError.InvalidUri -> INVALID_URI
            is ClipboardDomainError.ClipboardUnavailable -> UNAVAILABLE
            is ClipboardDomainError.ReadNotAllowed -> READ_NOT_ALLOWED
            is SecurityException -> SECURITY
            else -> UNKNOWN
        }
    }
}
