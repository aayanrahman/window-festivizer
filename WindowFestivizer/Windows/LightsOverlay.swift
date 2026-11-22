import AppKit

/// One window's lights: the strip along its top edge and, optionally, the tail hanging off its
/// top-right corner.
///
/// Each part lives in its own OverlayWindow kept directly above the window it decorates, so any
/// window in front still covers the lights properly. Two small overlays rather than one big one
/// means nothing invisible sits over the middle of your window.
final class LightsOverlay {
    let targetID: CGWindowID

    /// The decorated window, in global CoreGraphics coordinates (origin top-left of the main screen, y down).
    private(set) var frame: CGRect = .zero

    private let stripWindow = OverlayWindow.make()
    private let tailWindow = OverlayWindow.make()
    private var strip: StripLayers?
    private var tailLayers: TailLayers?
    private var geometry: WrapGeometry?
    private var chain: SwingingTail?
    private var built: Build?

    /// What the current layers were drawn for. Anything different means drawing them again.
    private struct Build: Equatable {
        var size: CGSize
        var theme: Theme
        var wrap: WrapSize
        var style: WrapStyle
        var tail: Bool
    }

    /// Bookkeeping for keeping the lights stacked above their window (see WindowTracker.keepAbove).
    var orderMisses = 0
    var lastOrderAttempt: CFTimeInterval = 0

    /// Notices the window being shaken as it's dragged.
    private var shake = ShakeDetector()

    init(targetID: CGWindowID) {
        self.targetID = targetID
    }

    /// The window numbers of this overlay's own windows.
    var windowNumbers: [Int] {
        tailLayers == nil ? [stripWindow.windowNumber] : [stripWindow.windowNumber, tailWindow.windowNumber]
    }

    /// Follow the window to `newFrame`, redrawing the lights if its size or the settings changed.
    /// Returns true if this move was the window being shaken (see ShakeDetector).
    @discardableResult
    func update(frame newFrame: CGRect, theme: Theme, wrap: WrapSize, style: WrapStyle, tail: Bool,
                beat: Int, pattern: LightPattern) -> Bool {
        let build = Build(size: newFrame.size, theme: theme, wrap: wrap, style: style, tail: tail)
        // This runs on every look at the windows (about 7 times a second even when idle), so do
        // nothing at all unless the window moved or the settings changed.
        if build == built && newFrame == frame { return false }

        let firstTime = built == nil
        let shaken = !firstTime && newFrame.origin != frame.origin
            && shake.moved(to: newFrame.origin, at: CACurrentMediaTime())
        frame = newFrame
        if build != built {
            rebuild(build, beat: beat, pattern: pattern)
        }
        guard let g = geometry else { return false }

        move(stripWindow, to: g.stripRect)
        if let t = g.tail, let tailLayers {
            let anchor = global(t.anchor)
            // A window that jumped (just appeared, or came back from another Space) gets a tail
            // hanging at rest, rather than one that swings in from far away.
            if chain == nil || distance(chain!.points[0], anchor) > 400 {
                chain = SwingingTail(anchor: anchor, lead: t.lead, segments: t.segments, segmentLength: t.segmentLength)
            }
            move(tailWindow, to: t.rect)
            tailLayers.layout(points: chain!.points, in: global(t.rect))
        }

        if firstTime { fadeIn() }
        return shaken
    }

    /// Move the tail on by `dt` seconds. Returns true while it's still swinging.
    func step(dt: CGFloat) -> Bool {
        guard let t = geometry?.tail, let tailLayers, var c = chain else { return false }
        let anchor = global(t.anchor)
        if c.isResting && c.points[0] == anchor { return false }
        c.step(anchor: anchor, dt: dt)
        chain = c
        tailLayers.layout(points: c.points, in: global(t.rect))
        return !c.isResting
    }

    /// Show this beat of the blink pattern.
    func showBeat(_ beat: Int, pattern: LightPattern, animated: Bool = true) {
        strip?.light(beat: beat, pattern: pattern, animated: animated)
        tailLayers?.light(beat: beat, pattern: pattern, animated: animated)
    }

    /// Put the lights directly above the window they decorate.
    func placeAboveTarget() {
        stripWindow.order(.above, relativeTo: Int(targetID))
        if tailLayers != nil { tailWindow.order(.above, relativeTo: Int(targetID)) }
    }

    func close() {
        stripWindow.orderOut(nil)
        tailWindow.orderOut(nil)
    }

    // MARK: Building

    private func rebuild(_ build: Build, beat: Int, pattern: LightPattern) {
        built = build
        let g = WrapGeometry(windowSize: build.size, style: build.style, scale: build.wrap.scale, tail: build.tail)
        geometry = g
        // Drawn for the sharpest display plugged in.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2

        let newStrip = StripLayers(geometry: g, theme: build.theme, scale: scale)
        newStrip.light(beat: beat, pattern: pattern, animated: false)
        install(newStrip.root, in: stripWindow)
        strip = newStrip

        if let t = g.tail {
            let newTail = TailLayers(tail: t, twist: g.twist, theme: build.theme, scale: scale)
            newTail.light(beat: beat, pattern: pattern, animated: false)
            install(newTail.root, in: tailWindow)
            tailLayers = newTail
            // A different style or size means a different chain: start it afresh. A plain resize
            // keeps it, so the tail swings as the corner moves.
            if let c = chain, c.lead != t.lead || c.segmentLength != t.segmentLength || c.points.count != t.segments + 1 {
                chain = nil
            }
        } else {
            tailLayers = nil
            chain = nil
            tailWindow.orderOut(nil)
        }
    }

    private func install(_ layer: CALayer, in window: OverlayWindow) {
        guard let host = window.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.sublayers = nil
        host.addSublayer(layer)
        CATransaction.commit()
    }

    /// The lights switching on: a quick fade the first time a window gets them.
    private func fadeIn() {
        for window in [stripWindow, tailWindow] {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.4
            window.contentView?.layer?.add(fade, forKey: "fade-in")
        }
    }

    // MARK: Coordinates

    /// Window-local (y down) → global CoreGraphics coordinates (y down from the top of the main screen).
    private func global(_ p: CGPoint) -> CGPoint { CGPoint(x: frame.minX + p.x, y: frame.minY + p.y) }
    private func global(_ r: CGRect) -> CGRect { r.offsetBy(dx: frame.minX, dy: frame.minY) }

    /// Place `window` over the window-local rectangle `r`. AppKit measures y up from the bottom of
    /// the main screen, so flip it.
    private func move(_ window: OverlayWindow, to r: CGRect) {
        let g = global(r)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = NSRect(x: g.minX, y: mainHeight - g.maxY, width: g.width, height: g.height)
        if window.frame != target { window.setFrame(target, display: false) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
