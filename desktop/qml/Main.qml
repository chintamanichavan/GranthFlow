// The window: the library, or one file open for reading. Files come in by File ▸ Open, by dropping
// them on the window, and from the command line ("Open with").
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import GranthFlow

ApplicationWindow {
    id: window
    required property Library library
    /// The file on show; empty shows the library.
    property string openPath

    width: 1100
    height: 760
    visible: true
    title: reader.item && reader.item.bookTitle ? reader.item.bookTitle + " — GranthFlow" : "GranthFlow"
    color: Theme.library.window

    /// Shows a file, starting afresh even if another was open.
    function show(path) {
        openPath = ""
        openPath = path
    }

    function bringIn(urls) {
        const paths = library.add(urls)
        if (paths.length === 1) show(paths[0])
    }

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            Action { text: qsTr("&Open…"); shortcut: StandardKey.Open; onTriggered: picker.open() }
            Action { text: qsTr("&Close"); shortcut: StandardKey.Close; enabled: window.openPath !== ""; onTriggered: window.openPath = "" }
            MenuSeparator {}
            Action { text: qsTr("&Quit"); shortcut: StandardKey.Quit; onTriggered: Qt.quit() }
        }
    }

    FileDialog {
        id: picker
        fileMode: FileDialog.OpenFiles
        title: qsTr("Add books and documents")
        onAccepted: window.bringIn(selectedFiles)
    }

    Loader {
        id: shelf
        anchors.fill: parent
        active: window.openPath === ""
        sourceComponent: LibraryView {
            library: window.library
            onOpen: path => window.show(path)
            onAdd: picker.open()
        }
    }

    Loader {
        id: reader
        anchors.fill: parent
        active: window.openPath !== ""
        sourceComponent: ReaderView {
            path: window.openPath
            library: window.library
            onBack: window.openPath = ""
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => { if (drop.hasUrls) window.bringIn(drop.urls) }
    }
}
