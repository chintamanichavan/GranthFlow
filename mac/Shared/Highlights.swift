// Where marked passages fall in a text, for each platform's view to paint them.
import Foundation

enum Highlights {
    /// How strongly a mark's colour is laid on. On dark paper it is lighter, so the light text over
    /// it stays readable.
    static func strength(onDark dark: Bool) -> CGFloat { dark ? 0.38 : 0.7 }

    static func ranges(of quote: String, in ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: quote, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = NSMaxRange(r)
        }
        return out
    }

    /// The 1-based line holding a UTF-16 offset.
    static func line(at location: Int, in ns: NSString) -> Int {
        var line = 1
        for i in 0..<min(location, ns.length) where ns.character(at: i) == 0x0A { line += 1 }
        return line
    }
}
