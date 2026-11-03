#include "Cover.h"

#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QPdfDocument>
#include <cmath>

#include "Engine.h"
#include "Typesetter.h"

namespace Cover {

namespace {

const QColor cloths[] = {QColor("#1B2F63"), QColor("#6E1E24"), QColor("#1F4A3A"), QColor("#7A4E16"), QColor("#4A2A5E"), QColor("#2E3A48")};
const QColor ink("#F1E4C6");
const QColor byteColours[] = {QColor("#0E1330"), QColor("#1D2C73"), QColor("#3B49DF"), QColor("#27B5A6"),
                              QColor("#F2C14E"), QColor("#F26A4B"), QColor("#F5F4F0")};

/// The first of these the system has: covers are set as the page is.
QString family(const QStringList &preferred, QFont::StyleHint hint) {
    const QStringList have = QFontDatabase::families();
    for (const QString &f : preferred) if (have.contains(f)) return f;
    QFont fallback;
    fallback.setStyleHint(hint);
    return fallback.defaultFamily();
}
QFont serif(double size, QFont::Weight weight = QFont::Normal) {
    static const QString f = family({"Charter", "Georgia", "Cambria", "Noto Serif", "DejaVu Serif", "Liberation Serif", "Times New Roman"}, QFont::Serif);
    QFont font(f, -1, weight);
    font.setPointSizeF(size);
    return font;
}
QFont sans(double size, QFont::Weight weight = QFont::Normal) {
    QFont font;
    font.setWeight(weight);
    font.setPointSizeF(size);
    return font;
}
QFont mono(double size, QFont::Weight weight = QFont::Normal) {
    static const QString f = family({"Cascadia Mono", "Consolas", "SF Mono", "Menlo", "DejaVu Sans Mono", "Noto Sans Mono"}, QFont::Monospace);
    QFont font(f, -1, weight);
    font.setPointSizeF(size);
    return font;
}

/// A canvas in card units: 120 × 168, drawn at `scale` pixels per unit. Fonts are sized in units too.
QImage canvas(QPainter &p, QImage &image) {
    image = QImage(width * scale, height * scale, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    p.begin(&image);
    p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    p.scale(scale, scale);
    return image;
}

void text(QPainter &p, const QRectF &r, const QString &s, const QFont &font, const QColor &colour, int flags = Qt::AlignLeft | Qt::AlignTop) {
    p.setFont(font);
    p.setPen(colour);
    p.drawText(r, flags | Qt::TextSingleLine, QFontMetricsF(font).elidedText(s, Qt::ElideRight, r.width()));
}

QImage bookFace(const QStringList &title, const QString &author, const QColor &cloth) {
    QImage image;
    QPainter p;
    canvas(p, image);
    p.fillRect(QRectF(0, 0, width, height), cloth);
    p.fillRect(QRectF(0, 0, 5, height), QColor(0, 0, 0, 41));                          // the spine's shade
    QColor frame = ink;
    frame.setAlphaF(0.55);
    p.setPen(QPen(frame, 0.7));
    p.drawRoundedRect(QRectF(11.35, 9.35, width - 19.7, height - 18.7), 1, 1);
    double y = 24;
    for (const QString &line : title) {
        text(p, QRectF(16, y, width - 28, 19), line, serif(15), ink, Qt::AlignHCenter | Qt::AlignTop);
        y += 19;
    }
    // Three diamonds over a rule, as on the design's cloth covers.
    QColor ornament = ink;
    ornament.setAlphaF(0.9);
    p.setPen(Qt::NoPen);
    p.setBrush(ornament);
    const double top = y + 14, widths[] = {4.9, 8.4, 4.9};
    double x = 16 + (width - 28 - (4.9 + 8.4 + 4.9 + 18)) / 2;
    for (double w : widths) {
        const double cx = x + w / 2, half = w / 1.4;
        p.drawPolygon(QPolygonF({QPointF(cx, top + 6 - half), QPointF(cx + w / 2, top + 6), QPointF(cx, top + 6 + half), QPointF(cx - w / 2, top + 6)}));
        x += w + 9;
    }
    p.drawRect(QRectF(16 + (width - 28 - 44) / 2, top + 18.5, 44, 0.6));
    QFont small = serif(6, QFont::Medium);
    small.setLetterSpacing(QFont::AbsoluteSpacing, 0.6);
    text(p, QRectF(16, height - 28, width - 28, 9), author.toUpper(), small, ink, Qt::AlignHCenter | Qt::AlignTop);
    return image;
}

/// A book's own cover picture, filling the card, with the spine's shade down the left edge.
QImage pictureFace(const QImage &picture) {
    QImage image;
    QPainter p;
    canvas(p, image);
    const QSizeF card(width, height);
    const QSizeF fill = QSizeF(picture.size()).scaled(card, Qt::KeepAspectRatioByExpanding);
    p.drawImage(QRectF(QPointF((width - fill.width()) / 2, (height - fill.height()) / 2), fill), picture);
    QLinearGradient shade(0, 0, 7, 0);
    shade.setColorAt(0, QColor(0, 0, 0, 56));
    shade.setColorAt(1, Qt::transparent);
    p.fillRect(QRectF(0, 0, 7, height), shade);
    return image;
}

/// The first page at the cover's width, from the top, on white. An unreadable PDF still looks like a page.
QImage pageFace(const QString &path) {
    QImage image;
    QPainter p;
    canvas(p, image);
    p.fillRect(QRectF(0, 0, width, height), Qt::white);
    QPdfDocument pdf;
    if (pdf.load(path) == QPdfDocument::Error::None && pdf.pageCount() > 0) {
        const QSizeF page = pdf.pagePointSize(0);
        if (page.width() > 0) {
            const QSize pixels(width * scale, int(page.height() * width * scale / page.width()));
            p.drawImage(QRectF(0, 0, width, pixels.height() / double(scale)), pdf.render(0, pixels));
            return image;
        }
    }
    p.setPen(Qt::NoPen);
    p.setBrush(QColor("#DBDBDB"));
    for (int k = 0; k < 9; ++k) p.drawRoundedRect(QRectF(16, 24 + k * 7, k % 4 == 3 ? 50 : 88, 2), 1, 1);
    return image;
}

QImage noteFace(const QString &heading, const QStringList &rows) {
    QImage image;
    QPainter p;
    canvas(p, image);
    const QColor paper("#FFFBEF"), dark("#32291C"), soft("#5E513E");
    p.fillRect(QRectF(0, 0, width, height), paper);
    p.setFont(sans(11, QFont::DemiBold));
    p.setPen(dark);
    QRectF used;
    p.drawText(QRectF(12, 12, width - 24, 34), Qt::TextWordWrap | Qt::AlignTop, heading, &used);   // two lines at most
    double y = 12 + std::min(used.height(), 34.0) + 9;
    for (const QString &row : rows) {
        if (y > height - 14) break;
        if (row.startsWith('#')) {
            QString h = row;
            while (h.startsWith('#')) h.remove(0, 1);
            text(p, QRectF(12, y, width - 24, 10), h.trimmed(), sans(7.5, QFont::DemiBold), dark);
        } else if (row.startsWith("- ") || row.startsWith("* ")) {
            p.setPen(Qt::NoPen);
            p.setBrush(dark);
            p.drawEllipse(QRectF(12, y + 3.5, 2.5, 2.5));
            text(p, QRectF(18.5, y, width - 30.5, 10), row.mid(2), sans(6.5), dark);
        } else {
            text(p, QRectF(12, y, width - 24, 10), row, sans(6.5), soft);
        }
        y += 13;
    }
    return image;
}

QImage textFace(const QStringList &rows) {
    QImage image;
    QPainter p;
    canvas(p, image);
    p.fillRect(QRectF(0, 0, width, height), Qt::white);
    p.fillRect(QRectF(0, 0, 18, height), QColor("#F3F3F6"));
    for (int k = 0; k < rows.size(); ++k) {
        const double y = 10 + k * 14;
        text(p, QRectF(0, y, 16, 14), QString::number(k + 1), mono(6), QColor("#8F8F8F"), Qt::AlignRight | Qt::AlignVCenter);
        text(p, QRectF(24, y, width - 28, 14), rows[k], mono(7, QFont::Medium),
             rows[k].startsWith('#') ? QColor("#3B49DF") : QColor("#1C1C1C"), Qt::AlignLeft | Qt::AlignVCenter);
    }
    return image;
}

QImage byteFace(const QByteArray &cells) {
    QImage image;
    QPainter p;
    canvas(p, image);
    p.fillRect(QRectF(0, 0, width, height), byteColours[0]);
    const double inset = 6, w = (width - 2 * inset) / mapCols, h = (height - 2 * inset) / mapRows;
    for (int i = 0; i < cells.size(); ++i) {
        if (cells[i] == 0) continue;
        p.fillRect(QRectF(inset + (i % mapCols) * w + 0.15, inset + (i / mapCols) * h + 0.15, w - 0.3, h - 0.3), byteColours[int(cells[i])]);
    }
    return image;
}

/// The book's own cover picture, read at shelf size rather than held at full size.
QImage bookPicture(const QByteArray &data, const QString &name) {
    const Engine::Result path = Engine::run("cover", {}, data, name, "epub");
    if (!path.ok || path.output.trimmed().isEmpty()) return {};
    Engine::Result bytes = Engine::run("cat", {path.output.trimmed()}, data, name, "epub");
    if (!bytes.ok) return {};
    QBuffer buffer(&bytes.outputBytes);
    QImageReader reader(&buffer);
    const QSize full = reader.size();
    if (full.height() > height * scale * 2) reader.setScaledSize(full.scaled(QSize(10000, height * scale * 2), Qt::KeepAspectRatio));
    return reader.read();
}

}  // namespace

Face face(const QString &path, const QString &kind) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QByteArray data = f.readAll();
    const QFileInfo info(path);
    Face face{{}, info.completeBaseName().isEmpty() ? info.fileName() : info.completeBaseName(), {}, label(kind, data), data.size()};
    if (kind == "epub") {
        const QString meta = Engine::run("meta", {}, data, info.fileName(), kind).output;
        if (const QString t = Engine::meta("title", meta); !t.isEmpty()) face.title = t;
        face.author = Engine::meta("creator", meta);
        const QImage picture = bookPicture(data, info.fileName());
        face.image = !picture.isNull() ? pictureFace(picture)
                                       : bookFace(titleLines(face.title), face.author, cloths[stableHash(face.title) % std::size(cloths)]);
    } else if (kind == "pdf") {
        face.image = pageFace(path);
    } else if (kind == "markdown") {
        const QStringList lines = QString::fromUtf8(data.left(16384)).split('\n');
        qsizetype h = -1;
        for (qsizetype i = 0; i < lines.size() && h < 0; ++i) if (Typesetter::headingLevel(lines[i].trimmed()) == 1) h = i;
        QString heading = face.title;
        if (h >= 0) {
            heading = lines[h].trimmed();
            while (heading.startsWith('#')) heading.remove(0, 1);
            heading = heading.trimmed();
        }
        QStringList rows;
        for (qsizetype i = 0; i < lines.size() && rows.size() < 8; ++i)
            if (i != h && !lines[i].trimmed().isEmpty()) rows << lines[i].trimmed();
        face.image = noteFace(heading, rows);
    } else if (kind == "text") {
        QStringList rows = QString::fromUtf8(data.left(4096)).split('\n').mid(0, 9);
        for (QString &r : rows) r = r.left(28);
        face.image = textFace(rows);
    } else {
        face.image = byteFace(byteMap(data));
    }
    return face;
}

QString label(const QString &kind, const QByteArray &data) {
    if (kind == "epub") return QStringLiteral("Book");
    if (kind == "pdf") return QStringLiteral("Document");
    if (kind == "markdown") return QStringLiteral("Note");
    if (kind == "text") return QStringLiteral("Text");
    return isProgram(data) ? QStringLiteral("Program") : QStringLiteral("Data");
}

bool isProgram(const QByteArray &data) {
    if (data.startsWith("MZ")) return true;
    static const QByteArray magics[] = {"\xCF\xFA\xED\xFE", "\xCE\xFA\xED\xFE", "\xFE\xED\xFA\xCF", "\xFE\xED\xFA\xCE", "\xCA\xFE\xBA\xBE", "\x7F" "ELF"};
    for (const QByteArray &m : magics) if (data.startsWith(m)) return true;
    return false;
}

QByteArray byteMap(const QByteArray &data, int cells) {
    if (data.isEmpty()) return {};
    const qsizetype block = std::max<qsizetype>(1, (data.size() + cells - 1) / cells);
    QByteArray out;
    for (qsizetype start = 0; start < data.size(); start += block)
        out += classify(data.constData() + start, data.constData() + std::min(data.size(), start + block));
    return out;
}

char classify(const char *from, const char *to) {
    // Long blocks are sampled at up to 4096 evenly spaced bytes; that keeps a 50 MB file quick.
    const qsizetype step = std::max<qsizetype>(1, (to - from) / 4096);
    int counts[256] = {};
    int n = 0, zeros = 0, printable = 0;
    for (const char *i = from; i < to; i += step) {
        const auto b = uchar(*i);
        ++counts[b];
        ++n;
        if (b == 0) ++zeros;
        if ((b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D || b == 0x09) ++printable;
    }
    if (zeros * 10 >= n * 9) return 0;
    if (printable * 100 >= n * 85) return 4;
    double entropy = 0;
    int seen = 0;
    for (int c : counts) {
        if (c == 0) continue;
        const double p = double(c) / n;
        entropy -= p * std::log2(p);
        ++seen;
    }
    // Short samples under-count entropy; the Miller–Madow correction adds back the expected shortfall.
    entropy = std::min(8.0, entropy + (seen - 1) / (2.0 * n * std::log(2.0)));
    // A block of n bytes can show at most log2(n) bits, so small blocks are judged against that.
    const double fraction = entropy / std::min(8.0, std::log2(std::max(n, 2)));
    if (fraction < 0.25) return 1;
    if (fraction < 0.55) return 2;
    if (fraction < 0.8) return 3;
    if (fraction < 0.95) return 5;
    return 6;
}

quint64 stableHash(const QString &s) {
    quint64 h = 0xcbf29ce484222325ULL;
    for (const char b : s.toUtf8()) h = (h ^ uchar(b)) * 0x100000001b3ULL;
    return h;
}

QStringList titleLines(const QString &title, int width) {
    QStringList lines;
    for (const QString &word : title.split(' ', Qt::SkipEmptyParts)) {
        if (!lines.isEmpty() && lines.last().size() + 1 + word.size() <= width) lines.last() += ' ' + word;
        else lines << word;
    }
    if (lines.size() > 3) {
        lines = lines.mid(0, 3);
        lines[2] += QStringLiteral("…");
    }
    return lines.isEmpty() ? QStringList{title} : lines;
}

}  // namespace Cover
