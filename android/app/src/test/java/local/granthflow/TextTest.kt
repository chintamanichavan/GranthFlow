// The text work that needs no device: finding in lines and pages, splitting the engine's output,
// and cutting text into pieces the speech engine will take.
package local.granthflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TextTest {
    @Test fun oneHitPerMatchingLineIgnoringCase() {
        val hits = Find.lines("whale", "a Whale\nno\nwhale and whale\n") { "Line $it" }
        assertEquals(listOf(1, 3), hits.map { it.target })
        assertEquals("whale and whale", hits[1].snippet)
    }

    @Test fun pagesSplitOnTheirHeadersOnly() {
        val out = "===== page 1 =====\none\n===== page 3 =====\nstill one\n===== page 2 =====\ntwo\n"
        assertEquals(listOf("one\n===== page 3 =====\nstill one", "two\n"), Find.splitPages(out))
        assertEquals(listOf("just one page"), Find.splitPages("just one page"))
    }

    @Test fun pageHitsArePageIndexes() {
        val hits = Find.pages("cost", listOf("intro", "costs held flat"))
        assertEquals(1, hits.single().target)
        assertEquals("Page 2", hits.single().place)
    }

    @Test fun hexQueriesAreBytes() {
        assertEquals(listOf(0x7f.toByte(), 0x45), Find.hexBytes("7f 45")?.toList())
        assertEquals(null, Find.hexBytes("cafe"))                     // a word, searched as text
        assertEquals(2, Find.bytes("7f 45", byteArrayOf(0, 0, 0x7f, 0x45, 1)).single().target)
    }

    @Test fun speechPiecesEndAtSentencesAndCoverTheText() {
        val text = "First sentence here. Second one follows. Third."
        val pieces = Speaker.pieces(text, 0, 25)
        assertEquals("First sentence here.", pieces[0].second)
        assertEquals(text, pieces.joinToString("") { it.second })
        pieces.forEach { (at, piece) -> assertEquals(piece, text.substring(at, at + piece.length)) }
        assertTrue(Speaker.pieces("   ", 0, 25).isEmpty())
        assertEquals(listOf(32 to "follows. Third."), Speaker.pieces(text, 32, 100))           // from the selection or the screen's top
    }
}
