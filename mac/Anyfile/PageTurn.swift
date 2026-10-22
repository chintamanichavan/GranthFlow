// Turning a page: the old page curls away to show the next one, drawn by Core Image's page curl
// with shadow. Going back runs the same curl in reverse, so the page lays itself down again.
// With Reduce Motion on, the pages crossfade instead.
import AppKit
import CoreImage
import QuartzCore

enum PageCurl {
    static let duration: CFTimeInterval = 0.55

    /// One frame of the turn. `progress` runs 0...1; forward curls `from` away to show `to`,
    /// backward lays `to` down over `from`, as if the previous page were turned back.
    static func frame(from: CIImage, to: CIImage, progress: Double, forward: Bool, reduceMotion: Bool = false) -> CIImage {
        let extent = from.extent
        let t = eased(min(max(progress, 0), 1))
        if reduceMotion {
            let f = CIFilter(name: "CIDissolveTransition")!
            f.setValue(from, forKey: kCIInputImageKey)
            f.setValue(to, forKey: kCIInputTargetImageKey)
            f.setValue(t, forKey: kCIInputTimeKey)
            return f.outputImage!.cropped(to: extent)
        }
        let f = CIFilter(name: "CIPageCurlWithShadowTransition")!
        // Back: the previous page is the one that moves, unrolling as time runs from 1 to 0.
        f.setValue(forward ? from : to, forKey: kCIInputImageKey)
        f.setValue(forward ? to : from, forKey: kCIInputTargetImageKey)
        f.setValue(backside(of: forward ? from : to), forKey: "inputBacksideImage")
        f.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        f.setValue(forward ? t : 1 - t, forKey: kCIInputTimeKey)
        f.setValue(angle, forKey: kCIInputAngleKey)
        f.setValue(extent.width * 0.18, forKey: kCIInputRadiusKey)
        f.setValue(0.6, forKey: "inputShadowSize")
        f.setValue(0.35, forKey: "inputShadowAmount")
        f.setValue(CIVector(cgRect: extent), forKey: "inputShadowExtent")
        return f.outputImage!.cropped(to: extent)
    }

    /// The curl starts at the lower right corner and travels to the left, as a right-hand page turns.
    static let angle = Double.pi * 0.92

    /// The back of a turning page: the same page seen through the paper, washed toward the paper colour.
    static func backside(of page: CIImage) -> CIImage {
        let paper = CIImage(color: CIColor(cgColor: Theme.paper.window.cgColor)).cropped(to: page.extent)
        let f = CIFilter(name: "CIDissolveTransition")!
        f.setValue(page.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -page.extent.width, y: 0)), forKey: kCIInputImageKey)
        f.setValue(paper, forKey: kCIInputTargetImageKey)
        f.setValue(0.85, forKey: kCIInputTimeKey)
        return f.outputImage!.cropped(to: page.extent)
    }

    /// Slow out of rest and into it, so the page does not jerk at either end.
    static func eased(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
}

/// Holds the reading view and plays page turns over it. The turn is drawn into a layer above the
/// page; the real text underneath already shows the new chapter, so nothing waits on the animation.
final class PageTurnView: NSView {
    let scroll: NSScrollView
    private let overlay = CALayer()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var from: CIImage?, to: CIImage?
    private var forward = true
    private var start: CFTimeInterval = 0
    private var link: CADisplayLink?
    /// Counts turns, so the fallback below only ever ends the turn that scheduled it.
    private var turnNumber = 0

    init(scroll: NSScrollView) {
        self.scroll = scroll
        super.init(frame: .zero)
        wantsLayer = true
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        overlay.isHidden = true
        overlay.contentsGravity = .resize
        layer?.addSublayer(overlay)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// What the page looks like now, at screen resolution.
    func snapshot() -> CIImage? {
        guard bounds.width > 1, bounds.height > 1, let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return nil }
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        return rep.cgImage.map { CIImage(cgImage: $0) }
    }

    /// Plays the turn from the page as it was to the page as it is now.
    func turn(from old: CIImage, forward: Bool) {
        layoutSubtreeIfNeeded()
        scroll.displayIfNeeded()
        guard let new = snapshot(), new.extent == old.extent else { return }
        from = old
        to = new
        self.forward = forward
        start = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.frame = bounds
        overlay.contentsScale = window?.backingScaleFactor ?? 2
        overlay.isHidden = false
        CATransaction.commit()
        draw(progress: 0)
        link?.invalidate()
        link = displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        // The display link only ticks while the window is on screen. If the window is hidden or
        // minimised mid-turn, this still clears the half-turned page from over the text.
        turnNumber += 1
        let this = turnNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + PageCurl.duration + 0.25) { [weak self] in
            if let self, self.turnNumber == this, self.isTurning { self.finish() }
        }
    }

    @objc private func tick() {
        let progress = (CACurrentMediaTime() - start) / PageCurl.duration
        if progress >= 1 { finish() } else { draw(progress: progress) }
    }

    private func draw(progress: Double) {
        guard let from, let to else { return }
        let frame = PageCurl.frame(from: from, to: to, progress: progress, forward: forward,
                                   reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.contents = context.createCGImage(frame, from: frame.extent)
        CATransaction.commit()
    }

    private func finish() {
        link?.invalidate()
        link = nil
        from = nil
        to = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.isHidden = true
        overlay.contents = nil
        CATransaction.commit()
    }

    var isTurning: Bool { link != nil }
}
