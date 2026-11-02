// The shelf: every file in GranthFlow's folder, most recent first, each as a cover with its title
// and how far reading has got. + brings files in; a long press removes one.
package local.granthflow

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(library: Library, onOpen: (String) -> Unit, onAdd: (List<Uri>) -> Unit) {
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) onAdd(uris) }
    val palette = Theme.library()
    val entries = library.recent
    Scaffold(
        containerColor = palette.window,
        topBar = {
            TopAppBar(
                title = { Text("Library") },
                actions = {
                    IconButton(onClick = { pick.launch(arrayOf("*/*")) }, modifier = Modifier.testTag("add")) {
                        Icon(Icons.Filled.Add, contentDescription = "Add books and documents")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window),
            )
        },
    ) { padding ->
        if (entries.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                Text("Nothing here yet.\nAdd books and documents with +.", textAlign = TextAlign.Center, color = palette.secondary)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(120.dp),
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                items(entries, key = { it.path }) { entry ->
                    ShelfItem(entry, palette, onOpen = { onOpen(entry.path) }, onRemove = {
                        entry.file.delete()
                        library.forget(entry.path)
                    })
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ShelfItem(entry: LibraryEntry, palette: Palette, onOpen: () -> Unit, onRemove: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    // A book's own title and author, read from the book; other files go by their name.
    val heading by produceState(entry.stem to "", entry.path) {
        if (entry.kind == "epub") value = withContext(Dispatchers.IO) {
            val meta = Engine.run("meta", data = entry.file.readBytes(), name = entry.name, kind = "epub").output
            (EpubChapter.meta("Title", meta) ?: entry.stem) to (EpubChapter.meta("Author", meta) ?: "")
        }
    }
    Column(
        Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }).testTag("shelf.${entry.name}"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Cover(heading.first, entry.kind)
        entry.progress?.takeIf { it < 1f }?.let { LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth()) }
        Text(heading.first, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(entry.progressText ?: heading.second.ifEmpty { kindLabel(entry.kind) }, style = MaterialTheme.typography.bodySmall,
             color = palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; onRemove() })
        }
    }
}

/** A plain cloth cover, coloured by kind, with the title set on it. */
@Composable
private fun Cover(title: String, kind: String) {
    val cloth = when (kind) {
        "epub" -> Color(0xFF1D2C73)
        "pdf" -> Color(0xFF7A2E1F)
        "markdown" -> Color(0xFF27615A)
        "text" -> Color(0xFF5A4F3C)
        else -> Color(0xFF3A3A40)
    }
    Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).clip(RoundedCornerShape(3.dp)).background(cloth).padding(12.dp)) {
        Column {
            Spacer(Modifier.height(18.dp))
            Text(title, color = Color(0xFFF2EAD8), fontFamily = FontFamily.Serif, fontSize = 17.sp, lineHeight = 21.sp,
                 maxLines = 5, overflow = TextOverflow.Ellipsis)
        }
        Text(kindLabel(kind).uppercase(), color = Color(0xB3F2EAD8), fontSize = 9.sp, letterSpacing = 1.5.sp,
             modifier = Modifier.align(Alignment.BottomStart))
    }
}

/** What to call a kind of file on the shelf. */
fun kindLabel(kind: String) = when (kind) {
    "epub" -> "Book"
    "pdf" -> "Document"
    "markdown" -> "Note"
    "text" -> "Text"
    else -> "Data"
}
