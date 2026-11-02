// Draws a cover. Everything is laid out on a 120 × 168 card, as on the Mac and iPhone, and scaled
// to the width given.
package local.granthflow

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.BoxWithConstraintsScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text as M3Text

/** A cover at the width it is given, or a quiet placeholder while it is made. */
@Composable
fun CoverView(art: CoverArt?, modifier: Modifier = Modifier) {
    BoxWithConstraints(
        modifier.fillMaxWidth().aspectRatio(120f / 168f).shadow(4.dp, RoundedCornerShape(3.dp)).clip(RoundedCornerShape(3.dp)),
    ) {
        val card = Card(this)
        // Cover text is sized on the card; Material's line heights would space it out. Replaced, not
        // merged, since a merge keeps them.
        CompositionLocalProvider(LocalTextStyle provides TextStyle.Default) { Face(art, card) }
    }
}

@Composable
private fun Face(art: CoverArt?, card: Card) {
    when (art) {
        null -> Box(Modifier.fillMaxSize().background(Color(0x1F808080)))
        is CoverArt.Book -> card.Book(art)
        is CoverArt.Picture -> Picture(art)
        is CoverArt.Page -> Page(art)
        is CoverArt.Note -> card.Note(art)
        is CoverArt.Text -> card.Text(art)
        is CoverArt.Bytes -> Bytes(art)
    }
}

/** Lengths on the 120-wide card, at the cover's actual size. */
private class Card(scope: BoxWithConstraintsScope) {
    private val unit = scope.maxWidth.value / 120f
    fun d(x: Float): Dp = (x * unit).dp
    @Composable fun s(x: Float): TextUnit = with(LocalDensity.current) { d(x).toSp() }

    @Composable fun Book(art: CoverArt.Book) {
        val ink = Color(Cover.INK)
        Box(Modifier.fillMaxSize().background(Color(Cover.cloths[art.cloth]))) {
            Box(Modifier.width(d(5f)).fillMaxHeight().background(Color.Black.copy(alpha = 0.16f)))      // the spine's shade
            Box(Modifier.fillMaxSize().padding(start = d(11f), top = d(9f), end = d(8f), bottom = d(9f))
                .border(d(0.7f), ink.copy(alpha = 0.55f), RoundedCornerShape(d(1f))))
            Column(Modifier.fillMaxSize().padding(start = d(16f), top = d(24f), end = d(12f), bottom = d(20f)),
                   horizontalAlignment = Alignment.CenterHorizontally) {
                art.title.forEach { line ->
                    M3Text(line, color = ink, fontFamily = FontFamily.Serif, fontSize = s(15f), maxLines = 1, softWrap = false,
                           lineHeight = s(19f), overflow = TextOverflow.Clip)
                }
                Spacer(Modifier.height(d(14f)))
                Ornament(ink)
                Spacer(Modifier.weight(1f))
                M3Text(art.author.uppercase(), color = ink, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium,
                       fontSize = s(6f), letterSpacing = s(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }

    /** Three diamonds over a rule. */
    @Composable private fun Ornament(ink: Color) {
        Canvas(Modifier.size(d(44f), d(20f))) {
            val c = ink.copy(alpha = 0.9f)
            val u = size.width / 44f
            // Diamonds 3.5, 6 and 3.5 across their half-height, 9 apart, centred over the rule.
            val widths = listOf(4.9f, 8.4f, 4.9f)
            var x = (size.width - (widths.sum() + 18f) * u) / 2
            for (w in widths) {
                val cx = x + w * u / 2
                val half = w / 1.4f * u
                drawPath(Path().apply { moveTo(cx, 6f * u - half); lineTo(cx + w * u / 2, 6f * u); lineTo(cx, 6f * u + half); lineTo(cx - w * u / 2, 6f * u); close() }, c)
                x += (w + 9f) * u
            }
            drawRect(c, Offset(0f, 18.5f * u), Size(size.width, 0.6f * u))
        }
    }

    @Composable fun Note(art: CoverArt.Note) {
        val ink = Color(0xFF32291C)
        Column(Modifier.fillMaxSize().background(Color(0xFFFFFBEF)).padding(d(12f)), verticalArrangement = Arrangement.spacedBy(d(5f))) {
            M3Text(art.heading, color = ink, fontWeight = FontWeight.SemiBold, fontSize = s(11f), lineHeight = s(13f), maxLines = 2,
                   overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = d(4f)))
            art.rows.forEach { row ->
                when {
                    row.startsWith("#") -> M3Text(row.trimStart('#').trim(), color = ink, fontWeight = FontWeight.SemiBold, fontSize = s(7.5f), maxLines = 1)
                    row.startsWith("- ") || row.startsWith("* ") -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(d(2.5f)).clip(CircleShape).background(ink))
                        Spacer(Modifier.width(d(4f)))
                        M3Text(row.drop(2), color = ink, fontSize = s(6.5f), maxLines = 1)
                    }
                    else -> M3Text(row, color = Color(0xFF5E513E), fontSize = s(6.5f), maxLines = 1)
                }
            }
        }
    }

    @Composable fun Text(art: CoverArt.Text) {
        Row(Modifier.fillMaxSize().background(Color.White)) {
            Column(Modifier.width(d(18f)).fillMaxHeight().background(Color(0xFFF3F3F6)).padding(top = d(10f)), horizontalAlignment = Alignment.End) {
                art.rows.indices.forEach { k ->
                    M3Text("${k + 1}", color = Color(0xFF8F8F8F), fontFamily = FontFamily.Monospace, fontSize = s(6f), lineHeight = s(14f),
                           modifier = Modifier.height(d(14f)), textAlign = TextAlign.End)
                }
            }
            Column(Modifier.padding(start = d(6f), top = d(10f))) {
                art.rows.forEach { row ->
                    M3Text(row.ifEmpty { " " }, color = if (row.startsWith("#")) Color(0xFF3B49DF) else Color(0xFF1C1C1C),
                           fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium, fontSize = s(7f), lineHeight = s(14f),
                           maxLines = 1, softWrap = false, modifier = Modifier.height(d(14f)))
                }
            }
        }
    }
}

/** A book's own cover picture, filling the card, with the spine's shade down the left edge. */
@Composable
private fun Picture(art: CoverArt.Picture) {
    Box(Modifier.fillMaxSize()) {
        Image(art.image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(Modifier.fillMaxHeight().fillMaxWidth(7f / 120f).background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.22f), Color.Transparent))))
    }
}

@Composable
private fun Page(art: CoverArt.Page) {
    Box(Modifier.fillMaxSize().background(Color.White)) {
        val t = art.thumbnail
        if (t != null) {
            Image(t.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, alignment = Alignment.TopCenter,
                  modifier = Modifier.fillMaxSize())
        } else {
            // An unreadable PDF still looks like a page.
            Canvas(Modifier.fillMaxSize()) {
                val u = size.width / 120f
                for (k in 0 until 9) drawRoundRect(Color(0xFFDBDBDB), Offset(16f * u, (24f + k * 7f) * u), Size((if (k % 4 == 3) 50f else 88f) * u, 2f * u),
                                                   androidx.compose.ui.geometry.CornerRadius(u, u))
            }
        }
    }
}

@Composable
private fun Bytes(art: CoverArt.Bytes) {
    Canvas(Modifier.fillMaxSize()) {
        drawRect(Color(Cover.byteColours[0]))
        val u = size.width / 120f
        val inset = 6f * u
        val w = (size.width - 2 * inset) / art.cols
        val h = (size.height - 2 * inset) / art.rows
        art.cells.forEachIndexed { i, v ->
            if (v.toInt() != 0) drawRect(Color(Cover.byteColours[v.toInt()]), Offset(inset + (i % art.cols) * w + 0.15f, inset + (i / art.cols) * h + 0.15f),
                                         Size(w - 0.3f, h - 0.3f))
        }
    }
}
