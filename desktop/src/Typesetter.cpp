#include "Typesetter.h"

#include <QRegularExpression>

namespace Typesetter {

namespace {
QString css(const QColor &c) { return c.name(QColor::HexRgb); }
QString pt(double v) { return QString::number(v, 'f', 1) + "pt"; }
}  // namespace

QString dropLeadingTitle(const QString &text, const QString &title) {
    if (title.isEmpty()) return text;
    QString rest = text;
    while (!rest.isEmpty() && rest.front().isSpace()) rest.remove(0, 1);
    const qsizetype end = rest.indexOf('\n');
    const QString first = end < 0 ? rest : rest.left(end);
    if (first.trimmed().compare(title, Qt::CaseInsensitive) != 0) return text;
    rest = end < 0 ? QString() : rest.mid(end);
    while (!rest.isEmpty() && (rest.front() == '\n' || rest.front() == '\r')) rest.remove(0, 1);
    return rest;
}

QString chapter(const QString &text, int number, const QString &title, double size, double lineHeight, const QColor &secondary) {
    const QString t = title.trimmed();
    QString html = QStringLiteral("<p align=\"center\" style=\"font-family: sans-serif; font-size: %1; color: %2; margin-bottom: %3px\">"
                                  "CHAPTER %4</p>")
                       .arg(pt(size * 12 / 17), css(secondary)).arg(size * 0.4).arg(number);
    if (!t.isEmpty())
        html += QStringLiteral("<p align=\"center\" style=\"font-size: %1; margin-bottom: %2px\">%3</p>")
                    .arg(pt(size * 30 / 17)).arg(size * 1.6).arg(t.toHtmlEscaped());
    // The engine sets paragraphs apart with a blank line; lines within one stay as they are.
    for (const QString &para : dropLeadingTitle(text, t).split(QRegularExpression("\\n\\s*\\n"), Qt::SkipEmptyParts)) {
        QString body = para.trimmed().toHtmlEscaped();
        body.replace('\n', "<br/>");
        html += QStringLiteral("<p style=\"margin-bottom: %1px; line-height: %2%\">%3</p>").arg(size * 0.8).arg(lineHeight * 100).arg(body);
    }
    return html;
}

int headingLevel(const QString &line) {
    qsizetype hashes = 0;
    while (hashes < line.size() && line[hashes] == '#') ++hashes;
    if (hashes < 1 || hashes > 6) return 0;
    return hashes == line.size() || line[hashes] == ' ' ? int(hashes) : 0;
}

/// Bold, italic, code and links within one line.
static QString inlineMarks(const QString &s, double size, const QColor &accent) {
    static const QRegularExpression pattern(R"(\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`|\[(.+?)\]\((.+?)\))");
    QString out;
    qsizetype at = 0;
    for (auto it = pattern.globalMatch(s); it.hasNext();) {
        const auto m = it.next();
        out += s.mid(at, m.capturedStart() - at).toHtmlEscaped();
        if (m.hasCaptured(1) || m.hasCaptured(2)) out += "<b>" + (m.captured(1) + m.captured(2)).toHtmlEscaped() + "</b>";
        else if (m.hasCaptured(3) || m.hasCaptured(4)) out += "<i>" + (m.captured(3) + m.captured(4)).toHtmlEscaped() + "</i>";
        else if (m.hasCaptured(5)) out += QStringLiteral("<span style=\"font-family: monospace; font-size: %1\">%2</span>").arg(pt(size * 0.88), m.captured(5).toHtmlEscaped());
        else out += QStringLiteral("<span style=\"color: %1\">%2</span>").arg(css(accent), m.captured(6).toHtmlEscaped());
        at = m.capturedEnd();
    }
    return out + s.mid(at).toHtmlEscaped();
}

QString markdown(const QString &source, double size, double lineHeight, const QColor &secondary, const QColor &accent) {
    static const double headingSizes[] = {30, 23, 19, 17, 15, 14};
    QString html;
    bool inFence = false;
    for (const QString &line : source.split('\n')) {
        const QString trimmed = line.trimmed();
        if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) { inFence = !inFence; continue; }
        const QString block = QStringLiteral("<p style=\"margin: 0; line-height: %1%; %2\">%3</p>").arg(lineHeight * 100);
        if (inFence) {
            html += block.arg(QStringLiteral("font-family: monospace; white-space: pre; font-size: %1; color: %2").arg(pt(size * 14 / 17), css(secondary)),
                              line.toHtmlEscaped());
        } else if (int level = headingLevel(trimmed)) {
            html += block.arg(QStringLiteral("font-weight: bold; font-size: %1").arg(pt(size * headingSizes[level - 1] / 17)),
                              trimmed.mid(level).trimmed().toHtmlEscaped());
        } else if (trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ")) {
            html += block.arg(QString(), "&nbsp;&nbsp;&bull;&nbsp;&nbsp;" + inlineMarks(trimmed.mid(2), size, accent));
        } else {
            html += block.arg(QString(), line.isEmpty() ? "&nbsp;" : inlineMarks(line, size, accent));
        }
    }
    return html;
}

}  // namespace Typesetter
