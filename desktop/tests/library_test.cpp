// The library: files and folders brought in, the order of the shelf, where reading stopped, and
// the JSON it keeps, read back as it was written.
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include "Library.h"
#include "epub_fixture.hpp"

class LibraryTest : public QObject {
    Q_OBJECT
    QTemporaryDir dir;

    QString file(const QString &name, const QByteArray &bytes) {
        QDir().mkpath(QFileInfo(dir.filePath(name)).absolutePath());
        QFile f(dir.filePath(name));
        if (!f.open(QIODevice::WriteOnly)) qFatal("cannot write %s", qPrintable(f.fileName()));
        f.write(bytes);
        return f.fileName();
    }
    QString libraryFile() { return dir.filePath("app/library.json"); }

private slots:
    void init() {
        QFile::remove(libraryFile());
        QFile::remove(dir.filePath("app/preferences.ini"));
    }

    void filesAndFoldersAreShelvedWithTheirKinds() {
        const QString book = file("Book.epub", QByteArray::fromStdString(epubBytes()));
        const QString note = file("folder/Note.md", "# Hi\n");
        file("folder/inner/Plain.txt", "plain text\n");
        Library library(libraryFile());
        QSignalSpy count(&library, &Library::countChanged);
        const QStringList added = library.add({QUrl::fromLocalFile(book), QUrl::fromLocalFile(dir.filePath("folder"))});
        QCOMPARE(added.size(), 3);
        QCOMPARE(library.rowCount(), 3);
        QCOMPARE(count.size(), 1);
        QCOMPARE(library.entry(book)->kind, QString("epub"));
        QCOMPARE(library.entry(note)->kind, QString("markdown"));
        QVERIFY(library.entry(note)->unopened);
    }

    void theMostRecentlyOpenedComesFirstAndPlacesAreKept() {
        const QString a = file("A.md", "a\n"), b = file("B.md", "b\n");
        {
            Library library(libraryFile());
            library.add({QUrl::fromLocalFile(a), QUrl::fromLocalFile(b)});
            QTest::qWait(1100);                                   // opened times are kept to the second
            library.recordOpened(a, "markdown");
            library.recordPosition(a, 3, 10);
            QCOMPARE(library.recent().first().path, a);
            QCOMPARE(library.data(library.index(0), Library::ProgressTextRole).toString(), QString());   // a note has no chapters
        }
        Library again(libraryFile());                             // read back from its file
        QCOMPARE(again.recent().first().path, a);
        QCOMPARE(again.position(a), 3);
        QCOMPARE(again.entry(a)->total, 10);
        QVERIFY(!again.entry(a)->unopened);
        QVERIFY(again.entry(b)->unopened);
    }

    void progressIsSaidAsTheOtherAppsSayIt() {
        LibraryEntry book{"/x/B.epub", "epub", QDateTime::currentDateTimeUtc(), 4, 135};
        QCOMPARE(book.progressText(), QString("Chapter 4 of 135"));
        book.position = 135;
        QCOMPARE(book.progressText(), QString("Finished"));
        LibraryEntry pdf{"/x/D.pdf", "pdf", QDateTime::currentDateTimeUtc(), 2, 12};
        QCOMPARE(pdf.progressText(), QString("Page 3 of 12"));
        QCOMPARE(pdf.progress(), 0.25);
        QCOMPARE(pdf.stem(), QString("D"));
    }

    void theJsonHasTheFieldsOfTheOtherApps() {
        const QString a = file("A.md", "a\n");
        Library library(libraryFile());
        library.add({QUrl::fromLocalFile(a)});
        library.recordPosition(a, 1, 2);
        QFile f(libraryFile());
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).array().first().toObject();
        QCOMPARE(o["path"].toString(), a);
        QCOMPARE(o["kind"].toString(), QString("markdown"));
        QVERIFY(o["opened"].toString().endsWith('Z'));          // ISO 8601 in UTC, as Swift writes it
        QCOMPARE(o["position"].toInt(), 1);
        QCOMPARE(o["total"].toInt(), 2);
        QVERIFY(o["unopened"].toBool());
    }

    void aBookKeepsItsSettingsAndANewBookStartsWithTheLatest() {
        const QString a = file("A.epub", QByteArray::fromStdString(epubBytes())), b = file("B.epub", QByteArray::fromStdString(epubBytes()));
        {
            Library library(libraryFile());
            library.add({QUrl::fromLocalFile(a), QUrl::fromLocalFile(b)});
            QCOMPARE(library.settings(a)["size"].toDouble(), 17.0);
            QCOMPARE(library.settings(a)["look"].toString(), QString("auto"));
            const QVariantMap kept = library.recordSettings(a, {{"size", 40}, {"spacing", "Loose"}, {"look", "night"}, {"width", "odd"}});
            QCOMPARE(kept["size"].toDouble(), 28.0);                // as large as text goes
            QCOMPARE(kept["spacing"].toString(), QString("loose"));
            QCOMPARE(kept["width"].toString(), QString("normal"));   // unknown: the default
            QCOMPARE(kept["lineHeight"].toDouble(), 1.7);
            QCOMPARE(kept["measure"].toDouble(), 560.0 * 28 / 17);
        }
        Library again(libraryFile());
        QCOMPARE(again.settings(a)["look"].toString(), QString("night"));
        QCOMPARE(again.settings(b)["look"].toString(), QString("night"));   // b has none of its own: the latest choice
        again.recordSettings(b, {{"look", "sepia"}});
        QCOMPARE(again.settings(a)["look"].toString(), QString("night"));   // a keeps its own
        QFile f(libraryFile());
        QVERIFY(f.open(QIODevice::ReadOnly));
        for (const QJsonValue &v : QJsonDocument::fromJson(f.readAll()).array())
            if (v["path"].toString() == a)
                QCOMPARE(v["settings"].toObject(), (QJsonObject{{"size", 28}, {"spacing", "loose"}, {"width", "normal"}, {"look", "night"}}));
    }

    void forgettingAndGoneFilesLeaveTheShelfButNotTheDisk() {
        const QString a = file("A.md", "a\n"), b = file("B.md", "b\n");
        Library library(libraryFile());
        library.add({QUrl::fromLocalFile(a), QUrl::fromLocalFile(b)});
        library.forget(a);
        QVERIFY(QFile::exists(a));
        QCOMPARE(library.rowCount(), 1);
        QFile::remove(b);
        Library again(libraryFile());
        QCOMPARE(again.rowCount(), 0);                            // b is remembered, but not shown
        QVERIFY(again.entry(b));
    }
};

QTEST_GUILESS_MAIN(LibraryTest)
#include "library_test.moc"
