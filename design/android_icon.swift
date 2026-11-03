// The Android launcher icon: the Mac icon's granth drawn flat, as Android icons are, for an adaptive
// icon. The blue tile is the background layer (android/app/src/main/res/drawable/ic_launcher_background.xml);
// this draws the foreground (the pothi on its red cloth) and the monochrome layer for themed icons.
//     swift design/android_icon.swift android/app/src/main/res
// Units: the adaptive icon's 108 × 108 grid. Launchers show at least the circle of radius 33 around
// the centre, so everything stays inside it.
import AppKit

let res = CommandLine.arguments.dropFirst().first ?? "res"
let cloth = NSColor(hex: 0xA8232B), gold = NSColor(hex: 0xD9A441), inlay = NSColor(hex: 0xE8B649)
let teak = NSColor(hex: 0x5E3A22), teakEdge = NSColor(hex: 0x4A2C19), leaf = NSColor(hex: 0xEAD9B4), leafLine = NSColor(hex: 0xCDB98C)
let cord = NSColor(hex: 0xC8B27A)
/// Pixels per grid unit. Shadows are measured in pixels, whatever the drawing's scale.
var unit: CGFloat = 1
let font = NSFont(name: "KohinoorDevanagari-Semibold", size: 10) ?? NSFont(name: "DevanagariSangamMN-Bold", size: 10)!

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// ग्रंथ set `height` units tall, centred on (x, y), in `colour`; Core Text shapes the conjunct and the anusvara.
func lettering(_ ctx: CGContext, x: CGFloat, y: CGFloat, height: CGFloat, colour: NSColor) {
    let text = NSAttributedString(string: "ग्रंथ", attributes: [.font: font, .foregroundColor: colour])
    let line = CTLineCreateWithAttributedString(text)
    let box = CTLineGetImageBounds(line, ctx)
    let scale = height / box.height
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: scale, y: -scale)                       // text rises upward; the grid falls
    ctx.textPosition = CGPoint(x: -box.midX, y: -box.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// The pothi, centred on the origin, long side across: top board, the leaves' edges, the bottom board.
func pothi(_ ctx: CGContext, mono: Bool) {
    func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 1) {
        ctx.setFillColor(c.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }
    fill(CGRect(x: -30, y: 4.5, width: 60, height: 3.5), mono ? .white : teakEdge)            // bottom board
    fill(CGRect(x: -29.2, y: 0.5, width: 58.4, height: 4.6), mono ? .white : leaf, radius: 0.6) // leaves
    ctx.setBlendMode(mono ? .clear : .normal)
    ctx.setStrokeColor(leafLine.cgColor)
    ctx.setLineWidth(0.3)
    for y in [1.7, 2.9, 4.1] as [CGFloat] {
        ctx.move(to: CGPoint(x: -28.6, y: y)); ctx.addLine(to: CGPoint(x: 28.6, y: y))
    }
    ctx.strokePath()
    ctx.setBlendMode(.normal)
    fill(CGRect(x: -30, y: -10, width: 60, height: 11.2), mono ? .white : teak, radius: 1.4)  // top board
    if !mono {
        fill(CGRect(x: -30, y: -0.2, width: 60, height: 1.4), teakEdge, radius: 0.6)       // its front edge
        ctx.setStrokeColor(gold.cgColor)
        ctx.setLineWidth(0.4)
        ctx.stroke(CGRect(x: -28.2, y: -8.3, width: 56.4, height: 7.4))
        fill(CGRect(x: 16.6, y: -10.4, width: 1.5, height: 18.8), cord, radius: 0.5)       // the cord round it
    }
    ctx.setBlendMode(mono ? .clear : .normal)
    lettering(ctx, x: -9, y: -4.6, height: 6.4, colour: inlay)
    ctx.setBlendMode(.normal)
}

func draw(_ ctx: CGContext, mono: Bool) {
    ctx.translateBy(x: 54, y: 56)
    ctx.rotate(by: 5 * .pi / 180)                          // turned a little across, as in the Mac icon
    if !mono {
        // The opened cloth under it, a square laid as a diamond, foreshortened, with its gold border.
        func diamond(_ w: CGFloat, _ h: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: 0, y: -h), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: -w, y: 0)])
            p.closeSubpath()
            return p
        }
        ctx.translateBy(x: 0, y: 3)
        ctx.addPath(diamond(31, 20)); ctx.setFillColor(cloth.cgColor); ctx.fillPath()
        ctx.addPath(diamond(27, 17.4)); ctx.setStrokeColor(gold.cgColor); ctx.setLineWidth(0.6); ctx.strokePath()
        // The cord's loose end, trailing onto the cloth.
        let end = CGMutablePath()
        end.move(to: CGPoint(x: 17.4, y: 4))
        end.addCurve(to: CGPoint(x: 25, y: 9), control1: CGPoint(x: 18, y: 8), control2: CGPoint(x: 21, y: 9.5))
        ctx.addPath(end); ctx.setStrokeColor(cord.cgColor); ctx.setLineWidth(0.8); ctx.setLineCap(.round); ctx.strokePath()
        ctx.translateBy(x: 0, y: -3)
        ctx.setShadow(offset: CGSize(width: 0, height: -1.6 * unit), blur: 3 * unit, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    ctx.translateBy(x: 0, y: -5)
    pothi(ctx, mono: mono)
    if !mono { ctx.endTransparencyLayer() }
}

func render(_ px: Int, mono: Bool, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: CGFloat(px) / 108, y: -CGFloat(px) / 108)   // the 108 grid, y falling
    unit = CGFloat(px) / 108                                 // shadows are in pixels, and rise: draw() asks for one below
    draw(ctx, mono: mono)
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for (bucket, px) in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)] {
    render(px, mono: false, to: "\(res)/mipmap-\(bucket)/ic_launcher_foreground.png")
    render(px, mono: true, to: "\(res)/mipmap-\(bucket)/ic_launcher_monochrome.png")
}
print("wrote the icon's layers under \(res)")
