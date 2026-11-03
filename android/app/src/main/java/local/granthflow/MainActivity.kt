// GranthFlow on Android: a shelf of the files in the app's own folder; the engine reads them.
// Files arrive from +, "Open with" and Share. The icon's shortcuts, and tests, start on a file with
// the extra "open", a path, or on Marks or Search.
package local.granthflow

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.IntentCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val app get() = application as GranthFlowApp
    /** The file on show, and a mark in it to go to; null shows the library. */
    private var open by mutableStateOf<Opening?>(null)
    private val view = LibraryView()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) follow(intent) else {
            open = savedInstanceState.getString("open")?.let { Opening(it) }
            view.showMarks = savedInstanceState.getBoolean("marks")
            view.searching = savedInstanceState.getBoolean("searching")
        }
        setContent {
            GranthFlowTheme {
                val o = open
                if (o == null) {
                    LibraryScreen(app.library, app.marks, view, onOpen = { open = it }, onAdd = { uris -> add(uris) {} })
                } else {
                    BackHandler { open = null }
                    key(o) { ReaderScreen(o.path, app.library, app.marks, o.goTo, onBack = { open = null }) }      // a new file starts afresh
                }
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("open", open?.path)
        outState.putBoolean("marks", view.showMarks)
        outState.putBoolean("searching", view.searching)
    }

    /** Leaving the app is when the icon's menu is next seen, so its books are brought up to date then. */
    override fun onPause() {
        super.onPause()
        val context = applicationContext
        lifecycleScope.launch(Dispatchers.IO) { Shortcuts.update(context, app.library) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        follow(intent)
    }

    private fun follow(intent: Intent) {
        intent.getStringExtra("open")?.let { open = Opening(it); return }
        when (intent.action) {
            Shortcuts.MARKS, Shortcuts.SEARCH -> {
                open = null
                view.showMarks = intent.action == Shortcuts.MARKS
                view.searching = intent.action == Shortcuts.SEARCH
                return
            }
        }
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            else -> null
        } ?: return
        add(listOf(uri)) { paths -> paths.firstOrNull()?.let { open = Opening(it) } }
    }

    /** Copies files in and shelves them, off the main thread, then hands over their paths. */
    private fun add(uris: List<Uri>, then: (List<String>) -> Unit) {
        lifecycleScope.launch {
            val paths = withContext(Dispatchers.IO) { Importing.add(uris, contentResolver, app.books, app.library).map { it.path } }
            then(paths)
        }
    }
}

/** A file to open, and the mark in it to go to. */
data class Opening(val path: String, val goTo: GoTo? = null) {
    constructor(mark: Mark) : this(mark.path, GoTo(mark.target, mark.quote))
}
