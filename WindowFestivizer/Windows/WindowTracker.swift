import AppKit

/// Watches every window on screen and keeps a set of lights on each one.
///
/// Like Window Scarves, it only uses public APIs that need no permissions: CGWindowListCopyWindowInfo
/// says where every window is and how they're stacked. It looks about 7 times a second while nothing
/// is happening, and once per screen refresh while something is moving or a tail is still swinging.
final class WindowTracker: NSObject {
    private let settings = Settings.shared
    private let myPID = getpid()
    private var overlays: [CGWindowID: LightsOverlay] = [:]

    /// Ticks while idle.
    private var timer: Timer?
    /// Ticks while something's moving: once per screen refresh, just after the screen updates (see
    /// `setSpeed`).
    private var displayLink: CADisplayLink?
    private var beatTimer: Timer?
    private var isFast = false
    /// Keep looking quickly until this time.
    private var fastUntil: CFTimeInterval = 0
    private var lastTick = CACurrentMediaTime()
    private var mouseMonitor: Any?

    /// Where each decorated window was at the last look, to notice movement.
    private var lastFrames: [CGWindowID: CGRect] = [:]
    /// New windows wait until they've held still for a moment: they animate open, and report
    /// odd sizes while they do.
    private var settling: [CGWindowID: (frame: CGRect, since: CFTimeInterval)] = [:]

    /// Which beat of the blink pattern we're on. Shared by every window so they all blink together.
    private(set) var beat = 0

    /// Single windows picked with Choose Windows (Option-click). Window numbers don't survive a
    /// restart, so these last until the app quits; whole apps are remembered in Settings.
    private(set) var chosenWindows: Set<CGWindowID> = []

    /// Every window that could have lights right now, front to back, and every real app window
    /// (including popovers and full-screen ones), for the window picker.
    private var candidates: [Target] = []
    private var allWindows: [Target] = []

    /// Every window that's had lights since launch. Only a window never seen before gets the
    /// new-window chime, so windows coming back from another Space or from being hidden don't.
    private var seenWindows: Set<CGWindowID> = []
    /// No new-window chime until this time: just after launch (every window is new then), and just
    /// after a menu change or a choice in the picker, which play their own sounds.
    private var chimeQuietUntil: CFTimeInterval = 0
    private var lastChime: CFTimeInterval = 0
    private var lastHit: CFTimeInterval = 0

    /// Asking macOS for the window list is most of this app's idle cost, so while nothing is
    /// happening it only looks about 7 times a second. Mouse presses and drags switch to the fast
    /// rate at once; only keyboard-driven moves (window-manager shortcuts) can lag, by under 0.15 s.
    private static let idleInterval = 0.15

    /// Things that own ordinary windows but aren't apps you'd want to decorate.
    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center", "SystemUIServer",
        "Spotlight", "WindowManager", "screencaptureui", "Screenshot", "loginwindow", "Wallpaper",
        "TextInputMenuAgent", "universalAccessAuthWarn", "SecurityAgent", "CoreServicesUIAgent",
        "UserNotificationCenter",
    ]

    /// This app's own names as the window list reports them. Windows from any copy of this app are
    /// ignored, so two copies (say, one run from Xcode and one installed) never decorate each other's
    /// lights or fight over stacking.
    private let ownNames: Set<String> = {
        let info = Bundle.main.infoDictionary ?? [:]
        return Set([ProcessInfo.processInfo.processName, info["CFBundleDisplayName"] as? String,
                    info["CFBundleName"] as? String].compactMap { $0 })
    }()

    private struct Target {
        let id: CGWindowID
        let frame: CGRect
        let owner: String
        let pid: pid_t
        /// Position in the stack, 0 = frontmost.
        let index: Int
    }

    // MARK: Starting and stopping

    func start() {
        chimeQuietUntil = CACurrentMediaTime() + 2.5
        setSpeed(fast: false)

        let beats = Timer(timeInterval: FestivizerPattern.beat, target: self, selector: #selector(nextBeat),
                          userInfo: nil, repeats: true)
        beats.tolerance = 0.03
        RunLoop.main.add(beats, forMode: .common)
        beatTimer = beats

        // A click often starts a drag: speed up straight away rather than at the next look.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            self?.wake()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(somethingChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(somethingChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        displayLink?.invalidate()
        beatTimer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        removeAll()
    }

    /// Settings changed. Each window's lights redraw themselves if their theme or size changed
    /// (LightsOverlay.update checks), windows that should no longer have lights lose them, and a new
    /// pattern takes effect straight away rather than at the next beat.
    func settingsChanged() {
        chimeQuietUntil = CACurrentMediaTime() + 1
        refresh()
        let pattern = settings.pattern
        for overlay in overlays.values { overlay.showBeat(beat, pattern: pattern) }
    }

    private func removeAll() {
        for overlay in overlays.values { overlay.close() }
        overlays.removeAll()
        lastFrames.removeAll()
        settling.removeAll()
    }

    // MARK: Ticking

    /// Something may be about to move: look now, and keep looking quickly for a bit.
    func wake() {
        fastUntil = max(fastUntil, CACurrentMediaTime() + 0.5)
        if !isFast { setSpeed(fast: true) }
        refresh()
    }

    @objc private func somethingChanged(_ note: Notification) { wake() }

    /// Debugging aid: launch with the environment variable FESTIVIZER_LOG=1 (in Xcode: Product >
    /// Scheme > Edit Scheme > Run > Arguments) to print when and why the tracker speeds up.
    private let logging = ProcessInfo.processInfo.environment["FESTIVIZER_LOG"] != nil
    private func log(_ message: @autoclosure () -> String) {
        guard logging else { return }
        FileHandle.standardError.write(Data(String(format: "%8.2f  %@\n", CACurrentMediaTime(), message()).utf8))
    }

    /// Fast: a display link, which calls `tick` once per screen refresh, right after the screen
    /// updates. Each look at the windows then lands at the same point in every frame, so the
    /// lights stay the same distance behind a moving window instead of jittering between one and
    /// two frames behind, as they did with a plain 60 Hz timer drifting against the display.
    /// Idle: a slow timer that macOS can line up with other work to save power.
    private func setSpeed(fast: Bool) {
        log(fast ? "fast (every screen refresh)" : "idle (~7/s)")
        isFast = fast
        timer?.invalidate()
        timer = nil
        displayLink?.invalidate()
        displayLink = nil
        if fast, let link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(tick)) {
            link.add(to: .main, forMode: .common)
            displayLink = link
            return
        }
        let t = Timer(timeInterval: fast ? 1.0 / 120 : Self.idleInterval, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = fast ? 0 : 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 1.0 / 30))
        lastTick = now
        // With the button held, a drag could start any moment.
        if NSEvent.pressedMouseButtons & 1 != 0 { fastUntil = max(fastUntil, now + 0.3) }

        refresh()

        var swinging = false
        for overlay in overlays.values {
            if overlay.step(dt: dt) { swinging = true }
        }

        let wantFast = swinging || now < fastUntil
        if wantFast != isFast { setSpeed(fast: wantFast) }
    }

    @objc private func nextBeat() {
        beat += 1
        let pattern = settings.pattern
        for overlay in overlays.values { overlay.showBeat(beat, pattern: pattern) }
    }

    // MARK: Looking at the windows

    func refresh() {
        guard settings.enabled else {
            if !overlays.isEmpty { removeAll() }
            return
        }
        // Kept as NSDictionary rather than [String: Any]: converting every window's info into Swift
        // dictionaries was a fifth of this app's idle CPU time.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [NSDictionary] else { return }
        let now = CACurrentMediaTime()
        let screens = screenRects()

        // Every real app window, front to back, plus everything's place in the stack.
        var windows: [Target] = []
        var stackIndex: [Int: Int] = [:]   // window number → position, 0 = frontmost
        var ownerAt: [pid_t] = []          // which app owns the window at each position
        for (i, info) in list.enumerated() {
            let number = info[kCGWindowNumber] as? Int ?? 0
            let pid = (info[kCGWindowOwnerPID] as? Int).map { pid_t($0) } ?? 0
            stackIndex[number] = i
            ownerAt.append(pid)

            guard info[kCGWindowLayer] as? Int == 0, pid != myPID else { continue }
            let owner = info[kCGWindowOwnerName] as? String ?? ""
            guard !Self.ignoredOwners.contains(owner), !ownNames.contains(owner) else { continue }
            if let alpha = info[kCGWindowAlpha] as? Double, alpha < 0.1 { continue }
            guard let bounds = info[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 200, frame.height >= 140 else { continue }
            windows.append(Target(id: CGWindowID(number), frame: frame, owner: owner, pid: pid, index: i))
        }

        var targets: [Target] = []
        for (k, w) in windows.enumerated() {
            if fillsScreen(w.frame, screens) { continue }
            // A window that already has lights keeps them, even if it now looks like a popover.
            if overlays[w.id] == nil, isPopover(w, above: windows[(k + 1)...]) { continue }
            targets.append(w)
        }
        candidates = targets
        allWindows = windows

        // The Show On menu.
        switch settings.showOn {
        case .allWindows: break
        case .frontWindow: targets = Array(targets.prefix(1))
        case .chosenWindows: targets.removeAll { !isChosen($0) }
        }

        targets = targets.filter { t in
            // Windows already lit, and windows just picked by hand, light up straight away.
            if overlays[t.id] != nil || chosenWindows.contains(t.id) { return true }
            if let s = settling[t.id], s.frame == t.frame {
                if now - s.since >= 0.18 {
                    settling[t.id] = nil
                    return true
                }
            } else {
                settling[t.id] = (t.frame, now)
                log("new window from \(t.owner), waiting for it to hold still")
            }
            fastUntil = max(fastUntil, now + 0.3)
            return false
        }
        if settling.count > 64 { settling.removeAll() }

        // If anything moved, appeared or vanished, keep looking quickly for a bit.
        let frames = Dictionary(targets.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        if frames != lastFrames {
            log("windows moved, appeared or vanished: \(frames.count) decorated")
            lastFrames = frames
            fastUntil = max(fastUntil, now + 0.5)
        }

        // Windows that have gone (closed, minimised, on another Space) or that the Show On menu now
        // leaves out lose their lights.
        for (id, overlay) in overlays where frames[id] == nil {
            overlay.close()
            overlays[id] = nil
        }

        let wrap = settings.size, style = settings.style, tail = settings.tail, pattern = settings.pattern
        var brandNew = false
        for t in targets {
            let overlay = overlays[t.id] ?? {
                let made = LightsOverlay(targetID: t.id)
                overlays[t.id] = made
                if seenWindows.insert(t.id).inserted { brandNew = true }
                return made
            }()
            let shaken = overlay.update(frame: t.frame, theme: settings.theme(forApp: t.owner), wrap: wrap,
                                        style: style, tail: tail, beat: beat, pattern: pattern)
            // A ding for every swing of a shake, but not faster than they can be told apart.
            if shaken && now - lastHit > 0.08 {
                lastHit = now
                SoundPlayer.shared.play(.shake)
            }
            keepAbove(overlay, t, stackIndex: stackIndex, ownerAt: ownerAt, now: now)
        }
        if brandNew && now > chimeQuietUntil && now - lastChime > 1.5 {
            lastChime = now
            SoundPlayer.shared.play(.newWindow)
        }
    }

    /// Keep an overlay's windows directly above the window they decorate.
    ///
    /// Clicking a window brings it to the front, over its own lights, so this puts them back on
    /// top. If something keeps sitting in between, it tries less and less often rather than
    /// fighting over it (which would flicker).
    private func keepAbove(_ overlay: LightsOverlay, _ t: Target, stackIndex: [Int: Int], ownerAt: [pid_t],
                           now: CFTimeInterval) {
        let numbers = overlay.windowNumbers
        let positions = numbers.compactMap { stackIndex[$0] }
        var inPlace = positions.count == numbers.count && positions.allSatisfy { $0 < t.index }
        if inPlace, let top = positions.min() {
            // Nothing may sit between the lights and their window, except that app's own
            // drop-downs and sheets.
            let mine = Set(positions)
            for i in top..<t.index where !mine.contains(i) && ownerAt[i] != t.pid {
                inPlace = false
                break
            }
        }
        if inPlace {
            overlay.orderMisses = 0
            return
        }
        let wait: CFTimeInterval = overlay.orderMisses < 3 ? 0 : (overlay.orderMisses < 12 ? 1 : 10)
        guard now - overlay.lastOrderAttempt >= wait else { return }
        overlay.placeAboveTarget()
        overlay.lastOrderAttempt = now
        overlay.orderMisses += 1
        log("re-stacked the lights on \(t.owner) (attempt \(overlay.orderMisses))")
        fastUntil = max(fastUntil, now + 0.2)
    }

    // MARK: Choosing windows

    /// A window the picker can point at.
    struct PickableWindow: Equatable {
        let id: CGWindowID
        let frame: CGRect
        let app: String
        /// Lit because its whole app was chosen.
        let appChosen: Bool
        /// Lit because this one window was chosen.
        let windowChosen: Bool
        var isChosen: Bool { appChosen || windowChosen }
    }

    private func isChosen(_ t: Target) -> Bool {
        settings.chosenApps.contains(t.owner) || chosenWindows.contains(t.id)
    }

    /// The window a click at `point` (global CoreGraphics coordinates) would land on, if it's one
    /// that can have lights.
    func window(at point: CGPoint) -> PickableWindow? {
        // The frontmost real window under the point decides, even if it's one that can't have
        // lights (a popover, say), so the picker never points at a window hidden behind it.
        guard let hit = allWindows.first(where: { $0.frame.contains(point) }),
              candidates.contains(where: { $0.id == hit.id }) else { return nil }
        return PickableWindow(id: hit.id, frame: hit.frame, app: hit.owner,
                              appChosen: settings.chosenApps.contains(hit.owner),
                              windowChosen: chosenWindows.contains(hit.id))
    }

    /// Choose a window, or take it back. Choosing picks its whole app (remembered across restarts),
    /// or with `justThisWindow` only that one window. Taking back undoes whichever choice lit it.
    func toggle(_ window: PickableWindow, justThisWindow: Bool) {
        chimeQuietUntil = CACurrentMediaTime() + 1
        if window.isChosen {
            settings.chosenApps.remove(window.app)
            chosenWindows.remove(window.id)
        } else if justThisWindow {
            chosenWindows.insert(window.id)
        } else {
            settings.chosenApps.insert(window.app)
        }
        refresh()
    }

    /// Forget every choice made with Choose Windows.
    func forgetChoices() {
        chosenWindows.removeAll()
        settings.chosenApps.removeAll()
    }

    /// Whether anything has been chosen with Choose Windows.
    var hasChoices: Bool { !chosenWindows.isEmpty || !settings.chosenApps.isEmpty }

    // MARK: Which windows get lights

    /// Every screen, in global CoreGraphics coordinates.
    private func screenRects() -> [CGRect] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: mainHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    /// Full-screen and edge-to-edge windows go without.
    private func fillsScreen(_ r: CGRect, _ screens: [CGRect]) -> Bool {
        screens.contains {
            abs(r.minX - $0.minX) < 2 && abs(r.maxX - $0.maxX) < 2 && abs(r.maxY - $0.maxY) < 2 && r.minY - $0.minY < 60
        }
    }

    /// A small window sitting mostly on top of a much bigger one from the same app is probably a
    /// popover, sheet or dialog, so it goes without too.
    private func isPopover(_ w: Target, above behind: ArraySlice<Target>) -> Bool {
        guard w.frame.width <= 560, w.frame.height <= 640,
              let parent = behind.first, parent.pid == w.pid else { return false }
        let area = w.frame.width * w.frame.height
        let overlap = w.frame.intersection(parent.frame)
        let covered = overlap.isNull ? 0 : overlap.width * overlap.height
        return area < 0.5 * parent.frame.width * parent.frame.height && covered >= 0.5 * area
    }
}
