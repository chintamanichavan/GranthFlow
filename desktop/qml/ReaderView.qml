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
    /// How a book is set (see ReadingSettings), changed with Aa.
    property var settings: library.settings(path)
    /// The page's colours: a book's chosen look, a note's paper, the library's grey for the rest.
    readonly property QtObject paper: document.kind === "epub" ? Theme.look(settings.look) : onPaper ? Theme.paper : Theme.library
    background: Rectangle { color: root.paper.window }

    header: ToolBar {
        background: Rectangle { color: root.paper.window }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            ToolButton {
                objectName: "backToLibrary"
                text: "‹ " + qsTr("Library")
                onClicked: root.back()
                palette.buttonText: root.paper.accent
            }
            Label {
                text: document.title
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                font.weight: Font.DemiBold
                color: root.paper.label
                Layout.fillWidth: true
            }
            Item {                                          // balances the back button, so the title sits centred
                Layout.preferredWidth: 80
                Layout.fillHeight: true
                ToolButton {
                    id: aa
                    objectName: "typeSettings"
                    anchors.right: parent.right
                    visible: document.kind === "epub" && document.error === ""
                    text: "Aa"
                    font.family: Theme.serif
                    font.pixelSize: 18
                    palette.buttonText: root.paper.accent
                    onClicked: panel.open()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Text size, spacing, column and look")
                }
                TypeSettingsPanel {
                    id: panel
                    x: aa.x + aa.width - width
                    y: aa.height
                    settings: root.settings
                    onChanged: s => root.settings = root.library.recordSettings(root.path, s)
                }
            }
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

    Component { id: epub; EpubReader { doc: document; library: root.library; settings: root.settings; paper: root.paper } }
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
