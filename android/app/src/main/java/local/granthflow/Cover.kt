// Every file has a face, made from its own contents, as on the Mac and iPhone: a book's own cover
// picture (or its title and author on cloth when it has none), a PDF's first page, a note's first
// lines, a text file's opening lines, or a map of a file's bytes.
package local.granthflow

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.text.format.Formatter
import android.content.Context
import java.io.File
import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min

sealed interface CoverArt {
    data class Book(val title: List<String>, val author: String, val cloth: Int) : CoverArt   // cloth: index into Cover.cloths
    /** A book that comes with its own cover. */
    data class Picture(val image: Bitmap) : CoverArt
    data class Page(val thumbnail: Bitmap?) : CoverArt
    data class Note(val heading: String, val rows: List<String>) : CoverArt
    data class Text(val rows: List<String>) : CoverArt
    data class Bytes(val cells: ByteArray, val cols: Int, val rows: Int) : CoverArt   // cells: indexes into Cover.byteColours
}

/** What the shelf shows for a file: its cover, title, and the line under it. */
data class ShelfFace(val art: CoverArt, val title: String, val author: String, val label: String, val size: Long)

object Cover {
    /** Book cloths: deep colours that light ink reads well on. */
    val cloths = listOf(0xFF1B2F63, 0xFF6E1E24, 0xFF1F4A3A, 0xFF7A4E16, 0xFF4A2A5E, 0xFF2E3A48)
    const val INK = 0xFFF1E4C6
    val byteColours = listOf(0xFF0E1330, 0xFF1D2C73, 0xFF3B49DF, 0xFF27B5A6, 0xFFF2C14E, 0xFFF26A4B, 0xFFF5F4F0)
    const val MAP_COLS = 30
    const val MAP_ROWS = 42
    /** Covers are decoded at most this tall: twice or so a shelf cover's height. */
    private const val PICTURE_HEIGHT = 600

    /** Reads the file and makes its face; null when the file cannot be read. */
    fun face(entry: LibraryEntry): ShelfFace? {
        val data = runCatching { entry.file.readBytes() }.getOrNull() ?: return null
        var title = entry.stem
        var author = ""
        val art = when (entry.kind) {
            "epub" -> {
                val meta = Engine.run("meta", data = data, name = entry.name, kind = "epub").output
                title = EpubChapter.meta("Title", meta) ?: entry.stem
                author = EpubChapter.meta("Author", meta) ?: ""
                bookCover(data, entry.name)?.let { CoverArt.Picture(it) }
                    ?: CoverArt.Book(titleLines(title), author, (stableHash(title) % cloths.size.toULong()).toInt())
            }
            "pdf" -> CoverArt.Page(firstPage(entry.file))
            "markdown" -> {
                val lines = String(data.copyOf(min(data.size, 16_384))).split('\n')
                val h = lines.indexOfFirst { MarkdownRenderer.headingLevel(it.trim()) == 1 }
                val heading = if (h >= 0) lines[h].trim().trimStart('#').trim() else entry.stem
                CoverArt.Note(heading, lines.filterIndexed { i, _ -> i != h }.map { it.trim() }.filter { it.isNotEmpty() }.take(8))
            }
            "text" -> CoverArt.Text(String(data.copyOf(min(data.size, 4096))).split('\n').take(9).map { it.take(28) })
            else -> CoverArt.Bytes(byteMap(data), MAP_COLS, MAP_ROWS)
        }
        return ShelfFace(art, title, author, label(entry.kind, data), data.size.toLong())
    }

    /** "Book · Herman Melville", "Document · Page 3 of 12", "Program · 1.2 MB". */
    fun subtitle(face: ShelfFace, entry: LibraryEntry, context: Context): String =
        face.label + " · " + (entry.progressText ?: face.author.ifEmpty { Formatter.formatShortFileSize(context, face.size) })

    /** The book's own cover picture, decoded at shelf size rather than held at full size. */
    private fun bookCover(data: ByteArray, name: String): Bitmap? {
        val path = Engine.run("cover", data = data, name = name, kind = "epub")
        if (!path.succeeded || path.output.isBlank()) return null
        val bytes = Engine.run("cat", listOf(path.output.trim()), data, name, "epub")
        if (!bytes.succeeded) return null
        val image = bytes.outputBytes
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(image, 0, image.size, bounds)
        if (bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outHeight / (sample * 2) >= PICTURE_HEIGHT) sample *= 2
        return BitmapFactory.decodeByteArray(image, 0, image.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    /** The first page at the cover's width, from the top, on white. */
    private fun firstPage(file: File): Bitmap? = runCatching {
        PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { r ->
            if (r.pageCount == 0) return null
            r.openPage(0).use { page ->
                val bitmap = Bitmap.createBitmap(240, 336, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.WHITE) }
                val scale = 240f / page.width
                page.render(bitmap, null, Matrix().apply { setScale(scale, scale) }, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                bitmap
            }
        }
    }.getOrNull()

    /** What to call a kind of file. Programs are told apart from other data by their magic bytes. */
    fun label(kind: String, data: ByteArray? = null) = when (kind) {
        "epub" -> "Book"
        "pdf" -> "Document"
        "markdown" -> "Note"
        "text" -> "Text"
        else -> if (data != null && isProgram(data)) "Program" else "Data"
    }

    /** Mach-O (32/64-bit, either byte order, and universal), ELF, or a Windows PE file. */
    fun isProgram(data: ByteArray): Boolean {
        val head = data.take(4).map { it.toInt() and 0xFF }
        if (head.size >= 2 && head[0] == 0x4D && head[1] == 0x5A) return true
        val magics = listOf(listOf(0xCF, 0xFA, 0xED, 0xFE), listOf(0xCE, 0xFA, 0xED, 0xFE), listOf(0xFE, 0xED, 0xFA, 0xCF),
                            listOf(0xFE, 0xED, 0xFA, 0xCE), listOf(0xCA, 0xFE, 0xBA, 0xBE), listOf(0x7F, 0x45, 0x4C, 0x46))
        return head in magics
    }

    /** One cell per block of the file, row by row. Files smaller than the grid fill only the top cells. */
    fun byteMap(data: ByteArray, cells: Int = MAP_COLS * MAP_ROWS): ByteArray {
        if (data.isEmpty()) return ByteArray(0)
        val block = max(1, (data.size + cells - 1) / cells)
        return ByteArray((data.size + block - 1) / block) { i -> classify(data, i * block, min(data.size, (i + 1) * block)) }
    }

    /** A block's colour: 0 empty, 4 text, and 1-3, 5, 6 by rising entropy (6 is compressed or random).
     *  Long blocks are sampled at up to 4096 evenly spaced bytes. */
    fun classify(data: ByteArray, from: Int, to: Int): Byte {
        val step = max(1, (to - from) / 4096)
        val counts = IntArray(256)
        var n = 0
        var zeros = 0
        var printable = 0
        var i = from
        while (i < to) {
            val b = data[i].toInt() and 0xFF
            counts[b] += 1
            n += 1
            if (b == 0) zeros += 1
            if (b in 0x20..0x7E || b == 0x0A || b == 0x0D || b == 0x09) printable += 1
            i += step
        }
        if (zeros * 10 >= n * 9) return 0
        if (printable * 100 >= n * 85) return 4
        var entropy = 0.0
        var seen = 0
        for (c in counts) if (c > 0) {
            val p = c.toDouble() / n
            entropy -= p * log2(p)
            seen += 1
        }
        // Short samples under-count entropy; the Miller–Madow correction adds back the expected shortfall.
        entropy = min(8.0, entropy + (seen - 1) / (2.0 * n * ln(2.0)))
        // A block of n bytes can show at most log2(n) bits, so small blocks are judged against that.
        val fraction = entropy / min(8.0, log2(max(n, 2).toDouble()))
        return when {
            fraction < 0.25 -> 1
            fraction < 0.55 -> 2
            fraction < 0.8 -> 3
            fraction < 0.95 -> 5
            else -> 6
        }
    }

    /** FNV-1a, so a book keeps its cloth from one launch to the next. */
    fun stableHash(s: String): ULong {
        var h = 0xcbf29ce484222325uL
        for (b in s.toByteArray()) h = (h xor (b.toUByte().toULong())) * 0x100000001b3uL
        return h
    }

    /** A title broken into at most three short lines, as on a cloth cover. */
    fun titleLines(title: String, width: Int = 12): List<String> {
        val lines = mutableListOf<String>()
        for (word in title.split(' ').filter { it.isNotEmpty() }) {
            val last = lines.lastOrNull()
            if (last != null && last.length + 1 + word.length <= width) lines[lines.size - 1] = "$last $word" else lines.add(word)
        }
        if (lines.size > 3) return lines.take(3).toMutableList().also { it[2] = it[2] + "…" }
        return lines.ifEmpty { listOf(title) }
    }
}
