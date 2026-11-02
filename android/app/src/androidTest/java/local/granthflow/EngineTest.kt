// The engine through JNI: kinds, a book's chapters and text, a changed file, and text that is not
// all in the Basic Multilingual Plane.
package local.granthflow

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EngineTest {
    @Test fun kindsAreDetected() {
        assertEquals("epub", Engine.detectKind(Fixtures.epub(), "b.epub"))
        assertEquals("pdf", Engine.detectKind(Fixtures.pdf(), "r.pdf"))
        assertEquals("markdown", Engine.detectKind("# Notes\n".toByteArray(), "n.md"))
        assertEquals("binary", Engine.detectKind(byteArrayOf(0x7f, 0x45, 0x4c, 0x46, 0, 1, 2), "a.out"))
    }

    @Test fun aBookHasChaptersAndText() {
        val book = Fixtures.epub()
        val chapters = EpubChapter.parse(Engine.run("chapters", data = book, name = "b.epub", kind = "epub").output)
        assertEquals(listOf("First", "Second Heading"), chapters.map { it.title })
        val text = Engine.run("text", listOf("2"), book, "b.epub", "epub")
        assertTrue(text.succeeded)
        assertTrue(text.output, text.output.contains("Closing words."))
        assertEquals("Tiny Book", EpubChapter.meta("Title", Engine.run("meta", data = book, name = "b.epub", kind = "epub").output))
    }

    @Test fun aCommandThatChangesTheFileReturnsItsNewBytes() {
        val r = Engine.run("replace", listOf("cat", "dog"), "a cat sat\n".toByteArray(), "n.txt", "text")
        assertTrue(r.error, r.succeeded)
        assertNotNull(r.changed)
        assertEquals("a dog sat\n", String(r.changed!!))
    }

    @Test fun textOutsideTheBasicPlaneSurvivesTheCrossing() {
        val r = Engine.run("replace", listOf("cat", "🐈 ग्रंथ"), "a cat\n".toByteArray(), "n.txt", "text")
        assertEquals("a 🐈 ग्रंथ\n", String(r.changed!!))
    }
}
