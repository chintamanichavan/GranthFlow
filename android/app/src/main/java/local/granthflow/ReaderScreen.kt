// A file opened from the shelf: one reader per kind, as on the Mac and iPhone. The library keeps
// where reading stopped; edits to a note or a text file are written back when it is left.
package local.granthflow

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/** The file's bytes and kind, read once; then the reader for its kind. */
@Composable
fun ReaderScreen(path: String, library: Library, onBack: () -> Unit) {
    val file = File(path)
    val title = file.nameWithoutExtension
    val loaded by produceState<Result<Pair<ByteArray, String>>?>(null, path) {
        value = withContext(Dispatchers.IO) { runCatching { file.readBytes().let { it to Engine.detectKind(it, file.name) } } }
    }
    val result = loaded ?: return Box(Modifier.fillMaxSize().background(Theme.paper().window), Alignment.Center) { CircularProgressIndicator() }
    val (data, kind) = result.getOrElse { return Unreadable(title, "The file could not be read. It may have been moved or deleted.", onBack) }
    LaunchedEffect(path) { library.recordOpened(path, kind) }
    when (kind) {
        "epub" -> EpubReader(path, data, library, title, onBack)
        "pdf" -> PdfReader(path, library, title, onBack)
        "markdown" -> TextReader(file, String(data), markdown = true, title, onBack)
        "text" -> TextReader(file, String(data), markdown = false, title, onBack)
        else -> HexReader(file.name, data, title, onBack)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderBar(title: String, palette: Palette, onBack: () -> Unit, middle: (@Composable () -> Unit)? = null) {
    TopAppBar(
        title = { middle?.invoke() ?: Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Library") }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window, titleContentColor = palette.label,
                                                   navigationIconContentColor = palette.accent),
    )
}

/** One chapter at a time, set on paper. The bottom bar turns chapters and lists them all. */
@Composable
private fun EpubReader(path: String, data: ByteArray, library: Library, title: String, onBack: () -> Unit) {
    val name = File(path).name
    val palette = Theme.paper()
    val chapters by produceState(emptyList<EpubChapter>(), path) {
        value = withContext(Dispatchers.IO) { EpubChapter.parse(Engine.run("chapters", data = data, name = name, kind = "epub").output) }
    }
    var index by rememberSaveable { mutableIntStateOf(-1) }
    var page by remember { mutableStateOf(AnnotatedString("")) }
    var listing by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()

    LaunchedEffect(chapters) {
        if (chapters.isNotEmpty() && index < 0) index = chapters.indexOfFirst { it.number == library.entry(path)?.position }.coerceAtLeast(0)
    }
    LaunchedEffect(chapters, index, palette) {
        val chapter = chapters.getOrNull(index) ?: return@LaunchedEffect
        val text = withContext(Dispatchers.IO) { Engine.run("text", listOf("${chapter.number}"), data, name, "epub").output }
        page = ReadingStyle.chapter(text, chapter.number, chapter.title, palette)
        scroll.scrollTo(0)
        library.recordPosition(path, chapter.number, chapters.size)
    }

    Scaffold(
        containerColor = palette.window,
        topBar = { ReaderBar(title, palette, onBack) },
        bottomBar = {
            BottomAppBar(containerColor = palette.window) {
                IconButton(onClick = { index -= 1 }, enabled = index > 0, modifier = Modifier.testTag("previousChapter")) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous chapter")
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    TextButton(onClick = { listing = true }) {
                        Text(chapters.getOrNull(index)?.name ?: "Contents", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    DropdownMenu(expanded = listing, onDismissRequest = { listing = false }) {
                        chapters.forEachIndexed { i, c -> DropdownMenuItem(text = { Text(c.name) }, onClick = { index = i; listing = false }) }
                    }
                }
                IconButton(onClick = { index += 1 }, enabled = index + 1 < chapters.size, modifier = Modifier.testTag("nextChapter")) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next chapter")
                }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(scroll), horizontalAlignment = Alignment.CenterHorizontally) {
            SelectionContainer {
                Text(page, Modifier.widthIn(max = 600.dp).padding(horizontal = 24.dp, vertical = 28.dp).testTag("page"))
            }
        }
    }
}

/** Every page of a PDF, drawn by Android's own renderer as it scrolls into view. */
@Composable
private fun PdfReader(path: String, library: Library, title: String, onBack: () -> Unit) {
    val renderer = remember(path) {
        runCatching { PdfRenderer(ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)) }.getOrNull()
    } ?: return Unreadable(title, "Android cannot draw this PDF. It may be damaged, or protected with a password.", onBack)
    // One page can be open at a time, so pages are drawn one after another.
    val lock = remember(path) { Mutex() }
    DisposableEffect(renderer) { onDispose { renderer.close() } }
    val count = renderer.pageCount
    val list = rememberLazyListState(initialFirstVisibleItemIndex = (library.entry(path)?.position ?: 0).coerceIn(0, maxOf(0, count - 1)))
    LaunchedEffect(list) { snapshotFlow { list.firstVisibleItemIndex }.collect { library.recordPosition(path, it, count) } }

    val palette = Theme.paper()
    Scaffold(containerColor = Color(0xFF8E8E93), topBar = { ReaderBar(title, palette, onBack) }) { padding ->
        BoxWithConstraints(Modifier.padding(padding).fillMaxSize()) {
            val width = constraints.maxWidth.coerceAtMost(2400)
            LazyColumn(state = list, modifier = Modifier.fillMaxSize().testTag("pdf")) {
                items(count) { i ->
                    val bitmap by produceState<Bitmap?>(null, i, width) {
                        value = withContext(Dispatchers.IO) {
                            lock.withLock {
                                renderer.openPage(i).use { p ->
                                    Bitmap.createBitmap(width, (width.toFloat() * p.height / p.width).toInt(), Bitmap.Config.ARGB_8888).also {
                                        it.eraseColor(android.graphics.Color.WHITE)
                                        p.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    }
                                }
                            }
                        }
                    }
                    val b = bitmap
                    if (b != null) {
                        Image(b.asImageBitmap(), contentDescription = "Page ${i + 1}", modifier = Modifier.fillMaxWidth().aspectRatio(b.width.toFloat() / b.height))
                    } else {
                        Box(Modifier.fillMaxWidth().aspectRatio(0.77f).background(Color.White))
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
    }
}

/** A note or a text file, edited in place. A note can also be read set as a page. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TextReader(file: File, initial: String, markdown: Boolean, title: String, onBack: () -> Unit) {
    var text by rememberSaveable(file.path) { mutableStateOf(initial) }
    var showPreview by rememberSaveable { mutableStateOf(false) }
    val palette = Theme.paper()
    val latest by rememberUpdatedState(text)
    // Written back when the file is left or the app goes to the background.
    val save = { if (latest != file.readText()) file.writeText(latest) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val watch = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP) save() }
        owner.lifecycle.addObserver(watch)
        onDispose { owner.lifecycle.removeObserver(watch); save() }
    }

    Scaffold(
        containerColor = palette.window,
        topBar = {
            ReaderBar(title, palette, onBack, middle = if (!markdown) null else {
                {
                    SingleChoiceSegmentedButtonRow(Modifier.testTag("mode")) {
                        listOf("Edit", "Preview").forEachIndexed { i, label ->
                            SegmentedButton(selected = showPreview == (i == 1), onClick = { showPreview = i == 1 },
                                            shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(label) }
                        }
                    }
                }
            })
        },
    ) { padding ->
        if (showPreview) {
            Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                SelectionContainer {
                    Text(MarkdownRenderer.render(text, palette), Modifier.widthIn(max = 600.dp).padding(horizontal = 24.dp, vertical = 28.dp).testTag("preview"))
                }
            }
        } else {
            BasicTextField(
                value = text, onValueChange = { text = it },
                textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp, lineHeight = 22.sp, color = palette.label),
                modifier = Modifier.padding(padding).fillMaxSize().padding(16.dp).testTag("editor"),
            )
        }
    }
}

/** A file that could not be shown, and why. */
@Composable
private fun Unreadable(title: String, why: String, onBack: () -> Unit) {
    val palette = Theme.paper()
    Scaffold(containerColor = palette.window, topBar = { ReaderBar(title, palette, onBack) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize().padding(32.dp), Alignment.Center) {
            Text(why, color = palette.secondary, modifier = Modifier.testTag("unreadable"))
        }
    }
}

/** Any other file: its bytes, as the engine's `hex` prints them. */
@Composable
private fun HexReader(name: String, data: ByteArray, title: String, onBack: () -> Unit) {
    val palette = Theme.paper()
    val hex by produceState("", name) { value = withContext(Dispatchers.IO) { Engine.run("hex", data = data, name = name, kind = "binary").output } }
    Scaffold(containerColor = palette.window, topBar = { ReaderBar(title, palette, onBack) }) { padding ->
        SelectionContainer(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).horizontalScroll(rememberScrollState())) {
            Text(hex, Modifier.padding(16.dp).testTag("hex"), fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = palette.label, softWrap = false)
        }
    }
}
