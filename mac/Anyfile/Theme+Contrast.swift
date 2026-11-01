// The hero's ground under white type: worked out in AppKit colours, as the Mac's hero draws it.
import AppKit

extension Theme {
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
}
