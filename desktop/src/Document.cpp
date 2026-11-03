#include "Document.h"

#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

#include "Engine.h"
#include "Typesetter.h"

void Document::setPath(const QString &path) {
    if (path == path_) return;
    path_ = path;
    kind_.clear();
    error_.clear();
    chapters_.clear();
    bytes_.clear();
    const QFileInfo info(path);
    title_ = info.completeBaseName().isEmpty() ? info.fileName() : info.completeBaseName();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        error_ = QStringLiteral("The file could not be read. It may have been moved or deleted.");
        emit loaded();
        return;
    }
    bytes_ = f.readAll();
    kind_ = Engine::detectKind(bytes_, info.fileName());
    if (kind_ == "epub") {
        const QString meta = Engine::run("meta", {}, bytes_, info.fileName(), kind_).output;
        if (const QString t = Engine::meta("title", meta); !t.isEmpty()) title_ = t;
        // One "number<TAB>title<TAB>path" line per chapter.
        for (const QString &line : Engine::run("chapters", {}, bytes_, info.fileName(), kind_).output.split('\n', Qt::SkipEmptyParts)) {
            const QStringList f = line.split('\t');
            bool ok = false;
            const int n = f.value(0).toInt(&ok);
            if (!ok || f.size() < 3) continue;
            chapters_ << QVariantMap{{"number", n}, {"name", f[1].isEmpty() ? QStringLiteral("Chapter %1").arg(n) : f[1]}};
        }
        if (chapters_.isEmpty()) error_ = QStringLiteral("This book could not be opened. It may be damaged.");
    }
    emit loaded();
}

QString Document::chapterHtml(int number, double size, const QColor &secondary) const {
    QString title;
    for (const QVariant &c : chapters_) {
        const QVariantMap m = c.toMap();
        if (m["number"].toInt() == number) title = m["name"].toString();
    }
    const QString text = Engine::run("text", {QString::number(number)}, bytes_, QFileInfo(path_).fileName(), kind_).output;
    return Typesetter::chapter(text, number, title, size, secondary);
}

QString Document::markdownHtml(const QString &source, double size, const QColor &secondary, const QColor &accent) const {
    return Typesetter::markdown(source, size, secondary, accent);
}

QString Document::hexRow(int row) const {
    const QByteArray chunk = bytes_.mid(qsizetype(row) * 16, 16);
    QString hex, ascii;
    for (int i = 0; i < 16; ++i) {
        if (i < chunk.size()) {
            const auto b = uchar(chunk[i]);
            hex += QStringLiteral("%1 ").arg(b, 2, 16, QChar('0'));
            ascii += b >= 0x20 && b < 0x7F ? QChar(b) : QChar('.');
        } else {
            hex += "   ";
        }
        if (i == 7) hex += ' ';
    }
    return QStringLiteral("%1  %2 |%3|").arg(row * 16, 8, 16, QChar('0')).arg(hex, ascii);
}

bool Document::save(const QString &text) {
    const QByteArray bytes = text.toUtf8();
    if (bytes == bytes_) return true;
    QSaveFile out(path_);
    if (!out.open(QIODevice::WriteOnly) || out.write(bytes) != bytes.size() || !out.commit()) {
        error_ = QStringLiteral("Your changes could not be saved: %1").arg(out.errorString());
        emit loaded();
        return false;
    }
    bytes_ = bytes;
    return true;
}
