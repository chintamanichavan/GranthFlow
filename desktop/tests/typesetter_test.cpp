// How chapters and notes are set as HTML for the page.
#include <QTest>
#include <QTextDocument>

#include "Typesetter.h"

class TypesetterTest : public QObject {
    Q_OBJECT

    static QString plain(const QString &html) {
        QTextDocument d;
        d.setHtml(html);
        return d.toPlainText();
    }

private slots:
    void aChapterHasItsNumberAndTitleThenItsParagraphs() {
        const QString page = plain(Typesetter::chapter("Opening\n\nFirst <para> & more.\n\nSecond\nline.", 1, "Opening", 17, Qt::gray));
        QVERIFY(page.contains("CHAPTER"));
        QCOMPARE(page.count("Opening"), 1);                       // the chapter's own heading is not shown twice
        QVERIFY(page.contains("First <para> & more."));
        QVERIFY(page.contains("Second\nline."));              // a line break within a paragraph stays
    }

    void theLeadingTitleIsDroppedOnlyWhenItIsTheTitle() {
        QCOMPARE(Typesetter::dropLeadingTitle("\n  opening\n\nText", "Opening"), QString("Text"));
        QCOMPARE(Typesetter::dropLeadingTitle("Text first", "Opening"), QString("Text first"));
        QCOMPARE(Typesetter::dropLeadingTitle("Text", ""), QString("Text"));
    }

    void markdownIsSetLineByLine() {
        const QString source = "# Title\n\nSome **bold** and *italic*, `code` and [a link](https://x).\n- item\n```\nlet x = 1\n```";
        QTextDocument d;
        d.setHtml(Typesetter::markdown(source, 17, Qt::gray, Qt::blue));
        const QStringList lines = d.toPlainText().split('\n');
        QCOMPARE(lines[0], QString("Title"));
        QCOMPARE(lines[2], QString("Some bold and italic, code and a link."));
        QVERIFY(lines[3].contains("•"));
        QVERIFY(lines[3].endsWith("item"));
        QCOMPARE(lines[4], QString("let x = 1"));                // the fences themselves are not shown
        QCOMPARE(d.blockCount(), 5);                              // one block per line shown
    }

    void headingsAreHashesThenASpace() {
        QCOMPARE(Typesetter::headingLevel("# One"), 1);
        QCOMPARE(Typesetter::headingLevel("###### Six"), 6);
        QCOMPARE(Typesetter::headingLevel("####### Seven"), 0);
        QCOMPARE(Typesetter::headingLevel("#tag"), 0);
        QCOMPARE(Typesetter::headingLevel("##"), 2);
    }
};

QTEST_MAIN(TypesetterTest)
#include "typesetter_test.moc"
