// Turning a page as a physical book does: the page lifts at its outer edge, bends as it swings over
// the spine, and shows its back; the next page lies beneath in the turning page's shadow
// (PageGeometry, PageRenderer). The arrow keys play a whole turn; a two-finger swipe on the trackpad
// holds the page under the fingers and lets it fall, or settle back, on release.
// With Reduce Motion on, or without Metal, the pages crossfade instead.
import AppKit
import CoreImage
import QuartzCore

enum PageCurl {
    static let duration: CFTimeInterval = 0.6
    /// Past this progress the page has swung beyond the spine, out of the view, so a turn ends here.
    static let visibleEnd: Float = 0.6

    /// The renderer's progress and which page turns, for a turn `fraction` of the way (0 old page
    /// showing, 1 new page showing). Forward, the old page lifts away; backward, the previous page
    /// comes back over the spine and lays itself down.
    static func progress(fraction: Double, forward: Bool) -> Float {
        let f = Float(min(max(fraction, 0), 1))
        return (forward ? f : 1 - f) * visibleEnd
    }

    /// Slow out of rest and into it, so the page does not jerk at either end.
    static func eased(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    /// Fast at first, then settling: how a released page falls the rest of the way.
    static func easedOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
}

/// A two-finger horizontal swipe, as the fraction of a page turn it has made. Fingers moving left
/// turn to the next page, right to the previous; the direction is fixed by the first clear movement.
struct SwipeTurn {
    /// How far the fingers travel, as a share of the view's width, for a whole turn.
    static let span: CGFloat = 0.55
    /// Movement before a direction is decided, so a wobble does not start a turn.
    static let slop: CGFloat = 8

    let width: CGFloat
    private(set) var travel: CGFloat = 0        // finger movement so far, positive to the right
    private(set) var step: Int?                 // +1 next page, -1 previous, nil until decided
    private(set) var lastMove: CGFloat = 0

    init(width: CGFloat) { self.width = max(width, 1) }

    mutating func move(by fingerDX: CGFloat) {
        travel += fingerDX
        lastMove = fingerDX
        if step == nil, abs(travel) >= Self.slop { step = travel < 0 ? 1 : -1 }
    }

    /// 0...1 of the turn, in the decided direction; moving back past the start holds at 0.
    var fraction: Double {
        guard let step else { return 0 }
        let along = step == 1 ? -travel : travel
        return Double(min(max(along / (width * Self.span), 0), 1))
    }

    /// Released past a third of the turn, or flicked onward, the page falls over; otherwise it settles back.
    var commits: Bool {
        guard let step else { return false }
        let onward = step == 1 ? -lastMove : lastMove
        return fraction > 0.33 || (fraction > 0.05 && onward > 6)
    }

    /// The fingers' horizontal movement from a scroll event's delta, positive to the right. With
    /// natural scrolling the delta already follows the fingers; without it, it is reversed.
    static func fingerDX(scrollingDeltaX: CGFloat, invertedFromDevice: Bool) -> CGFloat {
        invertedFromDevice ? scrollingDeltaX : -scrollingDeltaX
    }
}

/// Holds the reading view and plays page turns over it. The turn is drawn in a layer above the page;
/// the real text underneath already shows the new chapter once a turn is decided, so nothing waits on it.
final class PageTurnView: NSView {
    let scroll: NSScrollView
    /// The neighbouring page (+1 next, -1 previous) as it will look, for a swipe to turn toward.
    var preview: ((Int) -> CGImage?)?
    /// Called when a swipe has turned the page, to change the chapter underneath.
    var commit: ((Int) -> Void)?

    private let renderer = PageRenderer()
    private let metal = CAMetalLayer()
    private let fade = CALayer()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var old: CGImage?, new: CGImage?
    private var forward = true
    private var fraction: Double = 0
    private var animation: (from: Double, to: Double, start: CFTimeInterval, duration: CFTimeInterval, curve: (Double) -> Double)?
    private var link: CADisplayLink?
    private var swipe: SwipeTurn?
    private var swipeRefused = false
    /// Counts turns, so a fallback timer only ever ends the turn that scheduled it.
    private var turnNumber = 0

    init(scroll: NSScrollView) {
        self.scroll = scroll
        super.init(frame: .zero)
        wantsLayer = true
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        (scroll as? PageScrollView)?.turner = self
        for l in [metal, fade] as [CALayer] {
            l.isHidden = true
            layer?.addSublayer(l)
        }
        metal.device = renderer?.device
        metal.pixelFormat = PageRenderer.pixelFormat
        metal.colorspace = CGColorSpace(name: CGColorSpace.sRGB)       // the page images are sRGB
        metal.isOpaque = true
        fade.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// True while a turn is on screen, whether played or held under the fingers.
    var isBusy: Bool { !(metal.isHidden && fade.isHidden) }

    /// What the page looks like now, at screen resolution.
    func snapshot() -> CGImage? {
        guard bounds.width > 1, bounds.height > 1, let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return nil }
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        return rep.cgImage
    }

    // MARK: Played turns (keys, arrows, Contents)

    /// Plays a whole turn from the page as it was to the page as it is now.
    func turn(from oldPage: CGImage, forward: Bool) {
        layoutSubtreeIfNeeded()
        scroll.displayIfNeeded()
        guard let newPage = snapshot(), newPage.width == oldPage.width, newPage.height == oldPage.height else { return }
        show(old: oldPage, new: newPage, forward: forward)
        animate(to: 1, duration: PageCurl.duration, curve: PageCurl.eased)
    }

    // MARK: Swiped turns (trackpad)

    func swipeMoved(by fingerDX: CGFloat) {
        guard !swipeRefused else { return }
        if swipe == nil {
            if isBusy { swipeRefused = true; return }           // a played turn is still finishing
            swipe = SwipeTurn(width: bounds.width)
        }
        swipe?.move(by: fingerDX)
        guard let s = swipe, let step = s.step else { return }
        if metal.isHidden && fade.isHidden {
            // The direction is decided: picture both pages, or refuse when there is no page that way.
            guard let oldPage = snapshot(), let newPage = preview?(step) else { swipeRefused = true; swipe = nil; return }
            show(old: oldPage, new: newPage, forward: step > 0)
        }
        stopAnimation()
        draw(fraction: s.fraction)
    }

    func swipeEnded() {
        defer { swipe = nil; swipeRefused = false }
        guard let s = swipe, let step = s.step, isBusy else { return }
        let target: Double = s.commits ? 1 : 0
        // The rest of the way takes as long as the distance left, at the speed of a whole turn.
        let duration = max(0.12, PageCurl.duration * abs(target - fraction))
        animate(to: target, duration: duration, curve: PageCurl.easedOut)
        if s.commits { commit?(step) }                         // the text underneath changes now, under the turning page
    }

    // MARK: Drawing

    private func show(old oldPage: CGImage, new newPage: CGImage, forward: Bool) {
        old = oldPage
        new = newPage
        self.forward = forward
        // Forward the old page turns away; backward the previous page comes back over the old one.
        renderer?.setPages(turning: forward ? oldPage : newPage, beneath: forward ? newPage : oldPage)
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let useMetal = renderer != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for l in [metal, fade] as [CALayer] { l.frame = bounds; l.contentsScale = scale }
        metal.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metal.isHidden = !useMetal
        fade.isHidden = useMetal
        CATransaction.commit()
        draw(fraction: 0)
    }

    private func draw(fraction f: Double) {
        fraction = f
        if !metal.isHidden, let renderer, let drawable = metal.nextDrawable(), let cb = renderer.makeCommandBuffer() {
            renderer.draw(progress: PageCurl.progress(fraction: f, forward: forward), into: drawable.texture, commandBuffer: cb)
            cb.present(drawable)
            cb.commit()
        } else if !fade.isHidden, let old, let new {
            let blend = CIFilter(name: "CIDissolveTransition")!
            blend.setValue(CIImage(cgImage: old), forKey: kCIInputImageKey)
            blend.setValue(CIImage(cgImage: new), forKey: kCIInputTargetImageKey)
            blend.setValue(f, forKey: kCIInputTimeKey)
            let image = blend.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: old.width, height: old.height))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fade.contents = context.createCGImage(image, from: image.extent)
            CATransaction.commit()
        }
    }

    private func animate(to target: Double, duration: CFTimeInterval, curve: @escaping (Double) -> Double) {
        animation = (fraction, target, CACurrentMediaTime(), duration, curve)
        link?.invalidate()
        link = displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        // The display link only ticks while the window is on screen. If the window is hidden or
        // minimised mid-turn, this still clears the half-turned page from over the text.
        turnNumber += 1
        let this = turnNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) { [weak self] in
            if let self, self.turnNumber == this, self.animation != nil { self.finish() }
        }
    }

    private func stopAnimation() {
        link?.invalidate()
        link = nil
        animation = nil
    }

    @objc private func tick() {
        guard let a = animation else { return finish() }
        let t = min((CACurrentMediaTime() - a.start) / a.duration, 1)
        if t >= 1 { finish() } else { draw(fraction: a.from + (a.to - a.from) * a.curve(t)) }
    }

    private func finish() {
        stopAnimation()
        old = nil
        new = nil
        fraction = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metal.isHidden = true
        fade.isHidden = true
        fade.contents = nil
        CATransaction.commit()
    }

    var isTurning: Bool { link != nil }
}

/// The reading view's scroll view. Up and down scroll as usual; a two-finger swipe left or right
/// on a trackpad goes to the page turner instead, and so does the momentum that follows it.
final class PageScrollView: NSScrollView {
    weak var turner: PageTurnView?
    private enum Gesture { case undecided, scrolling, turning }
    private var gesture = Gesture.undecided
    private var swallowMomentum = false

    override func scrollWheel(with event: NSEvent) {
        // A mouse wheel has no phases and only ever scrolls.
        if event.phase.isEmpty && event.momentumPhase.isEmpty { return super.scrollWheel(with: event) }
        if !event.momentumPhase.isEmpty {
            // The coasting after a swipe that turned the page belongs to the turn, not to scrolling.
            if swallowMomentum {
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowMomentum = false }
                return
            }
            return super.scrollWheel(with: event)
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            gesture = .undecided
            swallowMomentum = false
        }
        if gesture == .undecided, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            gesture = Self.isTurn(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) && turner != nil ? .turning : .scrolling
        }
        switch gesture {
        case .turning:
            turner?.swipeMoved(by: SwipeTurn.fingerDX(scrollingDeltaX: event.scrollingDeltaX, invertedFromDevice: event.isDirectionInvertedFromDevice))
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                turner?.swipeEnded()
                swallowMomentum = true
            }
        case .scrolling, .undecided:
            super.scrollWheel(with: event)
        }
    }

    /// A swipe turns the page when it is clearly more sideways than up or down.
    static func isTurn(dx: CGFloat, dy: CGFloat) -> Bool { abs(dx) > abs(dy) * 1.5 }
}
