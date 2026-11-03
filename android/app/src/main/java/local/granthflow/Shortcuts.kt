// Android's counterpart of the Shortcuts app's actions. A long press on GranthFlow's icon offers the
// books part-way through, each opening at its place, and Marks and Search every file (those two are
// in res/xml/shortcuts.xml). Adding files is Share, which the manifest already takes.
package local.granthflow

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

object Shortcuts {
    const val OPEN = "local.granthflow.OPEN"
    const val MARKS = "local.granthflow.MARKS"
    const val SEARCH = "local.granthflow.SEARCH"

    /** Puts the books part-way through, most recent first, on the icon's menu. */
    fun update(context: Context, library: Library) {
        val room = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context) - 2        // Marks and Search
        val books = library.continueReading.take(room.coerceIn(0, 3)).mapIndexed { rank, entry ->
            val title = title(entry)
            ShortcutInfoCompat.Builder(context, entry.path)
                .setShortLabel(title)
                .setLongLabel("Continue $title")
                .setIcon(IconCompat.createWithResource(context, R.drawable.shortcut_book))
                .setIntent(Intent(OPEN, null, context, MainActivity::class.java).putExtra("open", entry.path))
                .setRank(rank)
                .build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(context, books)
    }

    /** A book's own title; a file's name otherwise. */
    private fun title(entry: LibraryEntry): String {
        if (entry.kind != "epub") return entry.stem
        val data = runCatching { entry.file.readBytes() }.getOrNull() ?: return entry.stem
        return EpubChapter.meta("Title", Engine.run("meta", data = data, name = entry.name, kind = "epub").output) ?: entry.stem
    }
}
