import AppKit

/// Owns the menu-bar icon (an SF Symbol, "sparkles") and its menu, and starts the window tracker.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let tracker = WindowTracker()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy at a time. A new launch (say, Cmd-R in Xcode while an installed copy is running)
        // asks any older copy to quit, which takes its lights off as it goes.
        if let id = Bundle.main.bundleIdentifier {
            for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other != .current {
                other.terminate()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Window Festivizer")
            button.toolTip = "Window Festivizer"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Any change in the menu is applied to every window straight away.
        settings.onChange = { [weak self] in self?.tracker.settingsChanged() }
        tracker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
    }

    // MARK: Menu

    /// The menu is rebuilt every time it opens, so the checkmarks always match the settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item(settings.enabled ? "Lights On" : "Lights Off", #selector(toggleEnabled),
                          checked: settings.enabled))
        menu.addItem(.separator())

        menu.addItem(submenu("Show On", showOnMenu()))

        let themes = NSMenu()
        themes.addItem(item("Mixed (different lights for each app)", #selector(pickTheme(_:)),
                            checked: settings.themeID == Theme.mixedID, value: Theme.mixedID))
        themes.addItem(.separator())
        for theme in Theme.all {
            themes.addItem(item(theme.name, #selector(pickTheme(_:)),
                                checked: settings.themeID == theme.id, value: theme.id))
        }
        menu.addItem(submenu("Lights", themes))

        let sizes = NSMenu()
        for size in WrapSize.allCases {
            sizes.addItem(item(size.title, #selector(pickSize(_:)), checked: settings.size == size, value: size.rawValue))
        }
        menu.addItem(submenu("Size", sizes))

        let patterns = NSMenu()
        for pattern in LightPattern.allCases {
            patterns.addItem(item(pattern.title, #selector(pickPattern(_:)),
                                  checked: settings.pattern == pattern, value: pattern.rawValue))
        }
        menu.addItem(submenu("Pattern", patterns))
        menu.addItem(.separator())
        menu.addItem(item("Quit Window Festivizer", #selector(quit), checked: false, key: "q"))
    }

    /// All windows or just the front one, then a checkbox for every app seen with a window since
    /// launch (plus any app already unticked, so it can be ticked again).
    private func showOnMenu() -> NSMenu {
        let menu = NSMenu()
        for choice in ShowOn.allCases {
            menu.addItem(item(choice.title, #selector(pickShowOn(_:)), checked: settings.showOn == choice,
                              value: choice.rawValue))
        }
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Apps", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let apps = tracker.recentApps.union(settings.skippedApps).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        if apps.isEmpty {
            let none = NSMenuItem(title: "No windows yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for app in apps {
            menu.addItem(item(app, #selector(toggleApp(_:)), checked: !settings.skippedApps.contains(app), value: app))
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, checked: Bool,
                      value: String? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        item.representedObject = value
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pickShowOn(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = ShowOn(rawValue: raw) { settings.showOn = choice }
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? String else { return }
        if settings.skippedApps.contains(app) {
            settings.skippedApps.remove(app)
        } else {
            settings.skippedApps.insert(app)
        }
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { settings.themeID = id }
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = WrapSize(rawValue: raw) { settings.size = size }
    }

    @objc private func pickPattern(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let pattern = LightPattern(rawValue: raw) {
            settings.pattern = pattern
        }
    }
}
