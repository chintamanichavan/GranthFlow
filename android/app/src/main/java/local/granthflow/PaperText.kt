// A page of set text, as the Mac's PaperTextView and the iPhone's PaperText show it: read-only,
// selectable, a column kept to the reader's measure on the reader's paper. Marked passages are
// painted in their colours, and the menu over a selection offers Mark.
package local.granthflow

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.util.TypedValue
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.widget.ScrollView
import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.max

/** A place to go in a file: a chapter, page or line, and the passage there to show. The serial
 *  makes going to the same passage twice a new request. */
data class GoTo(val target: Int, val quote: String, val serial: Int = 0)

/** The page's text view, kept where a reader can reach it to read it aloud. */
class TextViewHandle {
    var view: TextView? = null
    /** The first character at the top of the screen. */
    var topCharacter: () -> Int = { 0 }
}

/**
 * [page] changes when the text should start again from its top, as for a new chapter; while it stays
 * the same, new text (other settings, a new mark) keeps the passage that was at the top of the
 * screen. [reveal] is brought into view and selected once text holding it is shown, looked for from
 * [revealFrom] on, in any case.
 */
@Composable
fun PaperText(
    text: CharSequence,
    palette: Palette,
    settings: ReadingSettings,
    modifier: Modifier = Modifier,
    page: Int = 0,
    paints: List<Paint> = emptyList(),
    reveal: GoTo? = null,
    revealFrom: Int = 0,
    onMark: ((start: Int, end: Int) -> Unit)? = null,
    handle: TextViewHandle? = null,
    tag: String = "page",
) {
    AndroidView(factory = { PageView(it) }, modifier = modifier, update = { v ->
        v.onMark = onMark
        handle?.view = v.text
        handle?.topCharacter = v::topCharacter
        v.text.tag = tag
        v.show(text, palette, settings, page, paints, reveal, revealFrom)
    })
}

@SuppressLint("ViewConstructor")
class PageView(context: Context) : ScrollView(context) {
    val text = TextView(context)
    var onMark: ((Int, Int) -> Unit)? = null
    private var shownText: CharSequence? = null
    private var shownPage: Int? = null
    private var shownPaints: List<Paint> = emptyList()
    private var shownSettings: ReadingSettings? = null
    private var shownReveal: GoTo? = null
    private var measure = 0
    private val dp = resources.displayMetrics.density

    init {
        isFillViewport = true
        addView(text, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        text.setTextIsSelectable(true)
        text.typeface = Typeface.SERIF
        text.customSelectionActionModeCallback = object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                if (onMark != null) menu.add(Menu.NONE, MARK, 0, "Mark")
                return true
            }
            override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                if (item.itemId != MARK) return false
                val (a, b) = text.selectionStart to text.selectionEnd
                if (a in 0 until b) onMark?.invoke(a, b)
                mode.finish()
                return true
            }
            override fun onDestroyActionMode(mode: ActionMode) {}
        }
    }

    fun show(chars: CharSequence, palette: Palette, settings: ReadingSettings, page: Int, paints: List<Paint>, reveal: GoTo?, revealFrom: Int) {
        setBackgroundColor(palette.window.toArgb())
        text.setTextColor(palette.label.toArgb())
        text.highlightColor = palette.accent.copy(alpha = 0.3f).toArgb()
        measure = (settings.measure.value * dp).toInt()
        if (width > 0) columns(width)
        val changed = chars !== shownText || page != shownPage || paints != shownPaints || settings != shownSettings
        if (changed) {
            val keep = if (page == shownPage) topCharacter() else null
            text.setTextSize(TypedValue.COMPLEX_UNIT_SP, settings.size.toFloat())
            text.setLineSpacing(0f, settings.spacing.lineHeight)
            text.text = painted(chars, paints, palette.window.luminance() < 0.4f)
            shownText = chars
            shownPage = page
            shownPaints = paints
            shownSettings = settings
            post { if (keep != null) scroll(toCharacter = keep) else scrollTo(0, 0) }
        }
        if (reveal != null && reveal != shownReveal) {
            val s = text.text.toString()
            val at = s.indexOf(reveal.quote, revealFrom.coerceIn(0, s.length), ignoreCase = true)
            if (at >= 0) {                                   // else the text holding it is not on show yet
                shownReveal = reveal
                post {
                    scroll(toCharacter = at)
                    android.text.Selection.setSelection(text.text as android.text.Spannable, at, at + reveal.quote.length)
                }
            }
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        columns(w)
    }

    /** Keeps the column at most the measure wide and at least 24 points from each edge. */
    private fun columns(width: Int) {
        val side = max((24 * dp).toInt(), (width - measure) / 2)
        if (text.paddingLeft != side) post { text.setPadding(side, (28 * dp).toInt(), side, (48 * dp).toInt()) }
    }

    /** The first character at the top of the screen. */
    fun topCharacter(): Int {
        val layout = text.layout ?: return 0
        return layout.getLineStart(layout.getLineForVertical(max(0, scrollY - text.top - text.paddingTop)))
    }

    fun scroll(toCharacter: Int) {
        val layout = text.layout ?: return
        val line = layout.getLineForOffset(toCharacter.coerceIn(0, text.length()))
        scrollTo(0, text.top + text.paddingTop + layout.getLineTop(line))
    }

    /** The text with every occurrence of each marked quote given its colour as a background. */
    private fun painted(chars: CharSequence, paints: List<Paint>, dark: Boolean): CharSequence {
        val out = SpannableString(chars)
        val plain = chars.toString()
        val alpha = (Highlights.alpha(dark) * 255).toInt() shl 24
        for (p in paints) for (r in Highlights.ranges(p.quote, plain)) {
            out.setSpan(BackgroundColorSpan(alpha or (p.colour.argb.toInt() and 0xFFFFFF)), r.first, r.last + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return out
    }

    private companion object {
        const val MARK = 1
    }
}
