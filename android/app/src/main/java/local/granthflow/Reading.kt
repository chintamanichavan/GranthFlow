// How reading text is set: serif type on paper, a chapter's number and title above it, as on the
// Mac and iPhone. Also the engine's chapter list, and Markdown set as a page.
package local.granthflow

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** One chapter as the engine lists it. */
data class EpubChapter(val number: Int, val title: String, val path: String) {
    val name get() = title.ifEmpty { "Chapter $number" }

    companion object {
        /** The engine's `chapters` output: one "number<TAB>title<TAB>path" line per chapter. */
        fun parse(output: String): List<EpubChapter> = output.lines().mapNotNull { line ->
            val f = line.split('\t', limit = 3)
            val n = f.getOrNull(0)?.toIntOrNull() ?: return@mapNotNull null
            if (f.size == 3) EpubChapter(n, f[1], f[2]) else null
        }

        /** A field from the engine's `meta` output, such as "title" or "language". */
        fun meta(field: String, output: String): String? = output.lines()
            .firstOrNull { it.substringBefore(':').trim().equals(field, ignoreCase = true) }
            ?.substringAfter(':')?.trim()?.ifEmpty { null }
    }
}

object ReadingStyle {
    const val BODY_SIZE = 17

    /** A chapter as it is shown: "CHAPTER n" and the title, centred, then the text. The label and
     *  title grow with the text. */
    fun chapter(text: String, number: Int, title: String, settings: ReadingSettings, palette: Palette): AnnotatedString = buildAnnotatedString {
        val t = title.trim()
        val scale = (settings.size / 17).toFloat()
        withStyle(ParagraphStyle(textAlign = TextAlign.Center, lineHeight = 2.2.em)) {
            withStyle(SpanStyle(fontSize = (12 * scale).sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.16.em, color = palette.secondary)) {
                append("CHAPTER $number")
            }
        }
        if (t.isNotEmpty()) {
            withStyle(ParagraphStyle(textAlign = TextAlign.Center, lineHeight = 1.3.em)) {
                withStyle(SpanStyle(fontFamily = FontFamily.Serif, fontSize = (30 * scale).sp, color = palette.label)) { append(t) }
            }
            append("\n")
        }
        withStyle(ParagraphStyle(lineHeight = settings.spacing.lineHeight.em)) {
            withStyle(SpanStyle(fontFamily = FontFamily.Serif, fontSize = settings.size.sp, color = palette.label)) {
                append(dropLeadingTitle(text, t))
            }
        }
    }

    /** Chapters usually begin with their own heading; it is already shown as the title. */
    fun dropLeadingTitle(text: String, title: String): String {
        if (title.isEmpty()) return text
        val rest = text.trimStart()
        val firstLine = rest.substringBefore('\n')
        if (!firstLine.trim().equals(title, ignoreCase = true)) return text
        return rest.substring(firstLine.length).trimStart('\n', '\r')
    }
}

/** Markdown set as a page: headings, lists and code in reading type, with bold, italic, code and
 *  links inline. Each line of the preview is tagged with its line in the source. */
object MarkdownRenderer {
    const val LINE = "sourceLine"
    private val headingSizes = listOf(30, 23, 19, 17, 15, 14)

    fun render(source: String, palette: Palette): AnnotatedString = buildAnnotatedString {
        var inFence = false
        source.split('\n').forEachIndexed { i, line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
                inFence = !inFence
                return@forEachIndexed
            }
            val start = length
            val level = headingLevel(trimmed)
            when {
                inFence -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 14.sp, color = palette.secondary)) { append(line) }
                level != null -> withStyle(
                    SpanStyle(fontFamily = FontFamily.Serif, fontSize = headingSizes[level - 1].sp, fontWeight = FontWeight.SemiBold, color = palette.label),
                ) { append(trimmed.trimStart('#').trim()) }
                trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ") ->
                    withStyle(body(palette)) { append("  •  "); inline(trimmed.drop(2), palette) }
                else -> withStyle(body(palette)) { inline(line, palette) }
            }
            append("\n")
            addStringAnnotation(LINE, (i + 1).toString(), start, length)
        }
    }

    private fun body(palette: Palette) = SpanStyle(fontFamily = FontFamily.Serif, fontSize = ReadingStyle.BODY_SIZE.sp, color = palette.label)

    private val inlinePattern = Regex("""\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`|\[(.+?)]\((.+?)\)""")

    /** Bold, italic, code and links within one line. */
    private fun AnnotatedString.Builder.inline(s: String, palette: Palette) {
        var at = 0
        for (m in inlinePattern.findAll(s)) {
            append(s.substring(at, m.range.first))
            val g = m.groupValues
            when {
                g[1].isNotEmpty() || g[2].isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(g[1] + g[2]) }
                g[3].isNotEmpty() || g[4].isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(g[3] + g[4]) }
                g[5].isNotEmpty() -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp)) { append(g[5]) }
                else -> withStyle(SpanStyle(color = palette.accent)) { append(g[6]) }
            }
            at = m.range.last + 1
        }
        append(s.substring(at))
    }

    fun headingLevel(line: String): Int? {
        val hashes = line.takeWhile { it == '#' }.length
        if (hashes !in 1..6) return null
        val rest = line.drop(hashes)
        return if (rest.isEmpty() || rest.first() == ' ') hashes else null
    }
}

