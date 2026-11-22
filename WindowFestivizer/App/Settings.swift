import CoreGraphics
import Foundation

/// How chunky the lights are. Everything (bulb length, wire thickness, spacing) scales from `scale`.
enum WrapSize: String, CaseIterable {
    case slim, regular, chunky

    var title: String { rawValue.capitalized }

    var scale: CGFloat {
        switch self {
        case .slim: return 1.25
        case .regular: return 1.6
        case .chunky: return 2
        }
    }
}

/// How the lights are put on a window. See WrapGeometry for how each is laid out.
enum WrapStyle: String, CaseIterable {
    /// Wound round the top of the window in an uneven coil, the way the Festivizer winds them round a gun.
    case wrapped
    /// Laid along the window's top edge like a scarf.
    case laidOnTop

    var title: String {
        switch self {
        case .wrapped: return "Wrapped Around"
        case .laidOnTop: return "Laid on Top"
        }
    }
}

/// How the bulbs blink.
enum LightPattern: String, CaseIterable {
    /// Three colours, two lit at a time, like the Festivizer. See FestivizerPattern.swift.
    case festivizer
    /// Every bulb on, all the time.
    case steady

    var title: String {
        switch self {
        case .festivizer: return "Festivizer (two of three colours lit)"
        case .steady: return "Steady"
        }
    }
}

/// Which windows get lights, before the per-app checkboxes are applied.
enum ShowOn: String, CaseIterable {
    case allWindows
    /// Only the window you're working in.
    case frontWindow
    /// Only what you picked with Choose Windows: whole apps, or single windows.
    case chosenWindows

    var title: String {
        switch self {
        case .allWindows: return "All Windows"
        case .frontWindow: return "Front Window Only"
        case .chosenWindows: return "Only Windows I Choose"
        }
    }
}

/// The choices in the menu, saved in UserDefaults so they survive a restart.
///
/// Values are read from UserDefaults once at launch and kept in memory, because the tracker asks
/// for them on every look at the windows. Setting one writes it back and calls `onChange`.
final class Settings {
    static let shared = Settings()

    /// Called after any setting changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    var enabled: Bool { didSet { save(enabled, "enabled") } }
    var themeID: String { didSet { save(themeID, "theme") } }
    var size: WrapSize { didSet { save(size.rawValue, "size") } }
    var style: WrapStyle { didSet { save(style.rawValue, "style") } }
    /// Whether the end of the cable hangs off the window's right corner and swings.
    var tail: Bool { didSet { save(tail, "tail") } }
    /// Whether the TF2 sound effects play (see Sounds.swift).
    var sounds: Bool { didSet { save(sounds, "sounds") } }
    var pattern: LightPattern { didSet { save(pattern.rawValue, "pattern") } }
    var showOn: ShowOn { didSet { save(showOn.rawValue, "showOn") } }
    /// Apps picked with Choose Windows, by name (like "Safari"). With Show On set to Windows I
    /// Choose, every window of these apps gets lights. Remembered across restarts.
    var chosenApps: Set<String> { didSet { save(chosenApps.sorted(), "chosenApps") } }

    private init() {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        themeID = defaults.string(forKey: "theme") ?? Theme.blu.id
        size = defaults.string(forKey: "size").flatMap(WrapSize.init(rawValue:)) ?? .regular
        style = defaults.string(forKey: "style").flatMap(WrapStyle.init(rawValue:)) ?? .wrapped
        tail = defaults.object(forKey: "tail") as? Bool ?? true
        sounds = defaults.object(forKey: "sounds") as? Bool ?? true
        pattern = defaults.string(forKey: "pattern").flatMap(LightPattern.init(rawValue:)) ?? .festivizer
        showOn = defaults.string(forKey: "showOn").flatMap(ShowOn.init(rawValue:)) ?? .allWindows
        chosenApps = Set(defaults.stringArray(forKey: "chosenApps") ?? [])
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    /// The theme for a window belonging to `app` (the app's name, like "Safari").
    func theme(forApp app: String) -> Theme {
        if themeID == Theme.mixedID {
            return Theme.all[Int(Settings.stableHash(app) % UInt32(Theme.all.count))]
        }
        // A theme saved by an older version that no longer exists falls back to BLU.
        return Theme.all.first { $0.id == themeID } ?? .blu
    }

    /// FNV-1a hash. Swift's own `hashValue` changes every launch, and an app should keep its colours.
    static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash
    }
}
