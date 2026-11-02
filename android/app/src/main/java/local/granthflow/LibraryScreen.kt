// The shelf: every file in GranthFlow's folder, most recent first, each as a cover with its title
// and how far reading has got. + brings files in; a long press removes one. Marks lists every
// passage marked, in any file; choosing one opens its file there. The magnifying glass searches
// every file on the shelf.
package local.granthflow

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(library: Library, store: MarkStore, onOpen: (Opening) -> Unit, onAdd: (List<Uri>) -> Unit) {
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) onAdd(uris) }
    val palette = Theme.library()
    val entries = library.recent
    var showMarks by rememberSaveable { mutableStateOf(false) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    val corpus = remember { Corpus() }
    val results by produceState(emptyList<Pair<LibraryEntry, List<FindHit>>>(), query) {
        if (query.isEmpty()) return@produceState run { value = emptyList() }
        delay(250)                                               // a word typed, not each letter
        value = withContext(Dispatchers.IO) { synchronized(corpus) { corpus.search(query, entries) } }
    }
    Scaffold(
        containerColor = palette.window,
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        if (searching) {
                            TextField(
                                value = query, onValueChange = { query = it }, singleLine = true, placeholder = { Text("Search every file") },
                                colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent),
                                modifier = Modifier.fillMaxWidth().testTag("searchField"),
                            )
                        } else {
                            Text("Library")
                        }
                    },
                    actions = {
                        IconButton(onClick = { searching = !searching; query = "" }, modifier = Modifier.testTag("search")) {
                            Icon(if (searching) Icons.Filled.Close else Icons.Filled.Search,
                                 contentDescription = if (searching) "Stop searching" else "Search every file")
                        }
                        IconButton(onClick = { pick.launch(arrayOf("*/*")) }, modifier = Modifier.testTag("add")) {
                            Icon(Icons.Filled.Add, contentDescription = "Add books and documents")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window),
                )
                PrimaryTabRow(selectedTabIndex = if (showMarks) 1 else 0, containerColor = palette.window) {
                    Tab(selected = !showMarks, onClick = { showMarks = false }, text = { Text("Books & Files") })
                    Tab(selected = showMarks, onClick = { showMarks = true }, text = { Text("Marks") }, modifier = Modifier.testTag("marksTab"))
                }
            }
        },
    ) { padding ->
        if (query.isNotEmpty()) {
            if (results.isEmpty()) {
                Box(Modifier.padding(padding).fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("No matches for “$query”.", color = palette.secondary)
                }
            } else {
                LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                    results.forEach { (entry, hits) ->
                        item(key = entry.path) {
                            Text(entry.name, style = MaterialTheme.typography.titleSmall, color = palette.secondary,
                                 modifier = Modifier.padding(start = 24.dp, top = 16.dp, bottom = 4.dp))
                        }
                        items(hits, key = { entry.path + "#" + it.id }) { hit ->
                            HitRow(hit, Modifier.clickable { onOpen(Opening(entry.path, GoTo(hit.target, query))) }
                                .testTag("searchHit.${entry.name}.${hit.id}"))
                        }
                    }
                }
            }
        } else if (showMarks) {
            val marks = store.all
            if (marks.isEmpty()) {
                Box(Modifier.padding(padding).fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("No marks yet.\nSelect a passage in any book or note and choose Mark. It will be kept here.",
                         textAlign = TextAlign.Center, color = palette.secondary)
                }
            } else {
                LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                    items(marks, key = { it.id }) { mark ->
                        MarkRow(mark, caption = "${mark.name}  ·  ${mark.place}", choose = { onOpen(Opening(mark)) }, store = store)
                        HorizontalDivider(Modifier.padding(horizontal = 24.dp))
                    }
                }
            }
        } else if (entries.isEmpty()) {
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
                    ShelfItem(entry, palette, onOpen = { onOpen(Opening(entry.path)) }, onRemove = {
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
    val context = LocalContext.current
    // Made from the file itself, off the main thread; made again when the file changes on disk.
    val face by produceState<ShelfFace?>(null, entry.path, entry.file.lastModified()) {
        value = withContext(Dispatchers.IO) { Cover.face(entry) }
    }
    Column(
        Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }).testTag("shelf.${entry.name}"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        CoverView(face?.art)
        entry.progress?.takeIf { it < 1f }?.let { p ->
            Box(Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(palette.secondary.copy(alpha = 0.2f))) {
                Box(Modifier.fillMaxWidth(p).height(3.dp).background(palette.accent))
            }
        }
        Text(face?.title ?: entry.stem, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(face?.let { Cover.subtitle(it, entry, context) } ?: " ", style = MaterialTheme.typography.bodySmall,
             color = palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; onRemove() })
        }
    }
}
