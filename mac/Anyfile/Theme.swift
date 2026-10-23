// Colours and type from the design (design/blender_ui_design.py), with dark versions the render
// does not show. Reading is set in New York, the app in SF Pro, bytes and source in SF Mono.
// Colours are NSColor because the reading and hex views are AppKit; SwiftUI wraps them with Color(nsColor:).
import AppKit

struct Palette {
    let window, label, secondary, tertiary, accent, hairline: NSColor
}

enum Theme {
    static let paper = Palette(window: dynamic("#F7F0E1", "#1F1B15"), label: dynamic("#32291C", "#E9E0CD"),
                               secondary: dynamic("#7B6D58", "#A89A82"), tertiary: dynamic("#AA9C86", "#6E6352"),
                               accent: dynamic("#3B49DF", "#8FA0FF"), hairline: dynamic("#E6DCC8", "#3A3328"))
    static let library = Palette(window: dynamic("#F5F4F0", "#1C1C1E"), label: dynamic("#1C1C1E", "#F2F2F4"),
                                 secondary: dynamic("#6B6B70", "#A0A0A6"), tertiary: dynamic("#A5A5AA", "#68686E"),
                                 accent: dynamic("#3B49DF", "#8FA0FF"), hairline: dynamic("#E2E0DA", "#333336"))
    /// A program's window takes the dark ground of its own cover, in light mode too.
    static let night = Palette(window: NSColor(hex: "#0E1330")!, label: NSColor(hex: "#E9EBFA")!,
                               secondary: NSColor(hex: "#8D94C4")!, tertiary: NSColor(hex: "#565E96")!,
                               accent: NSColor(hex: "#8FA0FF")!, hairline: NSColor(hex: "#252C5E")!)
    /// A highlight the reader made.
    static let mark = NSColor(hex: "#FFDD6B")!
    /// A byte map's colours, from empty to dense.
    static let bytes = ["#0E1330", "#1D2C73", "#3B49DF", "#27B5A6", "#F2C14E", "#F26A4B", "#F5F4F0"].map { NSColor(hex: $0)! }

    /// New York for Latin text, falling back to ITF Devanagari, a book face, for Devanagari: on its
    /// own New York falls back to the interface's sans serif. Marathi text gets ITF Devanagari
    /// Marathi, which draws letters such as ल and श in their Marathi forms.
    static func readingFont(size: CGFloat, weight: NSFont.Weight = .regular, language: String? = nil) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        // Core Text draws a fallback at the main font's size; ReadingStyle sizes Devanagari runs itself.
        let fallback = NSFontDescriptor(name: devanagariFace(weight: weight, language: language), size: size)
        return NSFont(descriptor: serif.addingAttributes([.cascadeList: [fallback]]), size: size) ?? base
    }

    /// Devanagari is drawn smaller than Latin at the same point size; this makes the two look one size on a line.
    static let devanagariScale: CGFloat = 1.05       // 1.0 looked small beside New York, 1.12 large

    static func devanagariFont(size: CGFloat, weight: NSFont.Weight, language: String?) -> NSFont {
        NSFont(name: devanagariFace(weight: weight, language: language), size: size * devanagariScale)
            ?? NSFont.systemFont(ofSize: size * devanagariScale, weight: weight)
    }

    static func devanagariFace(weight: NSFont.Weight, language: String?) -> String {
        let family = isMarathi(language) ? "ITFDevanagariMarathi" : "ITFDevanagari"
        let face = weight >= .bold ? "Bold" : weight >= .medium ? "Medium" : "Book"
        return "\(family)-\(face)"
    }

    /// The book's own language when it gives one, otherwise whether Marathi is among the Mac's languages.
    static func isMarathi(_ language: String?, preferred: [String] = Locale.preferredLanguages) -> Bool {
        if let language, !language.isEmpty { return language.lowercased().hasPrefix("mr") }
        return preferred.contains { $0.lowercased().hasPrefix("mr") }
    }

    /// The colour darkened, keeping its hue, until white text on it has at least the WCAG contrast
    /// ratio for body text (4.5:1). A light cover such as a pale pink would otherwise wash out the
    /// hero's white type; a dark one is only darkened a little.
    static func groundForWhiteText(_ colour: NSColor) -> NSColor {
        var c = colour.usingColorSpace(.sRGB) ?? colour
        var darkened = 0.18
        c = c.blended(withFraction: darkened, of: .black) ?? c
        while contrastWithWhite(c) < 4.5, darkened < 0.95 {
            c = c.blended(withFraction: 0.08, of: .black) ?? c
            darkened += 0.08
        }
        return c
    }

    /// WCAG contrast ratio of white text on the colour.
    static func contrastWithWhite(_ colour: NSColor) -> Double {
        guard let c = colour.usingColorSpace(.sRGB) else { return 21 }
        func channel(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        return 1.05 / (luminance + 0.05)
    }

    private static func dynamic(_ light: String, _ dark: String) -> NSColor {
        let l = NSColor(hex: light)!, d = NSColor(hex: dark)!
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
    }
}

extension NSColor {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let v = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
