// The app driven by taps: each kind of file opens in its reader, a book turns chapters and the
// library remembers where it got to, a note is previewed and saved, and passages are marked by a
// long press and Mark in the menu over them, as a reader would.
package local.granthflow

import android.content.Intent
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.UnderlineSpan
import android.widget.TextView
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
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import androidx.test.espresso.Espresso
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
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
    /** Each test's screens, closed when it ends so the next test starts with none. */
    private val launched = mutableListOf<ActivityScenario<MainActivity>>()

    @After fun closeScreens() = launched.forEach { it.close() }

    private fun launch(path: String) {
        launched += ActivityScenario.launch(Intent(app, MainActivity::class.java).putExtra("open", path).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Puts a file in GranthFlow's folder under a name of its own, and starts the app on it. */
    private fun open(bytes: ByteArray, extension: String): File {
        val file = File(app.books, "t-${UUID.randomUUID()}.$extension").apply { writeBytes(bytes) }
        app.library.add(listOf(file to Engine.detectKind(bytes, file.name)))
        launch(file.path)
        return file
    }

    /** The page's text view (a book's page or a note's preview), found by its tag. */
    private fun <T> page(tag: String, read: (TextView) -> T): T? {
        var out: T? = null
        launched.last().onActivity { a -> a.window.decorView.findViewWithTag<TextView>(tag)?.let { out = read(it) } }
        return out
    }

    private fun waitFor(tag: String, text: String) = compose.waitUntil(10_000) { page(tag) { it.text.contains(text) } == true }

    /** For text Compose draws itself: messages, the hex view. */
    private fun waitForCompose(tag: String, text: String) =
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag(tag).assertTextContains(text, substring = true) }.isSuccess }

    /** Long-presses a word on the page, which selects it, then chooses Mark from the menu over it. */
    private fun mark(tag: String, word: String) {
        val point = page(tag) { tv ->
            val i = tv.text.indexOf(word)
            val layout = tv.layout
            val line = layout.getLineForOffset(i)
            val at = IntArray(2).also { tv.getLocationOnScreen(it) }
            at[0] + tv.totalPaddingLeft + layout.getPrimaryHorizontal(i + word.length / 2).toInt() to
                at[1] + tv.totalPaddingTop + (layout.getLineTop(line) + layout.getLineBottom(line)) / 2
        }!!
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.swipe(point.first, point.second, point.first, point.second, 200)              // held still: a long press
        val item = device.wait(Until.findObject(By.text("Mark")), 3000)
            ?: device.findObject(By.desc("More options")).let { it.click(); device.wait(Until.findObject(By.text("Mark")), 3000) }
        item.click()
    }

    @Test fun aBookTurnsChaptersAndTheLibraryKeepsThePlace() {
        val file = open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        waitFor("page", "CHAPTER 1")
        compose.onNodeWithTag("nextChapter").performClick()
        waitFor("page", "Closing words.")
        compose.onNodeWithContentDescription("Library").performClick()
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("shelf.${file.name}").assertIsDisplayed() }.isSuccess }
        val shelved = compose.onNodeWithTag("shelf.${file.name}")
        shelved.assert(hasText("Finished", substring = true))                 // the last chapter of two
        compose.waitUntil(10_000) { runCatching { shelved.assert(hasText("Tiny Book", substring = true)) }.isSuccess }   // read from the book
    }

    @Test fun aBooksTypeIsSetWithAaAndKeptForIt() {
        val file = open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithTag("typeSettings").performClick()
        compose.onNodeWithTag("textLarger").performClick()
        compose.onNodeWithTag("textSize").assertTextContains("${ReadingDefaults.load(app).size.toInt()} pt")
        compose.onNodeWithTag("look.Night").performClick()
        compose.onNodeWithTag("Line spacing.Loose").performClick()
        val kept = app.library.entry(file.path)!!.settings!!
        assertEquals(ReadingSettings.Look.NIGHT, kept.look)
        assertEquals(ReadingSettings.Spacing.LOOSE, kept.spacing)
        assertEquals(kept, ReadingDefaults.load(app))                       // the next new book starts this way
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
        launch(gone.path)
        waitForCompose("unreadable", "could not be read")
    }

    @Test fun aDamagedPdfSaysSo() {
        open("%PDF-1.4\nnot really a PDF\n".toByteArray(), "pdf")
        waitForCompose("unreadable", "cannot draw this PDF")
    }

    @Test fun aSecondFileOpenedOverTheFirstShowsItself() {
        open(Fixtures.pdf(), "pdf")
        compose.waitUntil(10_000) { runCatching { compose.onNode(hasContentDescription("Page 1")).assertIsDisplayed() }.isSuccess }
        open("# Second\n".toByteArray(), "md")                        // arrives at the running app, as from another app
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("editor").assertTextContains("# Second", substring = true) }.isSuccess }
    }

    @Test fun aPassageInABookIsMarkedNotedAndOpenedFromTheLibrary() {
        val file = open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithTag("nextChapter").performClick()
        waitFor("page", "Closing words.")
        mark("page", "Closing")
        compose.waitUntil(5_000) { app.marks.marks(file.path).isNotEmpty() }
        val kept = app.marks.marks(file.path).single()
        assertEquals("Closing", kept.quote)
        assertEquals(2, kept.target)
        assertEquals("Second Heading", kept.place)
        compose.waitUntil(5_000) {                                                  // painted on the page
            page("page") { (it.text as Spanned).getSpans(0, it.text.length, BackgroundColorSpan::class.java).isNotEmpty() } == true
        }

        compose.onNodeWithTag("marksButton").performClick()
        compose.onNodeWithTag("mark.Closing").assertIsDisplayed()
        compose.onNodeWithTag("addNote").performClick()
        compose.onNodeWithTag("noteField").performTextInput("The last words.")
        compose.onNodeWithTag("noteField").performImeAction()
        compose.onNodeWithTag("note.Closing").assertTextContains("The last words.")
        assertEquals("The last words.", app.marks.marks(file.path).single().note)
        Espresso.pressBack()                                                         // the sheet closes

        compose.onNodeWithTag("previousChapter").performClick()
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithContentDescription("Library").performClick()
        compose.onNodeWithTag("marksTab").performClick()
        compose.onNodeWithText("“Closing”").performClick()                         // opens the book at the mark
        waitFor("page", "Closing words.")
    }

    @Test fun aPassageInANotesPreviewIsMarkedOnItsLine() {
        val file = open("# Notes\n\nSome years ago, a whale.\n".toByteArray(), "md")
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithText("Preview").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithText("Preview").performClick()
        waitFor("preview", "Some years ago")
        mark("preview", "whale")
        compose.waitUntil(5_000) { app.marks.marks(file.path).isNotEmpty() }
        val kept = app.marks.marks(file.path).single()
        assertEquals("whale", kept.quote)
        assertEquals("Line 3", kept.place)
    }

    @Test fun findInABookGoesToTheChapter() {
        open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithTag("findButton").performClick()
        compose.onNodeWithTag("findField").performTextInput("CLOSING")                  // any case
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("hit.0").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag("hit.0").assert(hasText("Second Heading", substring = true)).performClick()
        waitFor("page", "Closing words.")
        compose.waitUntil(5_000) { page("page") { it.selectionEnd - it.selectionStart } == "closing".length }   // the match is selected
    }

    @Test fun findInAPdfGoesToThePage() {
        open(Fixtures.pdf(), "pdf")
        compose.waitUntil(10_000) { runCatching { compose.onNode(hasContentDescription("Page 1")).assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag("findButton").performClick()
        compose.onNodeWithTag("findField").performTextInput("page 2")
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("hit.0").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag("hit.0").assert(hasText("Page 2", substring = true)).performClick()
        compose.waitUntil(10_000) { runCatching { compose.onNode(hasContentDescription("Page 2")).assertIsDisplayed() }.isSuccess }
    }

    @Test fun searchEveryFileFindsAndOpens() {
        val file = open("Ishmael speaks first.\n\nSome years ago, a whale.\n".toByteArray(), "md")
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithText("Preview").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithContentDescription("Library").performClick()
        compose.onNodeWithTag("search").performClick()
        compose.onNodeWithTag("searchField").performTextInput("whale")
        val hit = "searchHit.${file.name}.0"
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag(hit).assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag(hit).assert(hasText("Line 3", substring = true)).performClick()
        waitFor("preview", "Some years ago")                                         // the note opens in its preview
    }

    @Test fun aBookIsReadAloudAndStopped() {
        open(Fixtures.epub(), "epub")
        waitFor("page", "Hello book & reader.")
        compose.onNodeWithTag("readAloud").performClick()
        compose.waitUntil(10_000) { runCatching { compose.onNodeWithTag("stopReading").assertIsDisplayed() }.isSuccess }
        compose.onNodeWithTag("pauseReading").assertIsDisplayed()
        compose.waitUntil(10_000) {                                                // the word being spoken is underlined
            page("page") { (it.text as Spanned).getSpans(0, it.text.length, UnderlineSpan::class.java).isNotEmpty() } == true
        }
        compose.onNodeWithTag("stopReading").performClick()
        compose.waitUntil(5_000) { runCatching { compose.onNodeWithTag("readAloud").assertIsDisplayed() }.isSuccess }
    }

    @Test fun anyOtherFileShowsItsBytes() {
        open(byteArrayOf(0x7f, 0x45, 0x4c, 0x46, 0, 1, 0xde.toByte(), 0xad.toByte()), "bin")      // zero bytes: not text
        waitForCompose("hex", "7f 45 4c 46 00 01 de ad")
    }
}
