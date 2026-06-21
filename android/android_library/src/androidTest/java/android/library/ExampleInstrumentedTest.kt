package android.library

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.library.share.data.repository.SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX
import android.library.share.data.repository.ShareRepositoryImpl
import android.library.share.domain.error.ShareDomainError
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ExampleInstrumentedTest {

    private val appContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun shareFileProvider_isRegisteredWithLibraryAuthority() {
        val authority = "${appContext.packageName}$SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX"

        val providerInfo = appContext.packageManager.resolveContentProvider(authority, 0)

        assertNotNull(providerInfo)
        assertEquals(authority, providerInfo?.authority)
        assertFalse(providerInfo?.exported ?: true)
        assertTrue(providerInfo?.grantUriPermissions ?: false)
    }

    @Test
    fun shareFile_cacheFile_succeedsWithLibraryProvider() {
        val file = createFile(appContext.cacheDir, "cache-share.txt")
        val repository = ShareRepositoryImpl(NoOpActivityContext(appContext))

        repository.shareFile(file.absolutePath)
    }

    @Test
    fun shareFile_filesFile_succeedsWithLibraryProvider() {
        val file = createFile(appContext.filesDir, "files-share.txt")
        val repository = ShareRepositoryImpl(NoOpActivityContext(appContext))

        repository.shareFile(file.absolutePath)
    }

    @Test
    fun shareFile_externalFilesFile_succeedsWithLibraryProvider() {
        val externalFilesDir = appContext.getExternalFilesDir(null)
        assumeNotNull(externalFilesDir)
        val file = createFile(externalFilesDir!!, "external-share.txt")
        val repository = ShareRepositoryImpl(NoOpActivityContext(appContext))

        repository.shareFile(file.absolutePath)
    }

    @Test
    fun shareFile_noBackupFile_throwsIllegalFileAccess() {
        val file = createFile(appContext.noBackupFilesDir, "blocked-share.txt")
        val repository = ShareRepositoryImpl(NoOpActivityContext(appContext))

        val error = runCatching {
            repository.shareFile(file.absolutePath)
        }.exceptionOrNull()

        assertEquals(ShareDomainError.IllegalFileAccess(file.absolutePath), error)
    }

    private fun createFile(directory: File, fileName: String): File {
        val file = File(directory, fileName)
        file.parentFile?.mkdirs()
        file.writeText("share test")
        return file
    }

    private class NoOpActivityContext(base: Context) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = baseContext.applicationContext

        override fun startActivity(intent: Intent) = Unit
    }
}
