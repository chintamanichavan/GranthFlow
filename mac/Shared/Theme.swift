// Colours and type from the design (design/blender_ui_design.py), with dark versions the render
// does not show. Reading is set in New York, the app in SF Pro, bytes and source in SF Mono.
// Colours are platform colours because the reading and hex views are AppKit or UIKit; SwiftUI wraps them with Color(platform:).
import SwiftUI

struct Palette {
    let window, label, secondary, tertiary, accent, hairline: PlatformColor
}

enum Theme {
    static let paper = Palette(window: PlatformColor.dynamic("#F7F0E1", "#1F1B15"), label: PlatformColor.dynamic("#32291C", "#E9E0CD"),
                               secondary: PlatformColor.dynamic("#7B6D58", "#A89A82"), tertiary: PlatformColor.dynamic("#AA9C86", "#6E6352"),
                               accent: PlatformColor.dynamic("#3B49DF", "#8FA0FF"), hairline: PlatformColor.dynamic("#E6DCC8", "#3A3328"))
    static let library = Palette(window: PlatformColor.dynamic("#F5F4F0", "#1C1C1E"), label: PlatformColor.dynamic("#1C1C1E", "#F2F2F4"),
                                 secondary: PlatformColor.dynamic("#6B6B70", "#A0A0A6"), tertiary: PlatformColor.dynamic("#A5A5AA", "#68686E"),
                                 accent: PlatformColor.dynamic("#3B49DF", "#8FA0FF"), hairline: PlatformColor.dynamic("#E2E0DA", "#333336"))
    /// A program's window takes the dark ground of its own cover, in light mode too.
    static let night = Palette(window: PlatformColor(hex: "#0E1330")!, label: PlatformColor(hex: "#E9EBFA")!,
                               secondary: PlatformColor(hex: "#8D94C4")!, tertiary: PlatformColor(hex: "#565E96")!,
                               accent: PlatformColor(hex: "#8FA0FF")!, hairline: PlatformColor(hex: "#252C5E")!)
    /// A highlight the reader made.
    static let mark = PlatformColor(hex: "#FFDD6B")!
    /// A byte map's colours, from empty to dense.
    static let bytes = ["#0E1330", "#1D2C73", "#3B49DF", "#27B5A6", "#F2C14E", "#F26A4B", "#F5F4F0"].map { PlatformColor(hex: $0)! }

    /// New York for Latin text, falling back to ITF Devanagari, a book face, for Devanagari: on its
    /// own New York falls back to the interface's sans serif. Marathi text gets ITF Devanagari
    /// Marathi, which draws letters such as ल and श in their Marathi forms.
    static func readingFont(size: CGFloat, weight: PlatformFont.Weight = .regular, language: String? = nil) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        // Core Text draws a fallback at the main font's size; ReadingStyle sizes Devanagari runs itself.
        let fallback = PlatformFontDescriptor(name: devanagariFace(weight: weight, language: language), size: size)
        let descriptor = serif.addingAttributes([.cascadeList: [fallback]])
        #if os(macOS)
        return NSFont(descriptor: descriptor, size: size) ?? base
        #else
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    /// Devanagari is drawn smaller than Latin at the same point size; this makes the two look one size on a line.
    static let devanagariScale: CGFloat = 1.05       // 1.0 looked small beside New York, 1.12 large

    static func devanagariFont(size: CGFloat, weight: PlatformFont.Weight, language: String?) -> PlatformFont {
        PlatformFont(name: devanagariFace(weight: weight, language: language), size: size * devanagariScale)
            ?? PlatformFont.systemFont(ofSize: size * devanagariScale, weight: weight)
    }

    static func devanagariFace(weight: PlatformFont.Weight, language: String?) -> String {
        let family = isMarathi(language) ? "ITFDevanagariMarathi" : "ITFDevanagari"
        let face = weight.rawValue >= PlatformFont.Weight.bold.rawValue ? "Bold" : weight.rawValue >= PlatformFont.Weight.medium.rawValue ? "Medium" : "Book"
        return "\(family)-\(face)"
    }

    /// The book's own language when it gives one, otherwise whether Marathi is among the Mac's languages.
    static func isMarathi(_ language: String?, preferred: [String] = Locale.preferredLanguages) -> Bool {
        if let language, !language.isEmpty { return language.lowercased().hasPrefix("mr") }
        return preferred.contains { $0.lowercased().hasPrefix("mr") }
    }
}
