// A file opened for reading: kinds, a book's title and chapters, a program's bytes, and saving a note.
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QTextDocument>

#include "Document.h"
#include "epub_fixture.hpp"

class DocumentTest : public QObject {
    Q_OBJECT
    QTemporaryDir dir;

    QString file(const QString &name, const QByteArray &bytes) {
        QFile f(dir.filePath(name));
        if (!f.open(QIODevice::WriteOnly)) qFatal("cannot write %s", qPrintable(f.fileName()));
        f.write(bytes);
        return f.fileName();
    }

private slots:
    void aBookHasItsTitleChaptersAndText() {
        Document doc;
        doc.setPath(file("Book.epub", QByteArray::fromStdString(epubBytes())));
        QCOMPARE(doc.kind(), QString("epub"));
        QCOMPARE(doc.title(), QString("The Test Book"));
        QCOMPARE(doc.error(), QString());
        QCOMPARE(doc.chapters().size(), 3);
        QCOMPARE(doc.chapters()[0].toMap()["name"].toString(), QString("Opening"));
        QTextDocument page;
        page.setHtml(doc.chapterHtml(1, 17, 1.45, Qt::gray));
        QVERIFY(page.toPlainText().contains("Hello brave world."));
    }

    void aGoneFileSaysSo() {
        Document doc;
        QSignalSpy loaded(&doc, &Document::loaded);
        doc.setPath(dir.filePath("gone.epub"));
        QCOMPARE(loaded.size(), 1);
        QVERIFY(doc.error().contains("could not be read"));
    }

    void aDamagedBookSaysSo() {
        Document doc;
        doc.setPath(file("Broken.epub", "PK\x03\x04 not really a book"));
        QVERIFY(!doc.error().isEmpty());
    }

    void anyOtherFileIsShownAsRowsOfHex() {
        Document doc;
        doc.setPath(file("prog.bin", QByteArray("\x7f" "ELF\0\x01\xde\xad" "abcdefghij", 18)));
        QCOMPARE(doc.kind(), QString("binary"));
        QCOMPARE(doc.hexRows(), 2);
        QCOMPARE(doc.hexRow(0), QString("00000000  7f 45 4c 46 00 01 de ad  61 62 63 64 65 66 67 68  |.ELF....abcdefgh|"));
        QVERIFY(doc.hexRow(1).startsWith("00000010  69 6a "));
    }

    void aNoteIsSavedInPlace() {
        const QString path = file("Note.md", "# Note\n");
        Document doc;
        doc.setPath(path);
        QCOMPARE(doc.kind(), QString("markdown"));
        QVERIFY(doc.save("# Note\n\nMore.\n"));
        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll(), QByteArray("# Note\n\nMore.\n"));
        QCOMPARE(doc.source(), QString("# Note\n\nMore.\n"));
    }
};

QTEST_MAIN(DocumentTest)
#include "document_test.moc"
