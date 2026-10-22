// Sets ग्रंथ as white on transparent, for the app icon's gold inlay. Blender cannot shape
// Devanagari (the conjunct ग्र and the anusvara need a shaping engine), so Core Text does it here.
//     swift design/granth_lettering.swift design/granth_lettering.png
import AppKit

let word = "ग्रंथ"
let out = CommandLine.arguments.dropFirst().first ?? "granth_lettering.png"
let font = NSFont(name: "KohinoorDevanagari-Semibold", size: 300) ?? NSFont(name: "DevanagariSangamMN-Bold", size: 300)!
let text = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: NSColor.white])
let bounds = text.boundingRect(with: NSSize(width: 4000, height: 4000), options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
let pad: CGFloat = 40
let size = NSSize(width: ceil(bounds.width + 2 * pad), height: ceil(bounds.height + 2 * pad))
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
text.draw(with: NSRect(x: pad - bounds.minX, y: pad - bounds.minY, width: bounds.width, height: bounds.height),
          options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(Int(size.width))x\(Int(size.height)) in \(font.fontName)")
