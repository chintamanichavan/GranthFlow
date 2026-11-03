// A PDF, every page drawn by Qt's PDF module and scrolled through; text can be selected on the
// page. The library keeps the page.
import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import GranthFlow

Item {
    id: root
    required property Document doc
    required property Library library

    PdfDocument {
        id: pdf
        source: root.doc.url
        onStatusChanged: if (pdf.status === PdfDocument.Ready) view.goToPage(Math.max(0, Math.min(root.library.position(root.doc.path), pdf.pageCount - 1)))
    }

    PdfMultiPageView {
        id: view
        objectName: "pdf"
        anchors.fill: parent
        visible: pdf.status !== PdfDocument.Error
        document: pdf
        onCurrentPageChanged: if (pdf.status === PdfDocument.Ready) root.library.recordPosition(root.doc.path, currentPage, pdf.pageCount)
    }

    Label {
        objectName: "unreadable"
        anchors.fill: parent
        visible: pdf.status === PdfDocument.Error
        text: qsTr("This PDF cannot be drawn. It may be damaged, or protected with a password.")
        color: Theme.library.secondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        padding: 32
    }
}
