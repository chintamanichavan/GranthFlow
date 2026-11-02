// The app: where its files, library and marks live. Books and documents are copied into `books`,
// the app's own folder; the library remembers each one and where reading stopped.
package local.granthflow

import android.app.Application
import android.system.Os
import java.io.File

class GranthFlowApp : Application() {
    lateinit var library: Library
        private set
    lateinit var marks: MarkStore
        private set
    val books: File get() = File(filesDir, "books").apply { mkdirs() }

    override fun onCreate() {
        super.onCreate()
        // The engine stages each file in the temporary directory, which Android leaves unset.
        Os.setenv("TMPDIR", cacheDir.path, true)
        library = Library(File(filesDir, "library.json"))
        marks = MarkStore(File(filesDir, "marks.json"))
    }
}
