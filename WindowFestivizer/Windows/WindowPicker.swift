import AppKit

/// Choose Windows: click the windows you want lights on.
///
/// A see-through sheet covers every screen and dims it a little. The window under the pointer is
/// spotlit, with a big label saying what a click will do. Clicking a window puts lights on every
/// window of that app (remembered across restarts); Option-clicking puts them on just that window
/// (until the app quits). Clicking a window that's already chosen takes its lights off. Each click
/// takes effect at once, under the spotlight, and the picker stays open so you can choose as many
/// as you like. Done, Return or Esc closes it.
///
/// While it's open, Show On is set to Windows I Choose, so only what you pick has lights.
final class WindowPicker {
    private let tracker: WindowTracker
    private var sheets: [PickerSheet] = []
    /// The app you were using before the picker opened, given focus back when it closes.
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { !sheets.isEmpty }

    init(tracker: WindowTracker) {
        self.tracker = tracker
    }

    func open() {
        guard !isOpen else { return }
        Settings.shared.showOn = .chosenWindows
        tracker.wake()
        previousApp = NSWorkspace.shared.frontmostApplication
        let main = NSScreen.screens.first
        for screen in NSScreen.screens {
            let sheet = PickerSheet(screen: screen, picker: self, showsBanner: screen == main)
            sheets.append(sheet)
            sheet.orderFrontRegardless()
        }
        NSApp.activate()
        sheets.first?.makeKey()
        pointerMoved()
    }

    func close() {
        for sheet in sheets { sheet.orderOut(nil) }
        sheets.removeAll()
        previousApp?.activate()
        previousApp = nil
    }

    /// Move the spotlight to whatever window is under the pointer now.
    func pointerMoved() {
        let target = tracker.window(at: Self.global(NSEvent.mouseLocation))
        for sheet in sheets { sheet.spotlight(target) }
    }

    func clicked(justThisWindow: Bool) {
        guard let target = tracker.window(at: Self.global(NSEvent.mouseLocation)) else { return }
        tracker.toggle(target, justThisWindow: justThisWindow)
        SoundPlayer.shared.play(target.isChosen ? .stomp : .achievement)
        pointerMoved()
    }

    /// AppKit screen coordinates (y up from the bottom of the main screen) → global CoreGraphics
    /// coordinates (y down from its top), which is what the window list uses.
    static func global(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }
}

/// The dimmed, click-catching sheet over one screen.
private final class PickerSheet: NSWindow {
    private let view: PickerView

    init(screen: NSScreen, picker: WindowPicker, showsBanner: Bool) {
        view = PickerView(screenFrame: screen.frame, picker: picker)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above every ordinary window (and their lights), below the menu bar and the Dock.
        level = .floating
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
        setFrame(screen.frame, display: false)
        if showsBanner { view.addBanner() }
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }

    func spotlight(_ window: WindowTracker.PickableWindow?) {
        view.target = window
    }
}

private final class PickerView: NSView {
    private weak var picker: WindowPicker?
    /// This screen's frame in AppKit screen coordinates.
    private let screenFrame: NSRect
    private var banner: NSView?

    var target: WindowTracker.PickableWindow? {
        didSet { if target != oldValue { needsDisplay = true } }
    }

    init(screenFrame: NSRect, picker: WindowPicker) {
        self.screenFrame = screenFrame
        self.picker = picker
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseMoved(with event: NSEvent) {
        if isOverBanner(event) { target = nil } else { picker?.pointerMoved() }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isOverBanner(event) else { return }
        picker?.clicked(justThisWindow: event.modifierFlags.contains(.option))
    }

    override func keyDown(with event: NSEvent) {
        // Esc or Return.
        if event.keyCode == 53 || event.keyCode == 36 { picker?.close() } else { super.keyDown(with: event) }
    }

    private func isOverBanner(_ event: NSEvent) -> Bool {
        guard let banner else { return false }
        return banner.frame.contains(convert(event.locationInWindow, from: nil))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        guard let target, let rect = local(target.frame) else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            dim.fill()
            return
        }
        // Dim everything except the window under the pointer.
        let hole = NSBezierPath(roundedRect: rect, xRadius: WrapGeometry.cornerRadius, yRadius: WrapGeometry.cornerRadius)
        dim.append(hole)
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        // Nearly invisible, but not completely clear: a fully clear pixel would let the click
        // through to the window underneath instead of to the picker.
        NSColor.white.withAlphaComponent(0.02).setFill()
        hole.fill()

        // A bold outline: green when it's chosen, the accent colour when it isn't yet.
        let colour = target.isChosen ? NSColor.systemGreen : NSColor.controlAccentColor
        colour.withAlphaComponent(0.45).setStroke()
        hole.lineWidth = 10
        hole.stroke()
        NSColor.white.setStroke()
        hole.lineWidth = 3
        hole.stroke()

        drawLabel(for: target, around: rect, colour: colour)
    }

    /// A big pill saying what a click will do, centred just above the window (or just inside its
    /// top edge, if there's no room above).
    private func drawLabel(for target: WindowTracker.PickableWindow, around rect: NSRect, colour: NSColor) {
        let title: String
        let detail: String
        if target.appChosen {
            title = "Click to take the lights off \(target.app)"
            detail = "Every \(target.app) window has lights"
        } else if target.windowChosen {
            title = "Click to take the lights off this window"
            detail = "Just this \(target.app) window has lights"
        } else {
            title = "Click to put lights on \(target.app)"
            detail = "Option-click for just this window"
        }
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let detailText = NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ])
        let padding = NSSize(width: 26, height: 14)
        let gap: CGFloat = 4
        let size = NSSize(width: max(titleText.size().width, detailText.size().width) + 2 * padding.width,
                          height: titleText.size().height + gap + detailText.size().height + 2 * padding.height)
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 16)
        if origin.y + size.height > bounds.maxY - 40 { origin.y = rect.maxY - size.height - 24 }
        origin.x = min(max(origin.x, 16), bounds.maxX - size.width - 16)
        let pill = NSRect(origin: origin, size: size)

        let shape = NSBezierPath(roundedRect: pill, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor.black.withAlphaComponent(0.78).setFill()
        shape.fill()
        colour.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        detailText.draw(at: NSPoint(x: pill.midX - detailText.size().width / 2, y: pill.minY + padding.height))
        titleText.draw(at: NSPoint(x: pill.midX - titleText.size().width / 2,
                                   y: pill.minY + padding.height + detailText.size().height + gap))
    }

    /// A window's frame (global CoreGraphics coordinates) in this view, or nil if it's not on this screen.
    private func local(_ frame: CGRect) -> NSRect? {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.minX - screenFrame.minX, y: mainHeight - frame.maxY - screenFrame.minY,
                          width: frame.width, height: frame.height)
        return rect.intersects(bounds) ? rect : nil
    }

    // MARK: Banner

    /// The instructions and the Done button, at the top of the main screen.
    func addBanner() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 18
        backdrop.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "Choose Windows")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let hint = NSTextField(labelWithString: "Click the windows you want lights on. Click again to take them off.")
        hint.font = .systemFont(ofSize: 15)
        hint.textColor = .secondaryLabelColor
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\r"
        done.bezelStyle = .push
        done.controlSize = .large

        let words = NSStackView(views: [title, hint])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 4
        let row = NSStackView(views: [words, done])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 32
        row.edgeInsets = NSEdgeInsets(top: 20, left: 28, bottom: 20, right: 24)
        row.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(row)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            row.topAnchor.constraint(equalTo: backdrop.topAnchor),
            row.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            backdrop.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Clear of the menu bar.
            backdrop.topAnchor.constraint(equalTo: topAnchor, constant: 64),
        ])
        banner = backdrop
    }

    @objc private func finish() { picker?.close() }
}
