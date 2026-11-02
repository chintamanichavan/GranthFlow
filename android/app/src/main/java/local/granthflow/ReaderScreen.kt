// A file opened from the shelf: one reader per kind, as on the Mac and iPhone. The library keeps
// where reading stopped and how each book is set; edits to a note or a text file are written back
// when it is left. A passage in a book or a note's preview is marked from the menu over it; the
// pencil lists this file's marks and notes.
package local.granthflow

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** The file's bytes and kind, read once; then the reader for its kind. [start] is a mark to go to,
 *  chosen in the library. */
@Composable
fun ReaderScreen(path: String, library: Library, store: MarkStore, start: GoTo?, onBack: () -> Unit) {
    val file = File(path)
    val title = file.nameWithoutExtension
    val loaded by produceState<Result<Pair<ByteArray, String>>?>(null, path) {
        value = withContext(Dispatchers.IO) { runCatching { file.readBytes().let { it to Engine.detectKind(it, file.name) } } }
    }
    val result = loaded ?: return Box(Modifier.fillMaxSize().background(Theme.paper().window), Alignment.Center) { CircularProgressIndicator() }
    val (data, kind) = result.getOrElse { return Unreadable(title, "The file could not be read. It may have been moved or deleted.", onBack) }
    LaunchedEffect(path) { library.recordOpened(path, kind) }

    var goTo by remember { mutableStateOf(start) }
    var showMarks by remember { mutableStateOf(false) }
    val marks = Marking(store.marks(path), onMark = { store.add(it, path, kind) }, goTo = goTo, list = {
        IconButton(onClick = { showMarks = true }, modifier = Modifier.testTag("marksButton")) {
            Icon(Icons.Filled.Edit, contentDescription = "Marks and notes")
        }
    })
    if (showMarks) {
        MarksSheet(store, path, data, kind, onDismiss = { showMarks = false }) { mark ->
            showMarks = false
            goTo = GoTo(mark.target, mark.quote, (goTo?.serial ?: 0) + 1)
        }
    }
    when (kind) {
        "epub" -> EpubReader(path, data, library, title, marks, onBack)
        "pdf" -> PdfReader(path, library, title, onBack)
        "markdown" -> TextReader(file, String(data), markdown = true, title, marks, onBack)
        "text" -> TextReader(file, String(data), markdown = false, title, null, onBack)
        else -> HexReader(file.name, data, title, onBack)
    }
}

/** What a reader needs to mark: this file's marks, where to send a new one, the mark to go to, and
 *  the button that lists them. */
private class Marking(val marks: List<Mark>, val onMark: (Selection) -> Unit, val goTo: GoTo?, val list: @Composable () -> Unit)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderBar(title: String, palette: Palette, onBack: () -> Unit, middle: (@Composable () -> Unit)? = null,
                      actions: @Composable () -> Unit = {}) {
    TopAppBar(
        actions = { actions() },
        title = { middle?.invoke() ?: Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Library") }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window, titleContentColor = palette.label,
                                                   navigationIconContentColor = palette.accent, actionIconContentColor = palette.accent),
    )
}

/** One chapter at a time, set on paper. The bottom bar turns chapters and lists them all; Aa sets
 *  the type, column and paper for this book. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EpubReader(path: String, data: ByteArray, library: Library, title: String, marking: Marking, onBack: () -> Unit) {
    val name = File(path).name
    val context = LocalContext.current
    // This book's own settings, else the latest choice made for any book.
    var settings by remember { mutableStateOf(library.entry(path)?.settings ?: ReadingDefaults.load(context)) }
    var showSettings by remember { mutableStateOf(false) }
    val palette = settings.palette(isSystemInDarkTheme())
    val chapters by produceState(emptyList<EpubChapter>(), path) {
        value = withContext(Dispatchers.IO) { EpubChapter.parse(Engine.run("chapters", data = data, name = name, kind = "epub").output) }
    }
    var index by rememberSaveable { mutableIntStateOf(-1) }
    var listing by remember { mutableStateOf(false) }
    val goTo = marking.goTo

    LaunchedEffect(chapters) {
        if (chapters.isNotEmpty() && index < 0) {
            val at = goTo?.target ?: library.entry(path)?.position
            index = chapters.indexOfFirst { it.number == at }.coerceAtLeast(0)
        }
    }
    LaunchedEffect(goTo) {                                   // a mark chosen in the marks sheet
        chapters.indexOfFirst { it.number == goTo?.target }.takeIf { it >= 0 }?.let { index = it }
    }
    // The chapter on show and its text, read by the engine off the main thread.
    var text by remember { mutableStateOf<Pair<EpubChapter, String>?>(null) }
    LaunchedEffect(chapters, index) {
        val chapter = chapters.getOrNull(index) ?: return@LaunchedEffect
        text = chapter to withContext(Dispatchers.IO) { Engine.run("text", listOf("${chapter.number}"), data, name, "epub").output }
        library.recordPosition(path, chapter.number, chapters.size)
    }
    val page = remember(text, palette) { text?.let { (c, body) -> ReadingStyle.chapter(body, c.number, c.title, palette) } }
    if (showSettings) {
        ModalBottomSheet(onDismissRequest = { showSettings = false }) {
            TypeSettingsPanel(settings) {
                settings = it
                ReadingDefaults.save(context, it)
                library.recordSettings(path, it)
            }
        }
    }

    SystemBarsFor(palette)
    Scaffold(
        containerColor = palette.window,
        topBar = {
            ReaderBar(title, palette, onBack) {
                marking.list()
                TextButton(onClick = { showSettings = true }, modifier = Modifier.testTag("typeSettings")) {
                    Text("Aa", fontFamily = FontFamily.Serif, fontSize = 18.sp, color = palette.accent)
                }
            }
        },
        bottomBar = {
            BottomAppBar(containerColor = palette.window, contentColor = palette.accent) {
                IconButton(onClick = { index -= 1 }, enabled = index > 0, modifier = Modifier.testTag("previousChapter")) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous chapter")
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    TextButton(onClick = { listing = true }, colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
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
        val (chapter, _) = text ?: return@Scaffold
        PaperText(
            page ?: "", palette, settings, Modifier.padding(padding).fillMaxSize(), page = chapter.number,
            paints = marking.marks.filter { it.target == chapter.number }.map { it.paint },
            reveal = goTo?.takeIf { it.target == chapter.number },
            onMark = { a, b -> page?.let { marking.onMark(Selection(it.substring(a, b), chapter.number, chapter.name)) } },
        )
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

/** A note or a text file, edited in place. A note can also be read set as a page, and marked there. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TextReader(file: File, initial: String, markdown: Boolean, title: String, marking: Marking?, onBack: () -> Unit) {
    var text by rememberSaveable(file.path) { mutableStateOf(initial) }
    val goTo = marking?.goTo
    // Marks are made, and shown, in the preview; going to one shows it.
    var showPreview by rememberSaveable { mutableStateOf(goTo != null) }
    LaunchedEffect(goTo) { if (goTo != null) showPreview = true }
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
            }) { marking?.list?.invoke() }
        },
    ) { padding ->
        if (showPreview && marking != null) {
            val preview = remember(text, palette) { MarkdownRenderer.render(text, palette) }
            PaperText(
                preview, palette, ReadingSettings(look = ReadingSettings.Look.PAPER), Modifier.padding(padding).fillMaxSize(),
                paints = marking.marks.map { it.paint }, reveal = goTo,
                // A mark is on a line of the source: its passage is looked for from there.
                revealFrom = goTo?.let { MarkdownRenderer.character(it.target, preview) } ?: 0,
                onMark = { a, b ->
                    val line = MarkdownRenderer.sourceLine(a, preview) ?: return@PaperText
                    marking.onMark(Selection(preview.substring(a, b), line, "Line $line"))
                },
                tag = "preview",
            )
        } else {
            BasicTextField(
                value = text, onValueChange = { text = it },
                textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp, lineHeight = 22.sp, color = palette.label),
                modifier = Modifier.padding(padding).fillMaxSize().padding(16.dp).testTag("editor"),
            )
        }
    }
}

/** This file's marks, in reading order: choose one to go to it, colour it, note it or remove it.
 *  Share sends them all as a Markdown file, as the Mac saves them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MarksSheet(store: MarkStore, path: String, data: ByteArray, kind: String, onDismiss: () -> Unit, choose: (Mark) -> Unit) {
    val context = LocalContext.current
    val marks = store.marks(path)
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Marks", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (marks.isNotEmpty()) {
                IconButton(onClick = { share(context, path, data, kind, marks) }, modifier = Modifier.testTag("exportMarks")) {
                    Icon(Icons.Filled.Share, contentDescription = "Share these marks and notes as Markdown")
                }
            }
        }
        if (marks.isEmpty()) {
            Text("Nothing marked yet. Select a passage and choose Mark from the menu over it.",
                 color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(24.dp))
        }
        LazyColumn(Modifier.padding(bottom = 24.dp)) {
            items(marks, key = { it.id }) { mark ->
                MarkRow(mark, caption = mark.place, choose = { choose(mark) }, store = store)
                HorizontalDivider(Modifier.padding(horizontal = 24.dp))
            }
        }
    }
}

/** Writes the marks as Markdown and hands the file to whichever app the reader picks. */
private fun share(context: android.content.Context, path: String, data: ByteArray, kind: String, marks: List<Mark>) {
    val meta = if (kind == "epub") Engine.run("meta", data = data, name = File(path).name, kind = kind).output else ""
    val title = EpubChapter.meta("Title", meta) ?: File(path).nameWithoutExtension
    val file = File(context.cacheDir, "exports").apply { mkdirs() }.let { File(it, MarkExport.fileName(title)) }
    file.writeText(MarkExport.markdown(title, EpubChapter.meta("Author", meta) ?: "", marks))
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val send = Intent(Intent.ACTION_SEND).setType("text/markdown").putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_SUBJECT, file.name).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, "Share marks"))
}

/** The status and navigation bars' icons, dark on light paper and light on dark, while the page is on show. */
@Composable
private fun SystemBarsFor(palette: Palette) {
    val view = LocalView.current
    val light = palette.window.luminance() > 0.4f
    DisposableEffect(light) {
        val window = (view.context as Activity).window
        val bars = WindowCompat.getInsetsController(window, view)
        val was = bars.isAppearanceLightStatusBars
        bars.isAppearanceLightStatusBars = light
        bars.isAppearanceLightNavigationBars = light
        onDispose {
            bars.isAppearanceLightStatusBars = was
            bars.isAppearanceLightNavigationBars = was
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
