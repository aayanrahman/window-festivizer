import AppKit

/// Owns the menu-bar icon (an SF Symbol, "sparkles") and its menu, and starts the window tracker.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let tracker = WindowTracker()
    private lazy var picker = WindowPicker(tracker: tracker)
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
        if settings.enabled { SoundPlayer.shared.play(.crate) }
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
        menu.addItem(item("Choose Windows…", #selector(chooseWindows), checked: false))
        menu.addItem(.separator())

        menu.addItem(submenu("Show On", showOnMenu()))
        menu.addItem(submenu("Style", choices(WrapStyle.allCases, current: settings.style, title: \.title,
                                              action: #selector(pickStyle(_:)))))

        let themes = NSMenu()
        themes.addItem(item("Mixed (different lights for each app)", #selector(pickTheme(_:)),
                            checked: settings.themeID == Theme.mixedID, value: Theme.mixedID))
        themes.addItem(.separator())
        for theme in Theme.all {
            themes.addItem(item(theme.name, #selector(pickTheme(_:)), checked: settings.themeID == theme.id, value: theme.id))
        }
        menu.addItem(submenu("Lights", themes))

        menu.addItem(submenu("Size", choices(WrapSize.allCases, current: settings.size, title: \.title,
                                             action: #selector(pickSize(_:)))))
        menu.addItem(submenu("Pattern", choices(LightPattern.allCases, current: settings.pattern, title: \.title,
                                                action: #selector(pickPattern(_:)))))
        menu.addItem(item("Swinging Tail", #selector(toggleTail), checked: settings.tail))
        menu.addItem(item("Sounds", #selector(toggleSounds), checked: settings.sounds))
        menu.addItem(.separator())
        menu.addItem(item("Quit Window Festivizer", #selector(quit), checked: false, key: "q"))
    }

    /// All windows, the front one, or the ones you choose; then a way to choose, and to start over.
    private func showOnMenu() -> NSMenu {
        let menu = choices(ShowOn.allCases, current: settings.showOn, title: \.title, action: #selector(pickShowOn(_:)))
        menu.addItem(.separator())
        menu.addItem(item("Choose Windows…", #selector(chooseWindows), checked: false))
        if tracker.hasChoices {
            menu.addItem(item("Forget My Choices", #selector(forgetChoices), checked: false))
        }
        return menu
    }

    /// A submenu of mutually exclusive choices, with a checkmark on the current one.
    private func choices<Choice: RawRepresentable & Equatable>(_ all: [Choice], current: Choice,
                                                               title: KeyPath<Choice, String>,
                                                               action: Selector) -> NSMenu where Choice.RawValue == String {
        let menu = NSMenu()
        for choice in all {
            menu.addItem(item(choice[keyPath: title], action, checked: choice == current, value: choice.rawValue))
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

    // MARK: Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if settings.enabled { SoundPlayer.shared.play(.crate) }
    }

    @objc private func toggleTail() {
        settings.tail.toggle()
        SoundPlayer.shared.play(.donk)
    }

    @objc private func toggleSounds() {
        settings.sounds.toggle()
        // A quick sample when they come back on, so you know they work.
        SoundPlayer.shared.play(.stomp)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func chooseWindows() { picker.open() }
    @objc private func forgetChoices() { tracker.forgetChoices() }

    @objc private func pickShowOn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ShowOn(rawValue: raw) else { return }
        // Picking "Windows I Choose" with nothing chosen yet goes straight to choosing.
        if choice == .chosenWindows && !tracker.hasChoices {
            picker.open()
        } else {
            settings.showOn = choice
        }
    }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = WrapStyle(rawValue: raw) { settings.style = style }
        SoundPlayer.shared.play(.donk)
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { settings.themeID = id }
        SoundPlayer.shared.play(.donk)
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = WrapSize(rawValue: raw) { settings.size = size }
        SoundPlayer.shared.play(.donk)
    }

    @objc private func pickPattern(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let pattern = LightPattern(rawValue: raw) {
            settings.pattern = pattern
        }
        SoundPlayer.shared.play(.donk)
    }
}
