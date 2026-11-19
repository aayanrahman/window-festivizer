import AppKit

/// One window's lights: the wrap along its top edge and the tail hanging off its right corner.
///
/// Each part lives in its own OverlayWindow, kept directly above the window it decorates, so any
/// window in front still covers the lights properly. Two small windows rather than one big one
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
    private var tail: SwingingTail?
    private var built: Build?

    /// What the current layers were made for. Anything different means making them again.
    private struct Build: Equatable {
        var size: CGSize
        var theme: Theme
        var wrap: WrapSize
        var swing: Bool
    }

    /// Bookkeeping for keeping the lights stacked above their window (see WindowTracker.keepAbove).
    var orderMisses = 0
    var lastOrderAttempt: CFTimeInterval = 0

    init(targetID: CGWindowID) {
        self.targetID = targetID
    }

    /// The window numbers of this overlay's own windows.
    var windowNumbers: [Int] {
        tailLayers == nil ? [stripWindow.windowNumber] : [stripWindow.windowNumber, tailWindow.windowNumber]
    }

    /// Follow the window to `newFrame`, rebuilding the lights if its size or the settings changed.
    func update(frame newFrame: CGRect, theme: Theme, wrap: WrapSize, swing: Bool, beat: Int, pattern: LightPattern) {
        let build = Build(size: newFrame.size, theme: theme, wrap: wrap, swing: swing)
        // This runs on every look at the windows (10 times a second even when idle), so do
        // nothing at all unless the window moved or the settings changed.
        if build == built && newFrame == frame { return }

        let firstTime = built == nil
        frame = newFrame
        if build != built {
            rebuild(build, beat: beat, pattern: pattern)
        }
        guard let g = geometry else { return }

        move(stripWindow, to: g.stripRect)

        if let tailLayers {
            let anchor = global(g.tailAnchor)
            // A window that jumped (just appeared, or came back from another Space) gets a tail
            // hanging at rest rather than one that swings in from far away.
            if tail == nil || distance(tail!.points[0], anchor) > 400 {
                tail = SwingingTail(anchor: anchor, segments: g.tailSegments, segmentLength: g.tailSegmentLength)
            }
            move(tailWindow, to: g.tailRect)
            tailLayers.layout(points: tail!.points, in: global(g.tailRect))
        }

        if firstTime { fadeIn() }
    }

    /// Move the tail on by `dt` seconds. Returns true while it's still swinging.
    func step(dt: CGFloat) -> Bool {
        guard let g = geometry, let tailLayers, var t = tail else { return false }
        let anchor = global(g.tailAnchor)
        if t.isResting && t.points[0] == anchor { return false }
        t.step(anchor: anchor, dt: dt)
        tail = t
        tailLayers.layout(points: t.points, in: global(g.tailRect))
        return !t.isResting
    }

    /// Show this beat of the blink pattern.
    func showBeat(_ beat: Int, pattern: LightPattern, animated: Bool = true) {
        strip?.bank.light(beat: beat, pattern: pattern, animated: animated)
        tailLayers?.bank.light(beat: beat, pattern: pattern, animated: animated)
    }

    /// Put the light windows directly above the window they decorate.
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
        let g = WrapGeometry(windowSize: build.size, radius: build.wrap.radius)
        geometry = g
        // Sharp enough for the sharpest display plugged in.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2

        let newStrip = StripLayers(geometry: g, theme: build.theme, scale: scale)
        install(newStrip.root, in: stripWindow)
        strip = newStrip

        if build.swing {
            let newTail = TailLayers(geometry: g, theme: build.theme, scale: scale)
            install(newTail.root, in: tailWindow)
            tailLayers = newTail
            // A different wrap size means different link lengths: start the chain afresh.
            if let t = tail, t.segmentLength != g.tailSegmentLength || t.points.count != g.tailSegments + 1 {
                tail = nil
            }
        } else {
            tailLayers = nil
            tail = nil
            tailWindow.orderOut(nil)
        }
        showBeat(beat, pattern: pattern, animated: false)
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

    /// Place `window` over the window-local rectangle `r`. AppKit measures y up from the bottom
    /// of the main screen, so flip it.
    private func move(_ window: OverlayWindow, to r: CGRect) {
        let g = global(r)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = NSRect(x: g.minX, y: mainHeight - g.maxY, width: g.width, height: g.height)
        if window.frame != target { window.setFrame(target, display: false) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
