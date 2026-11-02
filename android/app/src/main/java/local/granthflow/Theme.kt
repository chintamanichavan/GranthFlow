// The colours of paper and ink, as the Mac and iPhone apps use them: warm paper by day, warm dark
// paper by night, and a quieter grey for the library.
package local.granthflow

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

data class Palette(val window: Color, val label: Color, val secondary: Color, val accent: Color)

object Theme {
    val paper = Palette(Color(0xFFF7F0E1), Color(0xFF32291C), Color(0xFF7B6D58), Color(0xFF3B49DF))
    val paperDark = Palette(Color(0xFF1F1B15), Color(0xFFE9E0CD), Color(0xFFA89A82), Color(0xFF8FA0FF))
    val sepia = Palette(Color(0xFFEBD9B4), Color(0xFF3E2C17), Color(0xFF7A5F3C), Color(0xFF8A4B14))
    /** Warm dark paper with light ink, for reading at night. */
    val night = Palette(Color(0xFF1F1B15), Color(0xFFE2D8C4), Color(0xFFA89A82), Color(0xFF8FA0FF))
    val library = Palette(Color(0xFFF5F4F0), Color(0xFF1C1C1E), Color(0xFF6B6B70), Color(0xFF3B49DF))
    val libraryDark = Palette(Color(0xFF1C1C1E), Color(0xFFF2F2F4), Color(0xFFA0A0A6), Color(0xFF8FA0FF))

    @Composable fun paper() = if (isSystemInDarkTheme()) paperDark else paper
    @Composable fun library() = if (isSystemInDarkTheme()) libraryDark else library
}

@Composable
fun GranthFlowTheme(content: @Composable () -> Unit) {
    val p = Theme.library()
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = p.accent, background = p.window, surface = p.window, onBackground = p.label, onSurface = p.label)
    } else {
        lightColorScheme(primary = p.accent, background = p.window, surface = p.window, onBackground = p.label, onSurface = p.label)
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
