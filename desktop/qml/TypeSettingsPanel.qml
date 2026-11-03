// The Aa panel: text size, line spacing, column width and look for the book on show.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import GranthFlow

Popup {
    id: root
    required property var settings
    signal changed(var settings)

    function choose(field, value) {
        const s = Object.assign({}, settings)
        s[field] = value
        changed(s)
    }

    padding: 18
    width: 300

    contentItem: ColumnLayout {
        spacing: 16
        RowLayout {
            Button {
                objectName: "textSmaller"
                text: "A"
                font.family: Theme.serif
                font.pixelSize: 13
                enabled: root.settings.size > 13
                onClicked: root.choose("size", root.settings.size - 1)
                Accessible.name: qsTr("Smaller text")
            }
            Label { objectName: "textSize"; text: Math.round(root.settings.size) + " pt"; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; opacity: 0.7 }
            Button {
                objectName: "textLarger"
                text: "A"
                font.family: Theme.serif
                font.pixelSize: 21
                enabled: root.settings.size < 28
                onClicked: root.choose("size", root.settings.size + 1)
                Accessible.name: qsTr("Larger text")
            }
        }
        Repeater {
            model: [
                { title: qsTr("Line spacing"), field: "spacing", options: [["tight", qsTr("Tight")], ["normal", qsTr("Normal")], ["loose", qsTr("Loose")]] },
                { title: qsTr("Column"), field: "width", options: [["narrow", qsTr("Narrow")], ["normal", qsTr("Normal")], ["wide", qsTr("Wide")]] },
            ]
            ColumnLayout {
                id: group
                required property var modelData
                spacing: 6
                Label { text: group.modelData.title; font.pixelSize: 11; opacity: 0.7 }
                RowLayout {
                    spacing: 0
                    Repeater {
                        model: group.modelData.options
                        Button {
                            required property var modelData
                            objectName: group.modelData.title + "." + modelData[1]
                            text: modelData[1]
                            checkable: true
                            checked: root.settings[group.modelData.field] === modelData[0]
                            onClicked: root.choose(group.modelData.field, modelData[0])
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14
            Repeater {
                model: [["auto", qsTr("Auto")], ["paper", qsTr("Paper")], ["sepia", qsTr("Sepia")], ["night", qsTr("Night")]]
                ColumnLayout {
                    id: swatch
                    required property var modelData
                    readonly property bool chosen: root.settings.look === modelData[0]
                    objectName: "look." + modelData[1]
                    spacing: 5
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignHCenter
                        radius: 20
                        color: Theme.look(swatch.modelData[0]).window
                        // Auto is half light paper, half dark: it follows the system's appearance.
                        gradient: swatch.modelData[0] !== "auto" ? null : halves
                        Gradient {
                            id: halves
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.5; color: Theme.lightPaper.window }
                            GradientStop { position: 0.5001; color: Theme.night.window }
                        }
                        border.width: swatch.chosen ? 2.5 : 1
                        border.color: swatch.chosen ? Theme.library.accent : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        Label {
                            anchors.centerIn: parent
                            text: "Aa"
                            font.family: Theme.serif
                            font.pixelSize: 12
                            color: swatch.modelData[0] === "night" ? Theme.night.label : Theme.lightPaper.label
                        }
                        TapHandler { onTapped: root.choose("look", swatch.modelData[0]) }
                    }
                    Label { text: swatch.modelData[1]; font.pixelSize: 11; opacity: 0.7; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }
    }
}
