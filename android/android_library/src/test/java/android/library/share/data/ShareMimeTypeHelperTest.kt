package android.library.share.data

import android.library.share.data.repository.ShareMimeTypeHelper
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class ShareMimeTypeHelperTest {

    @Test
    fun getMimeType_jpgExtension_returnsImageJpeg() {
        assertEquals("image/jpeg", ShareMimeTypeHelper.getMimeType(File("photo.jpg")))
    }

    @Test
    fun getMimeType_jpegExtension_returnsImageJpeg() {
        assertEquals("image/jpeg", ShareMimeTypeHelper.getMimeType(File("photo.jpeg")))
    }

    @Test
    fun getMimeType_pngExtension_returnsImagePng() {
        assertEquals("image/png", ShareMimeTypeHelper.getMimeType(File("image.png")))
    }

    @Test
    fun getMimeType_gifExtension_returnsImageGif() {
        assertEquals("image/gif", ShareMimeTypeHelper.getMimeType(File("anim.gif")))
    }

    @Test
    fun getMimeType_webpExtension_returnsImageWebp() {
        assertEquals("image/webp", ShareMimeTypeHelper.getMimeType(File("image.webp")))
    }

    @Test
    fun getMimeType_pdfExtension_returnsApplicationPdf() {
        assertEquals("application/pdf", ShareMimeTypeHelper.getMimeType(File("doc.pdf")))
    }

    @Test
    fun getMimeType_txtExtension_returnsTextPlain() {
        assertEquals("text/plain", ShareMimeTypeHelper.getMimeType(File("readme.txt")))
    }

    @Test
    fun getMimeType_mp4Extension_returnsVideoMp4() {
        assertEquals("video/mp4", ShareMimeTypeHelper.getMimeType(File("video.mp4")))
    }

    @Test
    fun getMimeType_mp3Extension_returnsAudioMpeg() {
        assertEquals("audio/mpeg", ShareMimeTypeHelper.getMimeType(File("song.mp3")))
    }

    @Test
    fun getMimeType_uppercaseExtension_returnsCorrectMimeType() {
        assertEquals("image/jpeg", ShareMimeTypeHelper.getMimeType(File("PHOTO.JPG")))
    }

    @Test
    fun getMimeType_unknownExtension_returnsWildcard() {
        assertEquals("*/*", ShareMimeTypeHelper.getMimeType(File("file.xyz")))
    }

    @Test
    fun getMimeType_noExtension_returnsWildcard() {
        assertEquals("*/*", ShareMimeTypeHelper.getMimeType(File("fileWithNoExtension")))
    }
}
