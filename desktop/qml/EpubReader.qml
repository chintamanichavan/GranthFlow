// A book, one chapter at a time, set on paper in a column of reading width. The bar below turns
// chapters and lists them all; Ctrl+← and Ctrl+→ turn them too. The library keeps the chapter.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Item {
    id: root
    required property Document doc
    required property Library library
    required property var settings
    required property QtObject paper
    property int index: -1
    readonly property var chapter: doc.chapters[index]

    Component.onCompleted: {
        const at = library.position(doc.path)
        index = Math.max(0, doc.chapters.findIndex(c => c.number === at))
    }
    onChapterChanged: {
        if (!chapter) return
        set()
        flick.contentY = 0
        library.recordPosition(doc.path, chapter.number, doc.chapters.length)
    }
    // A new size, spacing or look sets the chapter again, keeping the place on the page.
    onSettingsChanged: if (chapter) {
        const at = flick.contentHeight > 0 ? flick.contentY / flick.contentHeight : 0
        set()
        flick.contentY = at * flick.contentHeight
    }
    onPaperChanged: if (chapter) set()

    function set() { page.text = doc.chapterHtml(chapter.number, settings.size, settings.lineHeight, paper.secondary) }

    Shortcut { sequence: "Ctrl+Left"; enabled: root.index > 0; onActivated: root.index -= 1 }
    Shortcut { sequence: "Ctrl+Right"; enabled: root.index + 1 < root.doc.chapters.length; onActivated: root.index += 1 }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: bar.top }
        contentHeight: page.height + 96
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        TextEdit {
            id: page
            objectName: "page"
            y: 40
            width: Math.min(flick.width - 64, root.settings.measure)
            x: (flick.width - width) / 2
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.Wrap
            font.family: Theme.serif
            font.pointSize: root.settings.size
            color: root.paper.label
            selectionColor: Qt.alpha(root.paper.accent, 0.3)
            selectedTextColor: root.paper.label
        }
    }

    RowLayout {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        ToolButton {
            objectName: "previousChapter"
            text: "‹"
            palette.buttonText: root.paper.accent
            font.pixelSize: 22
            enabled: root.index > 0
            onClicked: root.index -= 1
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Previous chapter (Ctrl+←)")
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: contents.implicitHeight
            ToolButton {
                id: contents
                objectName: "contents"
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                text: root.chapter ? root.chapter.name : qsTr("Contents")
                palette.buttonText: root.paper.accent
                onClicked: list.popup(contents)
            }
            Menu { id: list }
            Instantiator {
                model: root.doc.chapters
                delegate: MenuItem { required property var modelData; required property int index; text: modelData.name; onTriggered: root.index = index }
                onObjectAdded: (i, item) => list.insertItem(i, item)
                onObjectRemoved: (i, item) => list.removeItem(item)
            }
        }
        ToolButton {
            objectName: "nextChapter"
            text: "›"
            palette.buttonText: root.paper.accent
            font.pixelSize: 22
            enabled: root.index + 1 < root.doc.chapters.length
            onClicked: root.index += 1
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Next chapter (Ctrl+→)")
        }
    }
}
