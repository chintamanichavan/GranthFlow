// Covers made from the files themselves, and the rules they share with the other apps: the byte
// map's colours, the cloth a title gets, and how a title breaks onto a cover.
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include "Cover.h"
#include "epub_fixture.hpp"
#include "fixtures.hpp"

class CoverTest : public QObject {
    Q_OBJECT
    QTemporaryDir dir;

    QString file(const QString &name, const QByteArray &bytes) {
        QFile f(dir.filePath(name));
        if (!f.open(QIODevice::WriteOnly)) qFatal("cannot write %s", qPrintable(f.fileName()));
        f.write(bytes);
        return f.fileName();
    }

private slots:
    void aBookWithoutAPictureIsTitledOnCloth() {
        const Face face = Cover::face(file("Book.epub", QByteArray::fromStdString(epubBytes())), "epub");
        QCOMPARE(face.title, QString("The Test Book"));
        QCOMPARE(face.author, QString("Ada & Bob"));
        QCOMPARE(face.label, QString("Book"));
        QCOMPARE(face.image.size(), QSize(240, 336));
        QCOMPARE(face.image.pixelColor(100, 300).name(), QString("#6e1e24"));   // cloth 1 of 6: FNV-1a of its title, mod 6
    }

    void aPdfShowsItsFirstPage() {
        const Face face = Cover::face(file("Report.pdf", QByteArray::fromStdString(simpleDoc("BT /F1 24 Tf 20 100 Td (Hello) Tj ET").build())), "pdf");
        QCOMPARE(face.label, QString("Document"));
        QCOMPARE(face.image.pixelColor(200, 320), QColor(Qt::white));
        bool inked = false;                                        // the page's text is drawn somewhere on it
        for (int y = 0; y < 336 && !inked; ++y)
            for (int x = 0; x < 240 && !inked; ++x) inked = face.image.pixelColor(x, y).lightness() < 128;
        QVERIFY(inked);
    }

    void notesTextAndProgramsHaveFacesToo() {
        QCOMPARE(Cover::face(file("Note.md", "# Plans\n\n- one\n"), "markdown").label, QString("Note"));
        QCOMPARE(Cover::face(file("Plain.txt", "plain\n"), "text").label, QString("Text"));
        const Face program = Cover::face(file("prog", QByteArray("\x7f" "ELF") + QByteArray(4000, '\0')), "binary");
        QCOMPARE(program.label, QString("Program"));
        QCOMPARE(program.image.pixelColor(2, 2).name(), QString("#0e1330"));
        QVERIFY(Cover::face(dir.filePath("gone.md"), "markdown").image.isNull());
    }

    void blocksAreColouredByWhatTheyHold() {
        const QByteArray zeros(512, '\0'), text = QByteArray("plain words, ").repeated(40);
        QByteArray random(4096, '\0');
        quint32 x = 12345;
        for (char &c : random) { x = x * 1664525 + 1013904223; c = char(x >> 24); }
        QCOMPARE(int(Cover::classify(zeros.cbegin(), zeros.cend())), 0);
        QCOMPARE(int(Cover::classify(text.cbegin(), text.cend())), 4);
        QCOMPARE(int(Cover::classify(random.cbegin(), random.cend())), 6);
        QCOMPARE(Cover::byteMap(QByteArray(10, 'a')).size(), 10);  // a small file fills only the top cells
        QCOMPARE(Cover::byteMap(QByteArray(1260 * 3, 'a')).size(), 1260);
    }

    void aTitleKeepsItsClothAndBreaksAsElsewhere() {
        QCOMPARE(Cover::stableHash(""), 0xcbf29ce484222325ULL);   // FNV-1a, as on the Mac and Android
        QCOMPARE(Cover::stableHash("a"), 0xaf63dc4c8601ec8cULL);
        QCOMPARE(Cover::titleLines("Moby-Dick; or, The Whale"), (QStringList{"Moby-Dick;", "or, The", "Whale"}));
        QCOMPARE(Cover::titleLines("one two three four five six seven eight").size(), 3);
        QVERIFY(Cover::titleLines("one two three four five six seven eight")[2].endsWith(QStringLiteral("…")));
    }

    void programsAreKnownByTheirMagic() {
        QVERIFY(Cover::isProgram("MZ\x90"));
        QVERIFY(Cover::isProgram("\xCF\xFA\xED\xFE"));
        QVERIFY(!Cover::isProgram("%PDF"));
        QCOMPARE(Cover::label("binary", "data"), QString("Data"));
    }
};

QTEST_MAIN(CoverTest)
#include "cover_test.moc"
