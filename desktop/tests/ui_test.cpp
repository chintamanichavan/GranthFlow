// The app driven as a reader drives it: the real window, clicked and typed into. Each kind of file
// opens in its reader, a book turns chapters and the library keeps the place, a note is edited,
// previewed and saved, and a file that cannot be read says so.
#include <QFile>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickTextDocument>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>
#include <QTextDocument>
#include <memory>

#include "Library.h"
#include "epub_fixture.hpp"
#include "fixtures.hpp"

class UiTest : public QObject {
    Q_OBJECT
    QTemporaryDir dir;
    std::unique_ptr<Library> library;
    std::unique_ptr<QQmlApplicationEngine> engine;
    QQuickWindow *window = nullptr;

    QString file(const QString &name, const QByteArray &bytes) {
        QFile f(dir.filePath(name));
        if (!f.open(QIODevice::WriteOnly)) qFatal("cannot write %s", qPrintable(f.fileName()));
        f.write(bytes);
        f.close();
        library->add({QUrl::fromLocalFile(f.fileName())});
        return f.fileName();
    }

    /// Opens the window, on the library or on a file.
    void start(const QString &open = {}) {
        engine = std::make_unique<QQmlApplicationEngine>();
        engine->setInitialProperties({{"library", QVariant::fromValue(library.get())}, {"openPath", open}});
        engine->loadFromModule("GranthFlow", "Main");
        window = nullptr;
        QVERIFY(!engine->rootObjects().isEmpty());
        window = qobject_cast<QQuickWindow *>(engine->rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));
    }

    /// Items by what is on screen, not by who made them: a list's rows belong to no object above them.
    static QQuickItem *named(QQuickItem *item, const QString &name) {
        if (item->objectName() == name) return item;
        for (QQuickItem *child : item->childItems())
            if (QQuickItem *found = named(child, name)) return found;
        return nullptr;
    }

    QQuickItem *find(const QString &name) {
        QQuickItem *found = nullptr;
        if (!window) return nullptr;                              // the window did not load; start() has said why
        if (!QTest::qWaitFor([&] { return (found = named(window->contentItem(), name)) && found->isVisible(); }, 5000))
            qWarning() << "nothing shown named" << name;
        return found;
    }

    void click(QQuickItem *item) {
        QVERIFY(item);
        const QPointF centre = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
        QTest::mouseClick(window, Qt::LeftButton, {}, centre.toPoint());
    }

    /// The text a page shows, as a reader would read it.
    static QString shown(QQuickItem *page) { return !page ? QString() : page->property("textDocument").value<QQuickTextDocument *>()->textDocument()->toPlainText(); }

private slots:
    void init() { library = std::make_unique<Library>(dir.filePath("library-" + QString::number(QDateTime::currentMSecsSinceEpoch()) + ".json")); }
    void cleanup() { engine.reset(); }

    void aBookTurnsChaptersAndTheLibraryKeepsThePlace() {
        const QString book = file("Book.epub", QByteArray::fromStdString(epubBytes()));
        start(book);
        QQuickItem *page = find("page");
        QVERIFY(shown(page).contains("Hello brave world."));
        QCOMPARE(window->title(), QString("The Test Book — GranthFlow"));
        click(find("nextChapter"));
        QTRY_VERIFY(shown(find("page")).contains("alpha again, alpha twice"));
        click(find("backToLibrary"));
        QVERIFY(find("shelf.Book.epub"));
        QCOMPARE(library->position(book), 2);
        QCOMPARE(library->entry(book)->progressText(), QString("Chapter 2 of 3"));
        click(find("shelf.Book.epub"));                          // opened again, at its place
        QTRY_VERIFY(shown(find("page")).contains("alpha again"));
    }

    void aNoteIsEditedPreviewedAndSaved() {
        const QString note = file("Note.md", "# Notes\n\nSome **bold** words.\n");
        start(note);
        click(find("editor"));
        QTest::keyClick(window, Qt::Key_End, Qt::ControlModifier);
        for (const char c : QByteArray("Added.")) QTest::keyClick(window, c);
        click(find("previewTab"));
        QTRY_VERIFY(shown(find("preview")).contains("Some bold words."));
        QVERIFY(shown(find("preview")).contains("Added."));
        click(find("backToLibrary"));
        QFile f(note);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll(), QByteArray("# Notes\n\nSome **bold** words.\nAdded."));
    }

    void aPdfShowsItsPages() {
        const QString pdf = file("Report.pdf", QByteArray::fromStdString(simpleDoc("BT /F1 12 Tf 20 100 Td (Hello pdf) Tj ET").build()));
        start(pdf);
        QQuickItem *view = find("pdf");
        QVERIFY(view);
        QTRY_COMPARE(view->property("document").value<QObject *>()->property("pageCount").toInt(), 1);
    }

    void anyOtherFileShowsItsBytes() {
        start(file("prog.bin", QByteArray("\x7f" "ELF\0\x01\xde\xad", 8)));
        QQuickItem *hex = find("hex");
        QVERIFY(hex);
        QTRY_COMPARE(hex->property("count").toInt(), 1);
    }

    void aFileThatHasGoneSaysSo() {
        start(dir.filePath("gone.epub"));
        QQuickItem *message = find("unreadable");
        QVERIFY(message);
        QVERIFY(message->property("text").toString().contains("could not be read"));
    }
};

QTEST_MAIN(UiTest)
#include "ui_test.moc"
