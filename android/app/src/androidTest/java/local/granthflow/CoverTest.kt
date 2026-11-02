// Faces made from files' own contents, and reading settings in the shape the Mac and iPhone save.
package local.granthflow

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CoverTest {
    private val app = ApplicationProvider.getApplicationContext<GranthFlowApp>()

    private fun face(bytes: ByteArray, extension: String): ShelfFace {
        val file = File(app.cacheDir, "c-${UUID.randomUUID()}.$extension").apply { writeBytes(bytes) }
        return Cover.face(LibraryEntry(file.path, Engine.detectKind(bytes, file.name), Instant.now()))!!
    }

    @Test fun aBookWithoutAPictureIsTitledOnCloth() {
        val f = face(Fixtures.epub(), "epub")
        assertEquals("Tiny Book", f.title)
        val art = f.art as CoverArt.Book
        assertEquals(listOf("Tiny Book"), art.title)
        assertEquals((Cover.stableHash("Tiny Book") % 6uL).toInt(), art.cloth)          // the same cloth every time
    }

    @Test fun aPdfShowsItsFirstPage() {
        val art = face(Fixtures.pdf(), "pdf").art as CoverArt.Page
        assertEquals(240, art.thumbnail!!.width)
    }

    @Test fun aNoteShowsItsHeadingAndFirstLines() {
        val art = face("intro\n# Plans\n\n- one\n- two\n".toByteArray(), "md").art as CoverArt.Note
        assertEquals("Plans", art.heading)
        assertEquals(listOf("intro", "- one", "- two"), art.rows)
    }

    @Test fun aProgramIsMappedByItsBytes() {
        val elf = byteArrayOf(0x7f, 0x45, 0x4c, 0x46) + ByteArray(2000) + ByteArray(2000) { (it * 7919 % 251).toByte() }
        val f = face(elf, "bin")
        assertEquals("Program", f.label)
        val cells = (f.art as CoverArt.Bytes).cells
        assertEquals(0, cells[1].toInt())                    // zeros are empty
        assertTrue(cells.last().toInt() >= 5)                 // varied bytes are dense
    }

    @Test fun longTitlesBreakIntoAtMostThreeLines() {
        assertEquals(listOf("The Brothers", "Karamazov"), Cover.titleLines("The Brothers Karamazov"))
        assertEquals(listOf("One Two", "Three Four", "Five Six…"), Cover.titleLines("One Two Three Four Five Six Seven Eight"))
    }

    @Test fun settingsReadAsTheOtherAppsWriteThem() {
        val s = ReadingSettings.fromJson(JSONObject("""{"size": 20, "spacing": "loose", "width": "wide", "look": "sepia"}"""))
        assertEquals(ReadingSettings(20.0, ReadingSettings.Spacing.LOOSE, ReadingSettings.Width.WIDE, ReadingSettings.Look.SEPIA), s)
        assertEquals(s, ReadingSettings.fromJson(s.toJson()))
        assertEquals(ReadingSettings(), ReadingSettings.fromJson(JSONObject("""{"look": "chartreuse"}""")))     // unknown values take defaults
    }
}
