// The few types that differ between the Mac and iPhone/iPad, named once so shared code uses one name.
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
typealias PlatformImage = UIImage
#endif

extension PlatformColor {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let v = UInt32(digits, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255, g = CGFloat((v >> 8) & 0xFF) / 255, b = CGFloat(v & 0xFF) / 255
        #if os(macOS)
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
        #else
        self.init(red: r, green: g, blue: b, alpha: 1)
        #endif
    }

    /// One colour in light mode, another in dark.
    static func dynamic(_ light: String, _ dark: String) -> PlatformColor {
        let l = PlatformColor(hex: light)!, d = PlatformColor(hex: dark)!
        #if os(macOS)
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? d : l }
        #endif
    }
}

extension PlatformFont {
    /// The same face made bold or italic, as its family draws them.
    func adding(bold: Bool = false, italic: Bool = false) -> PlatformFont {
        #if os(macOS)
        var font = self
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
        #else
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        return fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: pointSize) } ?? self
        #endif
    }

    var isBold: Bool {
        #if os(macOS)
        fontDescriptor.symbolicTraits.contains(.bold)
        #else
        fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }
}

extension Color {
    init(platform colour: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: colour)
        #else
        self.init(uiColor: colour)
        #endif
    }
}

extension Image {
    init(platformImage image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}
