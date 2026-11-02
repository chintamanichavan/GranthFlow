// Find inside one file, and search every file on the shelf, as on the Mac and iPhone. Every kind
// answers with the same kind of hit: where it is, a line of context, and a target the reader can go
// to (a line, a chapter number, a page index or a byte offset).
package local.granthflow


data class FindHit(val id: Int, val place: String, val snippet: String, val target: Int)

object Find {
    /** Enough to show; more than this and the query is too broad to be useful. */
    const val LIMIT = 500

    /** A file made ready to search: read and split once, then only looked through. */
    sealed interface Body {
        data class Text(val text: String) : Body
        data class Book(val chapters: List<Pair<EpubChapter, String>>) : Body
        data class Pages(val pages: List<String>) : Body
        class Bytes(val data: ByteArray) : Body
    }

    fun body(data: ByteArray, name: String, kind: String): Body = when (kind) {
        "text", "markdown" -> Body.Text(String(data))
        "epub" -> Body.Book(bookChapters(data, name))
        "pdf" -> Body.Pages(splitPages(Engine.run("text", data = data, name = name, kind = "pdf").output))
        else -> Body.Bytes(data)
    }

    fun hits(query: String, body: Body): List<FindHit> {
        if (query.isEmpty()) return emptyList()
        return when (body) {
            is Body.Text -> lines(query, body.text) { "Line $it" }
            is Body.Book -> chapters(query, body.chapters)
            is Body.Pages -> pages(query, body.pages)
            is Body.Bytes -> bytes(query, body.data)
        }
    }

    /** One hit per matching line, ignoring case. Targets are 1-based line numbers. */
    fun lines(query: String, text: String, firstId: Int = 0, place: (Int) -> String): List<FindHit> {
        val hits = mutableListOf<FindHit>()
        var lineNumber = 1
        var counted = 0                                       // newlines counted in text[0 until counted]
        var from = 0
        while (hits.size < LIMIT) {
            val at = text.indexOf(query, from, ignoreCase = true)
            if (at < 0) break
            for (i in counted until at) if (text[i] == '\n') lineNumber += 1
            counted = at
            val start = text.lastIndexOf('\n', at - 1) + 1
            val end = text.indexOf('\n', at).let { if (it < 0) text.length else it }
            val line = text.substring(start, end)
            hits += FindHit(firstId + hits.size, place(lineNumber), snippet(line, at - start, query.length), lineNumber)
            from = end + 1                                    // one hit per line: carry on from the next line
            if (from >= text.length) break
        }
        return hits
    }

    /** Each chapter's text, as the engine extracts it. Targets are chapter numbers. */
    fun chapters(query: String, book: List<Pair<EpubChapter, String>>): List<FindHit> {
        val hits = mutableListOf<FindHit>()
        for ((chapter, text) in book) {
            hits += lines(query, text, hits.size) { chapter.name }.map { it.copy(target = chapter.number) }
            if (hits.size >= LIMIT) return hits.take(LIMIT)
        }
        return hits
    }

    /** Each page's text. Targets are page indexes, from 0. */
    fun pages(query: String, pages: List<String>): List<FindHit> {
        val hits = mutableListOf<FindHit>()
        pages.forEachIndexed { i, text ->
            hits += lines(query, text, hits.size) { "Page ${i + 1}" }.map { it.copy(target = i) }
            if (hits.size >= LIMIT) return hits.take(LIMIT)
        }
        return hits
    }

    /** A book's chapters with their text, read with two engine calls rather than one per chapter. */
    fun bookChapters(data: ByteArray, name: String): List<Pair<EpubChapter, String>> {
        val list = EpubChapter.parse(Engine.run("chapters", data = data, name = name, kind = "epub").output)
        val texts = splitBook(Engine.run("text", data = data, name = name, kind = "epub").output)
        return list.mapNotNull { c -> texts[c.number]?.let { c to it } }
    }

    /** The engine's whole-book `text`, where each chapter starts with "== N. title ==". Only the next
     *  chapter number counts as a header, so a chapter holding such a line is not cut in two. */
    fun splitBook(output: String): Map<Int, String> {
        val texts = mutableMapOf<Int, String>()
        var current = 0
        val body = mutableListOf<String>()
        fun close() { if (current > 0) texts[current] = body.joinToString("\n") }
        for (line in output.split('\n')) {
            if (line.startsWith("== ${current + 1}. ") && line.endsWith(" ==")) {
                close()
                current += 1
                body.clear()
            } else {
                body += line
            }
        }
        close()
        return texts
    }

    /** The engine's whole-document `text`, where each page of several starts with "===== page N =====".
     *  Only the next page number counts as a header. A single page has none. */
    fun splitPages(output: String): List<String> {
        val pages = mutableListOf<String>()
        var current = 0
        val body = mutableListOf<String>()
        for (line in output.split('\n')) {
            if (line == "===== page ${current + 1} =====") {
                if (current > 0) pages += body.joinToString("\n")
                current += 1
                body.clear()
            } else {
                body += line
            }
        }
        if (current == 0) return listOf(output)
        pages += body.joinToString("\n")
        return pages
    }

    /** Bytes: hex digits ("7f 45 4c") when the query is only hex, otherwise its UTF-8. Targets are offsets. */
    fun bytes(query: String, data: ByteArray): List<FindHit> {
        val needle = hexBytes(query) ?: query.toByteArray()
        if (needle.isEmpty() || needle.size > data.size) return emptyList()
        val hits = mutableListOf<FindHit>()
        var i = 0
        while (hits.size < LIMIT && i <= data.size - needle.size) {
            var match = true
            for (k in needle.indices) if (data[i + k] != needle[k]) { match = false; break }
            if (match) {
                val shown = (i until minOf(i + 16, data.size)).joinToString(" ") { "%02x".format(data[it]) }
                hits += FindHit(hits.size, "0x%x".format(i), shown, i)
            }
            i += 1
        }
        return hits
    }

    /** "7f 45 4c 46" (two or more pairs) or "0x7f454c46"; null for anything else, so a word that
     *  happens to be hex, like "cafe", is searched as text. */
    fun hexBytes(query: String): ByteArray? {
        val q = query.trim()
        val digits = if (q.lowercase().startsWith("0x")) q.drop(2) else {
            val pairs = q.split(' ')
            if (pairs.size < 2 || pairs.any { it.length != 2 }) return null
            pairs.joinToString("")
        }
        if (digits.isEmpty() || digits.length % 2 != 0 || !digits.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
        return ByteArray(digits.length / 2) { digits.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    /** At most about 90 characters of a line, centred on the match, with ellipses where cut. */
    fun snippet(line: String, at: Int, length: Int): String {
        if (line.length <= 90) return line.trim()
        val start = maxOf(0, at - 40)
        val end = minOf(line.length, at + length + 40)
        return (if (start > 0) "…" else "") + line.substring(start, end).trim() + (if (end < line.length) "…" else "")
    }
}

/** Every file on the shelf, each read once and read again only when it changes on disk. */
class Corpus {
    private val ready = mutableMapOf<String, Pair<Long, Find.Body>>()

    /** Files with at least one match, in the order given. */
    fun search(query: String, entries: List<LibraryEntry>): List<Pair<LibraryEntry, List<FindHit>>> = entries.mapNotNull { entry ->
        val body = body(entry) ?: return@mapNotNull null
        Find.hits(query, body).takeIf { it.isNotEmpty() }?.let { entry to it }
    }

    private fun body(entry: LibraryEntry): Find.Body? {
        val modified = entry.file.lastModified()
        ready[entry.path]?.takeIf { it.first == modified }?.let { return it.second }
        val data = runCatching { entry.file.readBytes() }.getOrNull() ?: return null
        return Find.body(data, entry.name, entry.kind).also { ready[entry.path] = modified to it }
    }
}

