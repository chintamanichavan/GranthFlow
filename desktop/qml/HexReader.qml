// Any other file, as its bytes: offset, sixteen bytes in hex, and the same bytes as text.
import QtQuick
import QtQuick.Controls
import GranthFlow

ListView {
    id: root
    required property Document doc
    objectName: "hex"
    model: doc.hexRows
    clip: true
    topMargin: 16
    leftMargin: 24
    ScrollBar.vertical: ScrollBar {}
    delegate: Text {
        required property int index
        text: root.doc.hexRow(index)
        font.family: Theme.mono
        font.pointSize: 12
        color: Theme.library.label
        textFormat: Text.PlainText
    }
}
