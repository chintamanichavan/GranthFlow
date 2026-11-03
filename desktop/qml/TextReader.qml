// A note or a text file, edited in place and saved as it is typed. A note can also be read set as a
// page: Preview.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Item {
    id: root
    required property Document doc
    readonly property bool markdown: doc.kind === "markdown"
    property bool previewing: false

    /// Saves now; also a moment after typing stops, and when the file is closed.
    function save() { if (editor.text !== doc.source) doc.save(editor.text) }
    Timer { id: soon; interval: 800; onTriggered: root.save() }
    Component.onDestruction: save()

    TabBar {
        id: tabs
        objectName: "mode"
        visible: root.markdown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        width: 220
        onCurrentIndexChanged: {
            root.previewing = currentIndex === 1
            if (root.previewing) {
                root.save()
                preview.text = root.doc.markdownHtml(editor.text, Theme.bodySize, Theme.lineHeight, Theme.paper.secondary, Theme.paper.accent)
            }
        }
        TabButton { text: qsTr("Edit") }
        TabButton { objectName: "previewTab"; text: qsTr("Preview") }
    }

    ScrollView {
        anchors { fill: parent; topMargin: root.markdown ? tabs.height + 16 : 0 }
        visible: !root.previewing
        TextArea {
            id: editor
            objectName: "editor"
            text: root.doc.source
            wrapMode: TextEdit.Wrap
            font.family: Theme.mono
            font.pointSize: 13
            leftPadding: 24
            rightPadding: 24
            topPadding: 16
            selectByMouse: true
            background: null
            onTextChanged: soon.restart()
        }
    }

    Flickable {
        id: flick
        anchors { fill: parent; topMargin: tabs.height + 16 }
        visible: root.previewing
        contentHeight: preview.height + 80
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        TextEdit {
            id: preview
            objectName: "preview"
            y: 24
            width: Math.min(flick.width - 64, Theme.measure)
            x: (flick.width - width) / 2
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.Wrap
            font.family: Theme.serif
            font.pointSize: Theme.bodySize
            color: Theme.paper.label
            selectionColor: Qt.alpha(Theme.paper.accent, 0.3)
            selectedTextColor: Theme.paper.label
        }
    }
}
