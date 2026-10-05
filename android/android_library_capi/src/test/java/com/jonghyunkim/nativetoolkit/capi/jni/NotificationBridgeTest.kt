package com.jonghyunkim.nativetoolkit.capi.jni

import android.app.ForegroundServiceStartNotAllowedException
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Test

/** The failures of notification operations as `ntk_notification_error` (C ABI design part 2, 11.2). */
class NotificationBridgeTest {

    @Test
    fun aServiceStartRefusedFromTheBackIsServiceStartNotAllowed() {
        assertEquals(14, NotificationBridge.errorOf(ForegroundServiceStartNotAllowedException("from the back")))
    }

    @Test
    fun aScheduleStorageFailureIsStorageFailed() {
        assertEquals(13, NotificationBridge.errorOf(IOException("disk")))
    }

    @Test
    fun anInvalidArgumentAndAnythingElse() {
        assertEquals(1, NotificationBridge.errorOf(IllegalArgumentException("bad")))
        assertEquals(4, NotificationBridge.errorOf(SecurityException("not expected after the checks")))
        assertEquals(4, NotificationBridge.errorOf(IllegalStateException("other")))
    }
}
