// Every file has a face, made from its own contents, as on the Mac, iPhone and Android: a book's
// own cover picture (or its title and author on cloth when it has none), a PDF's first page, a
// note's first lines, a text file's opening lines, or a map of a file's bytes. Covers are drawn on
// a 120 × 168 card, at twice that in pixels.
#pragma once
#include <QByteArray>
#include <QImage>
#include <QString>
#include <QStringList>

struct Face {
    QImage image;
    QString title;
    QString author;
    /// "Book", "Document", "Note", "Text", "Program" or "Data".
    QString label;
    qint64 size = 0;
};

namespace Cover {

inline constexpr int width = 120, height = 168, scale = 2;
inline constexpr int mapCols = 30, mapRows = 42;

/// Reads the file and makes its face; a face with a null image when the file cannot be read.
Face face(const QString &path, const QString &kind);

QString label(const QString &kind, const QByteArray &data);
/// Mach-O (32/64-bit, either byte order, and universal), ELF, or a Windows PE file.
bool isProgram(const QByteArray &data);
/// One cell per block of the file, row by row; small files fill only the top cells.
QByteArray byteMap(const QByteArray &data, int cells = mapCols * mapRows);
/// A block's colour: 0 empty, 4 text, and 1-3, 5, 6 by rising entropy (6 is compressed or random).
char classify(const char *from, const char *to);
/// FNV-1a, so a book keeps its cloth from one launch to the next.
quint64 stableHash(const QString &s);
/// A title broken into at most three short lines, as on a cloth cover.
QStringList titleLines(const QString &title, int width = 12);

}  // namespace Cover
