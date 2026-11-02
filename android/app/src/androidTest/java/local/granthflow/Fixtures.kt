// Small files built in code, so the tests carry no binary fixtures.
package local.granthflow

import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32

object Fixtures {
    /** Two chapters, "First" and "Second Heading", stored uncompressed. */
    fun epub(): ByteArray = zip(
        listOf(
            "mimetype" to "application/epub+zip",
            "META-INF/container.xml" to "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>",
            "OPS/book.opf" to "<package version=\"3.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>Tiny Book</dc:title></metadata>" +
                "<manifest><item id=\"a\" href=\"a.xhtml\"/><item id=\"b\" href=\"b.xhtml\"/><item id=\"n\" href=\"nav.xhtml\" properties=\"nav\"/></manifest>" +
                "<spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>",
            "OPS/a.xhtml" to "<html><body><h1>First</h1><p>Hello book &amp; reader.</p></body></html>",
            "OPS/b.xhtml" to "<html><body><h1>Second Heading</h1><p>Closing words.</p></body></html>",
            "OPS/nav.xhtml" to "<html><body><nav><ol><li><a href=\"a.xhtml\">First</a></li></ol></nav></body></html>",
        ),
    )

    /** Two pages, each with a line of text. */
    fun pdf(): ByteArray {
        val doc = PdfDocument()
        for (n in 1..2) {
            val page = doc.startPage(PdfDocument.PageInfo.Builder(400, 500, n).create())
            page.canvas.drawText("Page $n of the report.", 20f, 40f, Paint().apply { textSize = 24f })
            doc.finishPage(page)
        }
        return ByteArrayOutputStream().also { doc.writeTo(it); doc.close() }.toByteArray()
    }

    private fun zip(files: List<Pair<String, String>>): ByteArray {
        val body = ByteArrayOutputStream()
        val directory = ByteArrayOutputStream()
        fun ByteArrayOutputStream.le16(v: Int) { write(v and 0xFF); write((v shr 8) and 0xFF) }
        fun ByteArrayOutputStream.le32(v: Long) { le16((v and 0xFFFF).toInt()); le16(((v shr 16) and 0xFFFF).toInt()) }
        for ((fileName, fileContent) in files) {
            val name = fileName.toByteArray()
            val content = fileContent.toByteArray()
            val crc = CRC32().apply { update(content) }.value
            val fields = ByteArrayOutputStream().apply {
                le16(10); le16(0); le16(0); le16(0); le16(0x21); le32(crc)
                le32(content.size.toLong()); le32(content.size.toLong()); le16(name.size); le16(0)
            }.toByteArray()
            directory.apply {
                write(byteArrayOf(0x50, 0x4B, 0x01, 0x02)); le16(20); write(fields); le16(0); le16(0); le16(0); le32(0); le32(body.size().toLong()); write(name)
            }
            body.apply { write(byteArrayOf(0x50, 0x4B, 0x03, 0x04)); write(fields); write(name); write(content) }
        }
        val dir = directory.toByteArray()
        val start = body.size().toLong()
        body.write(dir)
        body.apply {
            write(byteArrayOf(0x50, 0x4B, 0x05, 0x06)); le16(0); le16(0); le16(files.size); le16(files.size)
            le32(dir.size.toLong()); le32(start); le16(0)
        }
        return body.toByteArray()
    }
}
