// The app driven by taps: each kind of file opens in its reader, a book turns chapters and the
// library remembers where it got to, and a note is previewed and saved.
package local.granthflow

import android.content.Intent
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ReaderTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app = ApplicationProvider.getApplicationContext<GranthFlowApp>()

    /** Puts a file in GranthFlow's folder under a name of its own, and starts the app on it. */
    private fun open(bytes: ByteArray, extension: String): File {
        val file = File(app.books, "t-${UUID.randomUUID()}.$extension").apply { writeBytes(bytes) }
        app.library.add(listOf(file to Engine.detectKind(bytes, file.name)))
        val intent = Intent(app, MainActivity::class.java).putExtra("open", file.path).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<MainActivity>(intent)
        return file
    }

    private fun waitFor(tag: String, text: String) =
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag(tag).assertTextContains(text, substring = true) }.isSuccess }

    @Test fun aBookTurnsChaptersAndTheLibraryKeepsThePlace() {
        val file = open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithTag("page").assertTextContains("CHAPTER 1", substring = true)
        compose.onNodeWithTag("nextChapter").performClick()
        waitFor("page", "Closing words.")
        compose.onNodeWithContentDescription("Library").performClick()
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("shelf.${file.name}").assertIsDisplayed() }.isSuccess }
        val shelved = compose.onNodeWithTag("shelf.${file.name}")
        shelved.assert(hasText("Finished", substring = true))                 // the last chapter of two
        compose.waitUntil(10_000) { runCatching { shelved.assert(hasText("Tiny Book", substring = true)) }.isSuccess }   // read from the book
    }

    @Test fun aPdfShowsItsPages() {
        open(Fixtures.pdf(), "pdf")
        compose.waitUntil(10_000) { runCatching { compose.onNode(hasContentDescription("Page 1")).assertIsDisplayed() }.isSuccess }
    }

    @Test fun aNoteIsPreviewedAndItsEditsAreSaved() {
        val file = open("# Notes\n\nSome **bold** words.\n".toByteArray(), "md")
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithText("Preview").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag("editor").performTextInput("Added. ")
        compose.onNodeWithText("Preview").performClick()
        waitFor("preview", "Some bold words.")
        compose.onNodeWithContentDescription("Library").performClick()
        compose.waitForIdle()
        assertEquals("Added. # Notes\n\nSome **bold** words.\n", file.readText())
    }

    @Test fun aFileThatHasGoneSaysSo() {
        val gone = File(app.books, "gone-${UUID.randomUUID()}.epub")
        ActivityScenario.launch<MainActivity>(Intent(app, MainActivity::class.java).putExtra("open", gone.path).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        waitFor("unreadable", "could not be read")
    }

    @Test fun aDamagedPdfSaysSo() {
        open("%PDF-1.4\nnot really a PDF\n".toByteArray(), "pdf")
        waitFor("unreadable", "cannot draw this PDF")
    }

    @Test fun aSecondFileOpenedOverTheFirstShowsItself() {
        open(Fixtures.pdf(), "pdf")
        compose.waitUntil(10_000) { runCatching { compose.onNode(hasContentDescription("Page 1")).assertIsDisplayed() }.isSuccess }
        open("# Second\n".toByteArray(), "md")                        // arrives at the running app, as from another app
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("editor").assertTextContains("# Second", substring = true) }.isSuccess }
    }

    @Test fun anyOtherFileShowsItsBytes() {
        open(byteArrayOf(0x7f, 0x45, 0x4c, 0x46, 0, 1, 0xde.toByte(), 0xad.toByte()), "bin")      // zero bytes: not text
        waitFor("hex", "7f 45 4c 46 00 01 de ad")
    }
}
