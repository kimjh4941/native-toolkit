package com.jonghyunkim.android.nativetoolkit.example

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityIncomingShareInstrumentedTest {

    @Test
    fun clearReceivedShare_clearsStateAndConsumesCurrentIntent() {
        val shareIntent = Intent(
            Intent.ACTION_SEND,
            null,
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext,
            MainActivity::class.java
        ).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Consumed share")
        }

        ActivityScenario.launch<MainActivity>(shareIntent).use { scenario ->
            scenario.onActivity { activity ->
                assertNotNull(activity.receivedShare)
                assertEquals(Intent.ACTION_SEND, activity.intent.action)
                activity.clearReceivedShare()
                assertNull(activity.receivedShare)
                assertEquals(Intent.ACTION_MAIN, activity.intent.action)
                // Restore the launch intent only so ActivityScenario can identify and close the Activity.
                activity.intent = shareIntent
            }
        }
    }
}
