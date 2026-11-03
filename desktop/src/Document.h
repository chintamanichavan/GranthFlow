// One file opened for reading: its bytes and kind, read once, and what each reader asks of them:
// a book's chapters and their text, a note's source, a program's bytes as rows of hex.
#pragma once
#include <QByteArray>
#include <QColor>
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class Document : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY loaded)
    Q_PROPERTY(QUrl url READ url NOTIFY loaded)
    Q_PROPERTY(QString kind READ kind NOTIFY loaded)
    /// A book's own title, otherwise the file's name without its extension.
    Q_PROPERTY(QString title READ title NOTIFY loaded)
    /// Why the file could not be read; empty when it was.
    Q_PROPERTY(QString error READ error NOTIFY loaded)
    /// A book's chapters, each { number, name }.
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY loaded)
    /// A note's or text file's text.
    Q_PROPERTY(QString source READ source NOTIFY loaded)
    Q_PROPERTY(int hexRows READ hexRows NOTIFY loaded)

public:
    using QObject::QObject;

    QString path() const { return path_; }
    void setPath(const QString &path);
    QUrl url() const { return QUrl::fromLocalFile(path_); }
    QString kind() const { return kind_; }
    QString title() const { return title_; }
    QString error() const { return error_; }
    QVariantList chapters() const { return chapters_; }
    QString source() const { return QString::fromUtf8(bytes_); }
    int hexRows() const { return int((bytes_.size() + 15) / 16); }

    /// The chapter set for reading, as HTML.
    Q_INVOKABLE QString chapterHtml(int number, double size, double lineHeight, const QColor &secondary) const;
    Q_INVOKABLE QString markdownHtml(const QString &source, double size, double lineHeight, const QColor &secondary, const QColor &accent) const;
    /// "00000010  7f 45 4c 46 …  |.ELF…|": sixteen bytes from row × 16.
    Q_INVOKABLE QString hexRow(int row) const;
    /// Writes a note's or text file's new text; false, with `error` set, when it could not be written.
    Q_INVOKABLE bool save(const QString &text);

signals:
    void loaded();

private:
    QString path_, kind_, title_, error_;
    QByteArray bytes_;
    QVariantList chapters_;
};
