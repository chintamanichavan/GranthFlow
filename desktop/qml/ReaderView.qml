// One file open: its bar, with the way back to the library, over the reader for its kind.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Page {
    id: root
    required property string path
    required property Library library
    readonly property string bookTitle: document.title
    signal back()

    Document { id: document; path: root.path }
    Component.onCompleted: if (document.error === "") library.recordOpened(path, document.kind)

    readonly property bool onPaper: document.kind === "epub" || document.kind === "markdown"
    background: Rectangle { color: root.onPaper ? Theme.paper.window : Theme.library.window }

    header: ToolBar {
        background: Rectangle { color: root.onPaper ? Theme.paper.window : Theme.library.window }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            ToolButton {
                objectName: "backToLibrary"
                text: "‹ " + qsTr("Library")
                onClicked: root.back()
                palette.buttonText: Theme.paper.accent
            }
            Label {
                text: document.title
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                font.weight: Font.DemiBold
                color: root.onPaper ? Theme.paper.label : Theme.library.label
                Layout.fillWidth: true
            }
            Item { Layout.preferredWidth: 80 }              // balances the back button, so the title sits centred
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: document.error !== "" ? unreadable
                       : document.kind === "epub" ? epub
                       : document.kind === "pdf" ? pdf
                       : document.kind === "markdown" || document.kind === "text" ? text
                       : hex
    }

    Component { id: epub; EpubReader { doc: document; library: root.library } }
    Component { id: pdf; PdfReader { doc: document; library: root.library } }
    Component { id: text; TextReader { doc: document } }
    Component { id: hex; HexReader { doc: document } }
    Component {
        id: unreadable
        Label {
            objectName: "unreadable"
            text: document.error
            color: Theme.library.secondary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            padding: 32
        }
    }
}
