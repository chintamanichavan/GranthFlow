// Marks: passages the reader highlighted, kept apart from the files so marking never changes a
// file. Stored as pretty-printed JSON beside the library, with the same fields as the Mac and
// iPhone apps' marks.json.
package local.granthflow

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** The colour a mark is painted in. A reader might use yellow for ideas and pink for quotes. */
enum class MarkColour(val argb: Long) {
    YELLOW(0xFFFFDD6B), PINK(0xFFFF9EC4), GREEN(0xFFA6E3A1), BLUE(0xFF9CC8FF);

    val title get() = name.lowercase().replaceFirstChar { it.uppercase() }
}

/** A passage to paint, and in which colour. */
data class Paint(val quote: String, val colour: MarkColour)

/** What is selected on a page, ready to become a mark. */
data class Selection(val quote: String, val target: Int, val place: String)

data class Mark(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val path: String,
    val kind: String,
    val quote: String,
    /** Where it is, as Find and the chapter list say it: a chapter number or a line. */
    val target: Int,
    val place: String,
    val created: Instant = Instant.now(),
    /** The reader's own words about the passage. */
    val note: String = "",
    val colour: MarkColour = MarkColour.YELLOW,
) {
    val paint get() = Paint(quote, colour)
    val name: String get() = File(path).name
}

class MarkStore(private val file: File) {
    var marks by mutableStateOf(load())
        private set

    /** Newest first. */
    val all: List<Mark> get() = marks.sortedByDescending { it.created }

    fun marks(path: String): List<Mark> = marks.filter { it.path == path }.sortedWith(compareBy({ it.target }, { it.created }))

    /** Adds a mark for the selection; a selection already marked at the same place is not added twice. */
    fun add(selection: Selection, path: String, kind: String, at: Instant = Instant.now()): Mark? {
        val quote = clean(selection.quote)
        if (quote.isEmpty()) return null
        marks.firstOrNull { it.path == path && it.target == selection.target && it.quote == quote }?.let { return it }
        val mark = Mark(path = path, kind = kind, quote = quote, target = selection.target, place = selection.place, created = at)
        marks = marks + mark
        save()
        return mark
    }

    /** Sets a mark's note, trimmed; an empty note removes it. */
    fun setNote(mark: Mark, note: String) = change(mark) { it.copy(note = note.trim()) }

    fun setColour(mark: Mark, colour: MarkColour) = change(mark) { it.copy(colour = colour) }

    fun remove(mark: Mark) {
        marks = marks.filter { it.id != mark.id }
        save()
    }

    private fun change(mark: Mark, edit: (Mark) -> Mark) {
        val now = marks.firstOrNull { it.id == mark.id } ?: return
        val changed = edit(now)
        if (changed == now) return
        marks = marks.map { if (it.id == mark.id) changed else it }
        save()
    }

    private fun load(): List<Mark> {
        if (!file.exists()) return emptyList()
        val array = runCatching { JSONArray(file.readText()) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val o = array.getJSONObject(i)
            runCatching {
                Mark(
                    id = o.getString("id"), path = o.getString("path"), kind = o.getString("kind"), quote = o.getString("quote"),
                    target = o.getInt("target"), place = o.getString("place"), created = Instant.parse(o.getString("created")),
                    note = o.optString("note"),
                    colour = MarkColour.entries.firstOrNull { it.name.equals(o.optString("colour"), true) } ?: MarkColour.YELLOW,
                )
            }.getOrNull()
        }
    }

    private fun save() {
        val array = JSONArray()
        for (m in marks.sortedBy { it.created }) {
            array.put(JSONObject().apply {
                put("id", m.id); put("path", m.path); put("kind", m.kind); put("quote", m.quote); put("target", m.target)
                put("place", m.place); put("created", m.created.truncatedTo(ChronoUnit.SECONDS).toString())
                put("note", m.note); put("colour", m.colour.name.lowercase())
            })
        }
        file.parentFile?.mkdirs()
        val temp = File(file.path + ".tmp")
        temp.writeText(array.toString(2))
        temp.renameTo(file)
    }

    companion object {
        /** A mark is a passage, not a chapter; longer selections are cut here. */
        const val LONGEST = 1000

        /** Trimmed, and cut at `LONGEST` characters on a word boundary. */
        fun clean(quote: String): String {
            val q = quote.trim()
            if (q.length <= LONGEST) return q
            val cut = q.take(LONGEST)
            return cut.substring(0, cut.lastIndexOf(' ').takeIf { it > 0 } ?: cut.length) + "…"
        }
    }
}

/** A book's marks as Markdown, as the Mac exports them: each passage as a quote with the reader's
 *  note under it, grouped by chapter or page in reading order. */
object MarkExport {
    fun markdown(title: String, author: String, marks: List<Mark>, on: Instant = Instant.now()): String = buildString {
        append("# $title\n")
        if (author.isNotEmpty()) append("\n*$author*\n")
        val count = if (marks.size == 1) "1 mark" else "${marks.size} marks"
        val date = DateTimeFormatter.ofPattern("MMMM d, yyyy").withZone(ZoneId.systemDefault()).format(on)
        append("\nExported from GranthFlow on $date · $count\n")
        // Colours only mean something when the reader used more than one.
        val showColour = marks.map { it.colour }.toSet().size > 1
        var place: String? = null
        for (m in marks.sortedWith(compareBy({ it.target }, { it.created }))) {
            if (m.place != place) {
                place = m.place
                append("\n## ${m.place}\n")
            }
            append("\n" + m.quote.split('\n').joinToString("\n") { if (it.isEmpty()) ">" else "> $it" } + "\n")
            if (showColour) append("\n*${m.colour.title}*\n")
            if (m.note.isNotEmpty()) append("\n${m.note}\n")
        }
    }

    fun fileName(title: String) = title.replace('/', '-').replace(':', '-') + " — marks.md"
}

/** Where each marked passage falls in a text. */
object Highlights {
    fun ranges(quote: String, text: String): List<IntRange> {
        if (quote.isEmpty()) return emptyList()
        val out = mutableListOf<IntRange>()
        var from = 0
        while (true) {
            val i = text.indexOf(quote, from)
            if (i < 0) break
            out += i until i + quote.length
            from = i + quote.length
        }
        return out
    }

    /** How strongly a mark's colour is laid on: lighter on dark paper, so the light text stays readable. */
    fun alpha(dark: Boolean) = if (dark) 0.38f else 0.7f
}
