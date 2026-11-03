// The shelf: every file brought in, most recent first, each as a cover made from the file, with its
// title and how far reading has got. + or File ▸ Open brings files in; dropping files or folders on the window does too. A
// right-click takes a file off the shelf, leaving the file itself where it is.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Page {
    id: root
    required property Library library
    required property Faces faces
    signal open(string path)
    signal add()

    background: Rectangle { color: Theme.library.window }

    header: ToolBar {
        background: Rectangle { color: Theme.library.window }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 12
            Label { text: qsTr("Library"); font.pixelSize: 22; font.weight: Font.DemiBold; color: Theme.library.label; Layout.fillWidth: true }
            ToolButton { objectName: "add"; text: "+"; font.pixelSize: 22; onClicked: root.add(); ToolTip.visible: hovered; ToolTip.text: qsTr("Add books and documents") }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: root.library.count === 0
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("Nothing here yet.\nAdd books and documents with +, or drop them here.")
        color: Theme.library.secondary
    }

    GridView {
        id: grid
        objectName: "shelf"
        anchors.fill: parent
        anchors.margins: 16
        cellWidth: 160
        cellHeight: 270
        clip: true
        model: root.library
        ScrollBar.vertical: ScrollBar {}

        delegate: ItemDelegate {
            id: item
            required property string path
            required property string stem
            required property string kind
            required property real progress
            required property string progressText
            required property double modified
            /// Filled in once the cover is made; a book's title comes from the book.
            readonly property var caption: (root.faces.revision, root.faces.caption(path))
            objectName: "shelf." + path.split("/").pop()
            width: grid.cellWidth - 16
            height: grid.cellHeight - 12
            onClicked: root.open(path)
            background: Rectangle { radius: 6; color: item.hovered ? Qt.alpha(Theme.library.label, 0.05) : "transparent" }

            contentItem: ColumnLayout {
                spacing: 6
                Item {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 168
                    Layout.alignment: Qt.AlignHCenter
                    Rectangle {                            // a soft shadow under the cover
                        anchors.fill: parent
                        anchors.topMargin: 2
                        anchors.bottomMargin: -2
                        radius: 4
                        color: Qt.rgba(0, 0, 0, cover.status === Image.Ready ? 0.14 : 0)
                    }
                    Rectangle {                            // a quiet placeholder while the cover is made
                        anchors.fill: parent
                        radius: 3
                        visible: cover.status !== Image.Ready
                        color: Qt.alpha(Theme.library.secondary, 0.12)
                    }
                    Image {
                        id: cover
                        objectName: "cover"
                        anchors.fill: parent
                        asynchronous: true
                        // The modified time makes a changed file's cover new.
                        source: "image://cover/" + encodeURIComponent(item.path) + "?" + item.modified
                        sourceSize: Qt.size(240, 336)
                        smooth: true
                        mipmap: true
                    }
                }
                Rectangle {                                // how far reading has got
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    radius: 2
                    visible: item.progress >= 0 && item.progress < 1
                    color: Qt.alpha(Theme.library.secondary, 0.2)
                    Rectangle { width: parent.width * Math.max(0, item.progress); height: 3; radius: 2; color: Theme.library.accent }
                }
                Label { text: item.caption.title ?? item.stem; Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; font.weight: Font.DemiBold; color: Theme.library.label }
                Label {                                    // "Book · Herman Melville", "Document · Page 3 of 12", "Program · 1.2 MB"
                    objectName: "subtitle"
                    text: item.caption.label ? item.caption.label + " · " + (item.progressText || item.caption.author || item.caption.sizeText) : " "
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Theme.library.secondary
                    font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: menu.popup()
            }
            Menu {
                id: menu
                MenuItem { text: qsTr("Remove from Library"); onTriggered: root.library.forget(item.path) }
            }
        }
    }
}
