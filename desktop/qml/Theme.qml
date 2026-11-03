// The colours of paper and ink, as on the Mac, iPhone and Android: warm paper by day, warm dark
// paper by night, and a quieter grey for the library. Each follows the system's light or dark.
pragma Singleton
import QtQuick

QtObject {
    readonly property bool dark: Application.styleHints.colorScheme === Qt.ColorScheme.Dark

    readonly property QtObject paper: QtObject {
        property color window: dark ? "#1F1B15" : "#F7F0E1"
        property color label: dark ? "#E9E0CD" : "#32291C"
        property color secondary: dark ? "#A89A82" : "#7B6D58"
        property color accent: dark ? "#8FA0FF" : "#3B49DF"
    }
    /// The looks a book can be set in. Auto is paper, light or dark with the system.
    readonly property QtObject lightPaper: QtObject {
        property color window: "#F7F0E1"
        property color label: "#32291C"
        property color secondary: "#7B6D58"
        property color accent: "#3B49DF"
    }
    readonly property QtObject sepia: QtObject {
        property color window: "#EBD9B4"
        property color label: "#3E2C17"
        property color secondary: "#7A5F3C"
        property color accent: "#8A4B14"
    }
    /// Warm dark paper with light ink, for reading at night.
    readonly property QtObject night: QtObject {
        property color window: "#1F1B15"
        property color label: "#E2D8C4"
        property color secondary: "#A89A82"
        property color accent: "#8FA0FF"
    }
    function look(name) { return ({ paper: lightPaper, sepia: sepia, night: night })[name] ?? paper }

    readonly property QtObject library: QtObject {
        property color window: dark ? "#1C1C1E" : "#F5F4F0"
        property color label: dark ? "#F2F2F4" : "#1C1C1E"
        property color secondary: dark ? "#A0A0A6" : "#6B6B70"
        property color accent: dark ? "#8FA0FF" : "#3B49DF"
    }

    /// Reading type: the first of these the system has, in order of preference across Windows, Linux and macOS.
    readonly property string serif: installed(["Charter", "Georgia", "Cambria", "Noto Serif", "DejaVu Serif", "Liberation Serif", "Times New Roman"], "serif")
    readonly property string mono: installed(["Cascadia Mono", "Consolas", "SF Mono", "Menlo", "DejaVu Sans Mono", "Noto Sans Mono"], "monospace")

    function installed(families, fallback) {
        const have = Qt.fontFamilies()
        return families.find(f => have.includes(f)) ?? fallback
    }
    /// Notes are set at the size and spacing a book starts with.
    readonly property real bodySize: 17
    readonly property real lineHeight: 1.45
    readonly property real measure: 560
}
