// What the library remembers: each file, when it was opened, and where reading stopped. Kept as
// pretty-printed JSON with the same fields as the Mac and iPhone apps' library.json.
package local.granthflow

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import org.json.JSONArray
import org.json.JSONObject

data class LibraryEntry(
    val path: String,
    val kind: String,
    val opened: Instant,
    /** Where reading stopped: a chapter number for EPUB, a page index for PDF. */
    val position: Int? = null,
    val total: Int? = null,
    /** On the shelf but not opened yet. */
    val unopened: Boolean = false,
    /** How this book is set for reading; null until the reader changes it. */
    val settings: ReadingSettings? = null,
) {
    val file get() = File(path)
    val name: String get() = file.name
    /** The name without its extension, as a title for files that carry none. */
    val stem: String get() = file.nameWithoutExtension.ifEmpty { name }

    /** "Chapter 4 of 135", "Page 3 of 12", "Finished", or null when there is nothing to say. */
    val progressText: String?
        get() {
            val p = position ?: return null
            val t = total?.takeIf { it > 0 } ?: return null
            return when (kind) {
                "epub" -> if (p >= t) "Finished" else "Chapter $p of $t"
                "pdf" -> if (p + 1 >= t) "Finished" else "Page ${p + 1} of $t"
                else -> null
            }
        }

    /** 0..1 through the file, for the progress bar. */
    val progress: Float?
        get() {
            val p = position ?: return null
            val t = total?.takeIf { it > 0 } ?: return null
            return if (kind == "pdf") (p + 1f) / t else p.toFloat() / t
        }
}

class Library(private val file: File) {
    var entries by mutableStateOf(load())
        private set

    /** Most recent first, leaving out files that have gone. */
    val recent: List<LibraryEntry> get() = entries.filter { it.file.exists() }.sortedByDescending { it.opened }

    fun entry(path: String) = entries.firstOrNull { it.path == path }

    fun recordOpened(path: String, kind: String, at: Instant = Instant.now()) {
        val e = entry(path)
        replace(path, e?.copy(opened = at, kind = kind, unopened = false) ?: LibraryEntry(path, kind, at))
    }

    fun recordPosition(path: String, position: Int, total: Int) {
        val e = entry(path) ?: return
        if (e.position == position && e.total == total) return
        replace(path, e.copy(position = position, total = total))
    }

    /** Puts files on the shelf as if just added; ones already there move to the front. */
    fun add(found: List<Pair<File, String>>, at: Instant = Instant.now()) {
        if (found.isEmpty()) return
        val byPath = entries.associateBy { it.path }.toMutableMap()
        for ((f, kind) in found) {
            val e = byPath[f.path]
            byPath[f.path] = e?.copy(opened = at, kind = kind) ?: LibraryEntry(f.path, kind, at, unopened = true)
        }
        entries = byPath.values.toList()
        save()
    }

    fun recordSettings(path: String, settings: ReadingSettings) {
        val e = entry(path) ?: return
        if (e.settings != settings) replace(path, e.copy(settings = settings))
    }

    fun forget(path: String) {
        entries = entries.filter { it.path != path }
        save()
    }

    private fun replace(path: String, entry: LibraryEntry) {
        entries = entries.filter { it.path != path } + entry
        save()
    }

    private fun load(): List<LibraryEntry> {
        if (!file.exists()) return emptyList()
        val array = runCatching { JSONArray(file.readText()) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val o = array.getJSONObject(i)
            runCatching {
                LibraryEntry(
                    path = o.getString("path"), kind = o.getString("kind"), opened = Instant.parse(o.getString("opened")),
                    position = o.optInt("position").takeIf { o.has("position") }, total = o.optInt("total").takeIf { o.has("total") },
                    unopened = o.optBoolean("unopened"),
                    settings = o.optJSONObject("settings")?.let(ReadingSettings::fromJson),
                )
            }.getOrNull()
        }
    }

    private fun save() {
        val array = JSONArray()
        for (e in entries.sortedBy { it.path }) {
            array.put(JSONObject().apply {
                put("path", e.path)
                put("kind", e.kind)
                put("opened", e.opened.truncatedTo(ChronoUnit.SECONDS).toString())     // as Swift writes ISO 8601
                e.position?.let { put("position", it) }
                e.total?.let { put("total", it) }
                if (e.unopened) put("unopened", true)
                e.settings?.let { put("settings", it.toJson()) }
            })
        }
        file.parentFile?.mkdirs()
        val temp = File(file.path + ".tmp")
        temp.writeText(array.toString(2))
        temp.renameTo(file)
    }
}
