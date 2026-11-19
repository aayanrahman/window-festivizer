import AppKit

/// A borderless, see-through window that clicks pass straight through and that never takes focus.
/// The lights are drawn in these, floating just above the window they decorate.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Let it sit partly off screen or under the menu bar, wherever its window is.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    static func make() -> OverlayWindow {
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        // Not something VoiceOver should land on.
        window.setAccessibilityElement(false)

        // A layer-hosting view: we hand it a layer and draw only with layers.
        let view = NSView(frame: .zero)
        view.layer = CALayer()
        view.wantsLayer = true
        window.contentView = view
        return window
    }
}
