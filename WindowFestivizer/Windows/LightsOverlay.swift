import AppKit

/// One window's lights, drawn in an OverlayWindow kept directly above the window it decorates, so
/// any window in front still covers the lights properly. The overlay only covers the strip along
/// the window's top edge, so nothing invisible sits over the rest of your window.
final class LightsOverlay {
    let targetID: CGWindowID

    /// The decorated window, in global CoreGraphics coordinates (origin top-left of the main screen, y down).
    private(set) var frame: CGRect = .zero

    private let window = OverlayWindow.make()
    private var strip: StripLayers?
    private var geometry: WrapGeometry?
    private var built: Build?

    /// What the current layers were drawn for. Anything different means drawing them again.
    private struct Build: Equatable {
        var size: CGSize
        var theme: Theme
        var wrap: WrapSize
    }

    /// Bookkeeping for keeping the lights stacked above their window (see WindowTracker.keepAbove).
    var orderMisses = 0
    var lastOrderAttempt: CFTimeInterval = 0

    init(targetID: CGWindowID) {
        self.targetID = targetID
    }

    var windowNumbers: [Int] { [window.windowNumber] }

    /// Follow the window to `newFrame`, redrawing the lights if its size or the settings changed.
    func update(frame newFrame: CGRect, theme: Theme, wrap: WrapSize, beat: Int, pattern: LightPattern) {
        let build = Build(size: newFrame.size, theme: theme, wrap: wrap)
        // This runs on every look at the windows (about 7 times a second even when idle), so do
        // nothing at all unless the window moved or the settings changed.
        if build == built && newFrame == frame { return }

        let firstTime = built == nil
        frame = newFrame
        if build != built {
            rebuild(build, beat: beat, pattern: pattern)
        }
        guard let g = geometry else { return }

        // AppKit measures y up from the bottom of the main screen, so flip the strip's rectangle.
        let r = g.stripRect.offsetBy(dx: frame.minX, dy: frame.minY)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
        if window.frame != target { window.setFrame(target, display: false) }

        if firstTime { fadeIn() }
    }

    /// Show this beat of the blink pattern.
    func showBeat(_ beat: Int, pattern: LightPattern, animated: Bool = true) {
        strip?.light(beat: beat, pattern: pattern, animated: animated)
    }

    /// Put the lights directly above the window they decorate.
    func placeAboveTarget() {
        window.order(.above, relativeTo: Int(targetID))
    }

    func close() {
        window.orderOut(nil)
    }

    private func rebuild(_ build: Build, beat: Int, pattern: LightPattern) {
        built = build
        let g = WrapGeometry(windowSize: build.size, scale: build.wrap.scale)
        geometry = g
        // Drawn for the sharpest display plugged in.
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let newStrip = StripLayers(geometry: g, theme: build.theme, scale: scale)
        newStrip.light(beat: beat, pattern: pattern, animated: false)

        guard let host = window.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.sublayers = nil
        host.addSublayer(newStrip.root)
        CATransaction.commit()
        strip = newStrip
    }

    /// The lights switching on: a quick fade the first time a window gets them.
    private func fadeIn() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.4
        window.contentView?.layer?.add(fade, forKey: "fade-in")
    }
}
