// How a book is set for reading: text size, line spacing, column width and theme. Kept per book
// in the library; a book opened for the first time starts with the reader's latest choice.
import AppKit

struct ReadingSettings: Codable, Equatable {
    enum Spacing: String, Codable, CaseIterable { case tight, normal, loose }
    enum Width: String, Codable, CaseIterable { case narrow, normal, wide }
    enum Look: String, Codable, CaseIterable { case auto, paper, sepia, night }

    var size: Double = 17
    var spacing = Spacing.normal
    var width = Width.normal
    var look = Look.auto

    static let sizes = 13.0...28.0

    func larger() -> ReadingSettings { var s = self; s.size = min(size + 1, Self.sizes.upperBound); return s }
    func smaller() -> ReadingSettings { var s = self; s.size = max(size - 1, Self.sizes.lowerBound); return s }

    var lineHeight: CGFloat {
        switch spacing { case .tight: 1.25; case .normal: 1.45; case .loose: 1.7 }
    }

    /// The widest the column grows, scaled with the text so a line keeps about the same number of words.
    var measure: CGFloat {
        let base: CGFloat = switch width { case .narrow: 460; case .normal: 560; case .wide: 700 }
        return base * CGFloat(size) / 17
    }

    var palette: Palette {
        switch look {
        case .auto: Theme.paper
        case .paper: Theme.fixedPaper
        case .sepia: Theme.sepia
        case .night: Theme.readingNight
        }
    }

    /// Whether the bar and cards over the page should be dark.
    var isDark: Bool? {
        switch look { case .auto: nil; case .paper, .sepia: false; case .night: true }
    }

    // Older libraries have no settings; and a later version may add a field. Missing fields take their defaults.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 17
        spacing = try c.decodeIfPresent(Spacing.self, forKey: .spacing) ?? .normal
        width = try c.decodeIfPresent(Width.self, forKey: .width) ?? .normal
        look = try c.decodeIfPresent(Look.self, forKey: .look) ?? .auto
    }
}

extension Theme {
    /// Paper that stays light in dark mode, for readers who want it.
    static let fixedPaper = Palette(window: NSColor(hex: "#F7F0E1")!, label: NSColor(hex: "#32291C")!, secondary: NSColor(hex: "#7B6D58")!,
                                    tertiary: NSColor(hex: "#AA9C86")!, accent: NSColor(hex: "#3B49DF")!, hairline: NSColor(hex: "#E6DCC8")!)
    static let sepia = Palette(window: NSColor(hex: "#EBD9B4")!, label: NSColor(hex: "#3E2C17")!, secondary: NSColor(hex: "#7A5F3C")!,
                               tertiary: NSColor(hex: "#A88B62")!, accent: NSColor(hex: "#8A4B14")!, hairline: NSColor(hex: "#D9C399")!)
    /// Warm dark paper with light ink, for reading at night.
    static let readingNight = Palette(window: NSColor(hex: "#1F1B15")!, label: NSColor(hex: "#E2D8C4")!, secondary: NSColor(hex: "#A89A82")!,
                                      tertiary: NSColor(hex: "#6E6352")!, accent: NSColor(hex: "#8FA0FF")!, hairline: NSColor(hex: "#3A3328")!)
}

/// The choice a new book starts with: the last one made, kept in UserDefaults.
@MainActor
enum ReadingDefaults {
    private static let key = "readingSettings"

    static func load(_ defaults: UserDefaults = .standard) -> ReadingSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReadingSettings.self, from: $0) } ?? ReadingSettings()
    }

    static func save(_ settings: ReadingSettings, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
