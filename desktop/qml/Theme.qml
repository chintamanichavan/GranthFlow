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
    readonly property real bodySize: 17
    /// The reading column's widest, about 66 characters of body type.
    readonly property real measure: 640
}
