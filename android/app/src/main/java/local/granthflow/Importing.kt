// Bringing files into GranthFlow: each is copied into the app's own folder and put on the shelf.
// Used by +, and by "Open with" and "Share" from other apps.
package local.granthflow

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File

object Importing {
    /** Copies each file in and shelves it; returns the files as they are now kept. A file already
     *  there with the same name and bytes is shelved again rather than copied twice. */
    fun add(uris: List<Uri>, resolver: ContentResolver, folder: File, library: Library): List<File> {
        val found = uris.mapNotNull { uri ->
            val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return@mapNotNull null
            val target = place(displayName(uri, resolver), folder, bytes)
            if (!target.exists()) target.writeBytes(bytes)
            target to Engine.detectKind(bytes, target.name)
        }
        library.add(found)
        return found.map { it.first }
    }

    /** "Book.epub", or "Book 2.epub" and on when a different file already has the name. */
    fun place(name: String, folder: File, bytes: ByteArray): File {
        val stem = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "")
        var candidate = File(folder, name)
        var n = 2
        while (candidate.exists() && !candidate.readBytes().contentEquals(bytes)) {
            candidate = File(folder, if (ext.isEmpty()) "$stem $n" else "$stem $n.$ext")
            n += 1
        }
        return candidate
    }

    private fun displayName(uri: Uri, resolver: ContentResolver): String {
        if (uri.scheme == "file") return File(uri.path!!).name
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { return it }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Untitled"
    }
}
