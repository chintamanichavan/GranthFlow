// How a book is set for reading: text size, line spacing, column width and theme, as on the Mac and
// iPhone. Kept per book in the library; a book opened for the first time starts with the reader's
// latest choice. The Aa sheet changes them.
package local.granthflow

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

data class ReadingSettings(
    val size: Double = 17.0,
    val spacing: Spacing = Spacing.NORMAL,
    val width: Width = Width.NORMAL,
    val look: Look = Look.AUTO,
) {
    enum class Spacing(val title: String, val lineHeight: Float) { TIGHT("Tight", 1.25f), NORMAL("Normal", 1.45f), LOOSE("Loose", 1.7f) }
    enum class Width(val title: String, val base: Float) { NARROW("Narrow", 460f), NORMAL("Normal", 560f), WIDE("Wide", 700f) }
    enum class Look(val title: String) { AUTO("Auto"), PAPER("Paper"), SEPIA("Sepia"), NIGHT("Night") }

    fun larger() = copy(size = minOf(size + 1, SIZES.endInclusive))
    fun smaller() = copy(size = maxOf(size - 1, SIZES.start))

    /** The widest the column grows, scaled with the text so a line keeps about the same number of words. */
    val measure: Dp get() = (width.base * size / 17).toFloat().dp

    fun palette(systemDark: Boolean) = when (look) {
        Look.AUTO -> if (systemDark) Theme.paperDark else Theme.paper
        Look.PAPER -> Theme.paper
        Look.SEPIA -> Theme.sepia
        Look.NIGHT -> Theme.night
    }

    /** As the Mac and iPhone write it: lower-case names. */
    fun toJson(): JSONObject = JSONObject().put("size", size).put("spacing", spacing.name.lowercase())
        .put("width", width.name.lowercase()).put("look", look.name.lowercase())

    companion object {
        val SIZES = 13.0..28.0

        /** Missing or unknown fields take their defaults, so older and newer libraries both load. */
        fun fromJson(o: JSONObject) = ReadingSettings(
            size = o.optDouble("size", 17.0).coerceIn(SIZES),
            spacing = Spacing.entries.firstOrNull { it.name.equals(o.optString("spacing"), true) } ?: Spacing.NORMAL,
            width = Width.entries.firstOrNull { it.name.equals(o.optString("width"), true) } ?: Width.NORMAL,
            look = Look.entries.firstOrNull { it.name.equals(o.optString("look"), true) } ?: Look.AUTO,
        )
    }
}

/** The choice a new book starts with: the last one made. */
object ReadingDefaults {
    private const val KEY = "readingSettings"

    fun load(context: Context): ReadingSettings = context.getSharedPreferences("granthflow", Context.MODE_PRIVATE).getString(KEY, null)
        ?.let { runCatching { ReadingSettings.fromJson(JSONObject(it)) }.getOrNull() } ?: ReadingSettings()

    fun save(context: Context, settings: ReadingSettings) {
        context.getSharedPreferences("granthflow", Context.MODE_PRIVATE).edit().putString(KEY, settings.toJson().toString()).apply()
    }
}

/** The Aa sheet: text size, line spacing, column width and theme for the book on show. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TypeSettingsPanel(settings: ReadingSettings, onChange: (ReadingSettings) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { onChange(settings.smaller()) }, enabled = settings.size > ReadingSettings.SIZES.start,
                           modifier = Modifier.testTag("textSmaller")) { Text("A", fontFamily = FontFamily.Serif, fontSize = 14.sp) }
            Text("${settings.size.toInt()} pt", Modifier.weight(1f).testTag("textSize"), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                 color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = { onChange(settings.larger()) }, enabled = settings.size < ReadingSettings.SIZES.endInclusive,
                           modifier = Modifier.testTag("textLarger")) { Text("A", fontFamily = FontFamily.Serif, fontSize = 22.sp) }
        }
        Choice("Line spacing", ReadingSettings.Spacing.entries, settings.spacing, { it.title }) { onChange(settings.copy(spacing = it)) }
        Choice("Column", ReadingSettings.Width.entries, settings.width, { it.title }) { onChange(settings.copy(width = it)) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            ReadingSettings.Look.entries.forEach { look -> LookSwatch(look, settings.look == look) { onChange(settings.copy(look = look)) } }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> Choice(title: String, options: List<T>, chosen: T, label: (T) -> String, choose: (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            options.forEachIndexed { i, o ->
                SegmentedButton(selected = o == chosen, onClick = { choose(o) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                                modifier = Modifier.testTag("$title.${label(o)}")) { Text(label(o)) }
            }
        }
    }
}

@Composable
private fun LookSwatch(look: ReadingSettings.Look, chosen: Boolean, choose: () -> Unit) {
    Column(Modifier.clickable(onClick = choose).testTag("look.${look.title}"), horizontalAlignment = Alignment.CenterHorizontally) {
        val paper = Theme.paper
        Box(
            Modifier.size(44.dp).clip(CircleShape)
                .background(if (look == ReadingSettings.Look.AUTO) paper.window else ReadingSettings(look = look).palette(false).window)
                .drawBehind {
                    // Auto is half light paper, half dark: it follows the system's appearance.
                    if (look == ReadingSettings.Look.AUTO) drawRect(Theme.night.window, Offset(size.width / 2, 0f), Size(size.width / 2, size.height))
                }
                .border(if (chosen) BorderStroke(2.5.dp, MaterialTheme.colorScheme.primary) else BorderStroke(1.dp, Color(0x26808080)), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("Aa", fontFamily = FontFamily.Serif, fontSize = 13.sp, color = if (look == ReadingSettings.Look.NIGHT) Theme.night.label else paper.label)
        }
        Text(look.title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
             modifier = Modifier.padding(top = 4.dp).width(56.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}
