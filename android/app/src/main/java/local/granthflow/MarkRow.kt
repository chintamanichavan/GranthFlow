// One mark: its colour, the passage and where it is, and the reader's note, which can be added or
// edited in place. Used in a file's marks sheet and in the library's list of every mark.
package local.granthflow

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun MarkRow(mark: Mark, caption: String, choose: () -> Unit, store: MarkStore) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(mark.note) }
    var colours by remember { mutableStateOf(false) }
    val tag = mark.quote.take(24)
    val finish = {
        if (editing) {
            editing = false
            store.setNote(mark, draft)
        }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 10.dp).testTag("mark.$tag")) {
        Box {
            Box(Modifier.width(6.dp).height(38.dp).clip(RoundedCornerShape(2.dp)).background(Color(mark.colour.argb))
                    .clickable { colours = true }.testTag("markColour"))
            DropdownMenu(expanded = colours, onDismissRequest = { colours = false }) {
                MarkColour.entries.forEach { c ->
                    DropdownMenuItem(
                        text = { Text(c.title) },
                        leadingIcon = { Box(Modifier.size(14.dp).clip(CircleShape).background(Color(c.argb))) },
                        onClick = { colours = false; store.setColour(mark, c) },
                        modifier = Modifier.testTag("colour.${c.title}"),
                    )
                }
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Column(Modifier.fillMaxWidth().clickable(onClick = choose)) {
                Text(if (mark.kind == "binary") mark.quote else "“${mark.quote}”", fontFamily = FontFamily.Serif, fontSize = 15.sp,
                     maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(caption, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (editing) {
                val focus = remember { FocusRequester() }
                var focused by remember { mutableStateOf(false) }
                OutlinedTextField(
                    value = draft, onValueChange = { draft = it }, placeholder = { Text("Your note") },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { finish() }),
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp).focusRequester(focus).testTag("noteField")
                        .onFocusChanged {                                         // tapping away keeps the note
                            if (focused && !it.isFocused) finish()
                            focused = it.isFocused
                        },
                )
                LaunchedEffect(Unit) { focus.requestFocus() }
            } else if (mark.note.isNotEmpty()) {
                Text(mark.note, fontStyle = FontStyle.Italic, color = MaterialTheme.colorScheme.onSurfaceVariant,
                     modifier = Modifier.padding(top = 4.dp).testTag("note.$tag"))
            }
        }
        IconButton(onClick = { draft = mark.note; editing = true }, modifier = Modifier.testTag("addNote")) {
            Icon(Icons.Filled.Edit, contentDescription = if (mark.note.isEmpty()) "Add a note" else "Edit the note",
                 tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        IconButton(onClick = { store.remove(mark) }) {
            Icon(Icons.Filled.Close, contentDescription = "Remove this mark", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
