// The shelf: every file brought in, most recent first, each with its title and how far reading has
// got. + or File ▸ Open brings files in; dropping files or folders on the window does too. A
// right-click takes a file off the shelf, leaving the file itself where it is.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Page {
    id: root
    required property Library library
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
            objectName: "shelf." + path.split("/").pop()
            width: grid.cellWidth - 16
            height: grid.cellHeight - 12
            onClicked: root.open(path)
            background: Rectangle { radius: 6; color: item.hovered ? Qt.alpha(Theme.library.label, 0.05) : "transparent" }

            contentItem: ColumnLayout {
                spacing: 6
                Rectangle {                                // the cover: covers from the files come next
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 168
                    Layout.alignment: Qt.AlignHCenter
                    radius: 3
                    color: Theme.paper.window
                    border.color: Qt.rgba(0, 0, 0, 0.12)
                    Label {
                        anchors.fill: parent
                        anchors.margins: 12
                        text: item.stem
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        font.family: Theme.serif
                        font.pixelSize: 15
                        color: Theme.paper.label
                        horizontalAlignment: Text.AlignHCenter
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
                Label { text: item.stem; Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; font.weight: Font.DemiBold; color: Theme.library.label }
                Label { text: item.progressText || ({ epub: qsTr("Book"), pdf: qsTr("Document"), markdown: qsTr("Note"), text: qsTr("Text") })[item.kind] || qsTr("File"); Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.library.secondary; font.pixelSize: 12 }
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
