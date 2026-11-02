// Reading aloud with the system's voices, as on the Mac and iPhone: from the selection or the top of
// the page, the word being spoken underlined and kept in view. The voice follows the book's language;
// Marathi falls back to Hindi, which reads Devanagari, when no Marathi voice is installed.
//
// Android's speech engine takes a few thousand characters at a time and cannot pause, so the text
// goes in pieces that end at a sentence, and pausing stops at the word and resumes from it.
package local.granthflow

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.text.Spannable
import android.text.style.UnderlineSpan
import android.widget.TextView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

class Speaker(context: Context) {
    enum class State { IDLE, SPEAKING, PAUSED }

    var state by mutableStateOf(State.IDLE)
        private set
    private val main = Handler(Looper.getMainLooper())
    private var ready = false
    /** A request made before the voices were ready, run once they are. */
    private var waiting: (() -> Unit)? = null
    private val tts = TextToSpeech(context.applicationContext) { status ->
        main.post {
            ready = status == TextToSpeech.SUCCESS
            if (ready) waiting?.invoke()
            waiting = null
        }
    }
    private var view: TextView? = null
    private var language: String? = null
    /** The word last spoken, as offsets in the view's text; where a resume starts. */
    private var word: IntRange? = null
    private val underline = UnderlineSpan()

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String) {}
            override fun onRangeStart(id: String, start: Int, end: Int, frame: Int) {
                val base = id.substringBefore(':').toInt()
                main.post { paint(base + start until base + end) }
            }
            override fun onDone(id: String) { if (id.endsWith(":last")) main.post { finished() } }
            @Deprecated("Deprecated in Java") override fun onError(id: String) { main.post { finished() } }
        })
    }

    /** Starts reading `view` aloud from its selection, or else `top`, the first character on screen. */
    fun speak(view: TextView, top: Int, language: String?) {
        stop()
        if (!ready) return run { waiting = { speak(view, top, language) } }
        this.view = view
        this.language = language
        val selection = view.selectionStart.takeIf { it >= 0 && view.selectionEnd > it }
        from(selection ?: top)
    }

    fun pauseOrResume() {
        when (state) {
            State.SPEAKING -> {
                tts.stop()
                state = State.PAUSED
            }
            State.PAUSED -> word?.let { from(it.first) } ?: finished()
            State.IDLE -> {}
        }
    }

    fun stop() {
        waiting = null
        tts.stop()
        finished()
    }

    fun shutdown() {
        stop()
        tts.shutdown()
    }

    private fun from(start: Int) {
        val text = view?.text?.toString() ?: return
        val pieces = pieces(text, start, TextToSpeech.getMaxSpeechInputLength() - 100)
        if (pieces.isEmpty()) return finished()
        tts.language = locale(language)
        pieces.forEachIndexed { i, (at, piece) ->
            val id = "$at:" + if (i == pieces.lastIndex) "last" else "$i"
            tts.speak(piece, if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null, id)
        }
        state = State.SPEAKING
    }

    /** The voice for a language: its own, else Hindi for Marathi, else the device's. */
    private fun locale(language: String?): Locale {
        val base = language?.lowercase()?.substringBefore('-')?.substringBefore('_')?.takeIf { it.isNotEmpty() } ?: return Locale.getDefault()
        val own = Locale.forLanguageTag(base)
        if (tts.isLanguageAvailable(own) >= TextToSpeech.LANG_AVAILABLE) return own
        if (base == "mr" && tts.isLanguageAvailable(Locale.forLanguageTag("hi")) >= TextToSpeech.LANG_AVAILABLE) return Locale.forLanguageTag("hi")
        return Locale.getDefault()
    }

    private fun paint(range: IntRange) {
        val text = view?.text as? Spannable ?: return
        if (range.last >= text.length) return
        text.setSpan(underline, range.first, range.last + 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        word = range
        view?.bringPointIntoView(range.first)
    }

    /** Reading has ended, by reaching the end or being stopped. A pause is not an end: the word stays
     *  underlined, to resume from. */
    private fun finished() {
        (view?.text as? Spannable)?.removeSpan(underline)
        state = State.IDLE
        view = null
        word = null
    }

    companion object {
        /** The text from `start`, in pieces of at most `limit` characters that end at a sentence or a
         *  space where they can, each with its offset in the whole text. Blank text gives none. */
        fun pieces(text: String, start: Int, limit: Int): List<Pair<Int, String>> {
            val out = mutableListOf<Pair<Int, String>>()
            var at = start.coerceIn(0, text.length)
            while (at < text.length) {
                var end = minOf(text.length, at + limit)
                if (end < text.length) {
                    val cut = maxOf(text.lastIndexOf(". ", end), text.lastIndexOf('\n', end))
                    end = if (cut > at) cut + 1 else text.lastIndexOf(' ', end).takeIf { it > at } ?: end
                }
                val piece = text.substring(at, end)
                if (piece.isNotBlank()) out += at to piece
                at = end
            }
            return out
        }
    }
}
