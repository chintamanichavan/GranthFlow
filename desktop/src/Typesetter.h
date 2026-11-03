// How reading text is set, as on the Mac, iPhone and Android: a chapter's number and title centred
// above serif text, and Markdown set as a page. Text is built as the HTML Qt's text documents take,
// at the reader's size; the page's colour, serif face and measure come from the view.
#pragma once
#include <QColor>
#include <QString>

namespace Typesetter {

/// "CHAPTER n" and the title, centred, then the chapter's paragraphs.
QString chapter(const QString &text, int number, const QString &title, double size, const QColor &secondary);

/// Chapters usually begin with their own heading; it is already shown as the title.
QString dropLeadingTitle(const QString &text, const QString &title);

/// Markdown as a page: headings, lists and code in reading type, with bold, italic, code and links
/// inline. Each line of the source is one block of the page.
QString markdown(const QString &source, double size, const QColor &secondary, const QColor &accent);

/// 1..6 for "# Title" to "###### Title", 0 for anything else.
int headingLevel(const QString &line);

}  // namespace Typesetter
