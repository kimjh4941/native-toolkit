package com.jonghyunkim.nativetoolkit.notification.data.repository

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The "Alarm is alive" rule of 8.6 (Kotlin API design), used for lossy entries in restoreScheduled.
class ScheduleIdentityTest {

    @Test
    fun sameInstallAndBoot_isAlive() {
        assertTrue(ScheduleIdentity.isAlarmAlive("i", 3, "i", 3))
    }

    @Test
    fun anotherBoot_isNotAlive() {
        assertFalse(ScheduleIdentity.isAlarmAlive("i", 3, "i", 4))
    }

    @Test
    fun anotherInstall_isNotAlive() {
        assertFalse(ScheduleIdentity.isAlarmAlive("i", 3, "j", 3))
    }

    @Test
    fun unknownBootCount_isNotAlive_evenWhenBothAreUnknown() {
        assertFalse(ScheduleIdentity.isAlarmAlive("i", -1, "i", -1))
        assertFalse(ScheduleIdentity.isAlarmAlive("i", -1, "i", 3))
    }
}
