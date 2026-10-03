package com.jonghyunkim.android.nativetoolkit.example.infra

/*
 * Test categories for scripts/test_android.sh (section 8 of the android-c-abi UI test design).
 * The runner selects them with `-e annotation` / `-e notAnnotation` and the fully qualified name.
 */

/** Menu and screen navigation (6.1). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryNavigation

/** Dialog screen (6.2). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryDialog

/** Notification screen, except the host-driven cases (6.3). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryNotification

/** Cases whose device state the host sets up first, because changing it kills the app process (U-5). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryHostState

/** Share screen (6.4 S-xx). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryShare

/** Received-share screen (6.4 R-xx). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryReceivedShare

/** Clipboard screen (6.5). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryClipboard

/** First phase of the host-driven cases that span an app update or a reboot (3.7). */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class CategoryHost
