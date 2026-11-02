// How reading text is set: serif type on paper, a chapter's number and title above it, as on the
// Mac and iPhone. Also the engine's chapter list, and Markdown set as a page. Text is built as
// Android spans, for the page view to show at the reader's size and spacing.
package local.granthflow

import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AlignmentSpan
import android.text.style.ForegroundColorSpan
import android.text.style.MetricAffectingSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import androidx.compose.ui.graphics.toArgb

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
    const val BODY_SIZE = 17f

    /** A chapter as it is shown: "CHAPTER n" and the title, centred, then the text. Sizes are
     *  relative to the body, so the label and title grow with the text. */
    fun chapter(text: String, number: Int, title: String, palette: Palette): CharSequence = SpannableStringBuilder().apply {
        val t = title.trim()
        span("CHAPTER $number\n", AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), RelativeSizeSpan(12f / BODY_SIZE),
             TypefaceSpan("sans-serif-medium"), Tracking(0.16f), ForegroundColorSpan(palette.secondary.toArgb()))
        if (t.isNotEmpty()) span("$t\n\n", AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), RelativeSizeSpan(30f / BODY_SIZE))
        else append("\n")
        append(dropLeadingTitle(text, t))
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
 *  links inline. Each line of the preview carries its line in the source. */
object MarkdownRenderer {
    private val headingSizes = listOf(30f, 23f, 19f, 17f, 15f, 14f)

    fun render(source: String, palette: Palette): CharSequence = SpannableStringBuilder().apply {
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
                inFence -> span(line, TypefaceSpan("monospace"), RelativeSizeSpan(14f / ReadingStyle.BODY_SIZE),
                                ForegroundColorSpan(palette.secondary.toArgb()))
                level != null -> span(trimmed.trimStart('#').trim(), RelativeSizeSpan(headingSizes[level - 1] / ReadingStyle.BODY_SIZE),
                                      StyleSpan(Typeface.BOLD))
                trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ") -> {
                    append("  •  ")
                    inline(trimmed.drop(2), palette)
                }
                else -> inline(line, palette)
            }
            append("\n")
            setSpan(SourceLine(i + 1), start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private val inlinePattern = Regex("""\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`|\[(.+?)]\((.+?)\)""")

    /** Bold, italic, code and links within one line. */
    private fun SpannableStringBuilder.inline(s: String, palette: Palette) {
        var at = 0
        for (m in inlinePattern.findAll(s)) {
            append(s.substring(at, m.range.first))
            val g = m.groupValues
            when {
                g[1].isNotEmpty() || g[2].isNotEmpty() -> span(g[1] + g[2], StyleSpan(Typeface.BOLD))
                g[3].isNotEmpty() || g[4].isNotEmpty() -> span(g[3] + g[4], StyleSpan(Typeface.ITALIC))
                g[5].isNotEmpty() -> span(g[5], TypefaceSpan("monospace"), RelativeSizeSpan(0.88f))
                else -> span(g[6], ForegroundColorSpan(palette.accent.toArgb()))
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

    /** The source line a character of the preview came from. */
    fun sourceLine(at: Int, text: CharSequence): Int? {
        if (text !is Spanned || text.isEmpty()) return null
        val i = at.coerceIn(0, text.length - 1)
        return text.getSpans(i, i + 1, SourceLine::class.java).firstOrNull()?.line
    }

    /** The first character of the preview that came from `line` or after it. */
    fun character(forLine: Int, text: CharSequence): Int? {
        if (text !is Spanned) return null
        return text.getSpans(0, text.length, SourceLine::class.java).filter { it.line >= forLine }.minOfOrNull { text.getSpanStart(it) }
    }
}

/** The 1-based line of the Markdown source a stretch of the preview came from. */
class SourceLine(val line: Int)

/** Letter spacing, in ems. */
private class Tracking(private val em: Float) : MetricAffectingSpan() {
    override fun updateDrawState(tp: TextPaint) { tp.letterSpacing = em }
    override fun updateMeasureState(tp: TextPaint) { tp.letterSpacing = em }
}

/** Appends text with spans over all of it. */
private fun SpannableStringBuilder.span(text: String, vararg spans: Any) {
    val start = length
    append(text)
    for (s in spans) setSpan(s, start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
}
