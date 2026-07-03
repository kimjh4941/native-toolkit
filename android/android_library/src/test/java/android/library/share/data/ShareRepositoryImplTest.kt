package android.library.share.data

import android.content.ContextWrapper
import android.library.share.data.repository.DirectShareShortcutPublisher
import android.library.share.data.repository.ShareRepositoryImpl
import android.library.share.domain.error.ShareDomainError
import android.library.share.domain.model.DirectShareTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareRepositoryImplTest {

    private val context = object : ContextWrapper(null) {
        override fun getApplicationContext() = this
    }
    private val target = DirectShareTarget(id = "target", label = "Sample User")

    @Test
    fun registerDirectShareTarget_pushReturnsFalse_throwsPushFailed() {
        val repository = ShareRepositoryImpl(context).apply {
            shortcutPublisher = DirectShareShortcutPublisher { _, _, _ -> false }
        }

        val error = runCatching {
            repository.registerDirectShareTarget(target, byteArrayOf(1))
        }.exceptionOrNull()

        assertEquals(
            ShareDomainError.DirectShareRegistrationFailed("push_failed"),
            error
        )
    }

    @Test
    fun registerDirectShareTarget_publisherThrows_convertsToDomainError() {
        val repository = ShareRepositoryImpl(context).apply {
            shortcutPublisher = DirectShareShortcutPublisher { _, _, _ ->
                throw IllegalArgumentException("invalid shortcut")
            }
        }

        val error = runCatching {
            repository.registerDirectShareTarget(target, byteArrayOf(1))
        }.exceptionOrNull()

        assertTrue(error is ShareDomainError.DirectShareRegistrationFailed)
        assertEquals("invalid shortcut", (error as ShareDomainError.DirectShareRegistrationFailed).reason)
    }
}
