import CoreGraphics
import Foundation

/// How chunky the wrap is.
///
/// The number is the radius of the imaginary pole the lights spiral around, in points. Everything
/// else (bulb size, glow, spacing between turns) scales from it.
enum WrapSize: String, CaseIterable {
    case slim, regular, chunky

    var title: String { rawValue.capitalized }

    var radius: CGFloat {
        switch self {
        case .slim: return 8
        case .regular: return 11
        case .chunky: return 15
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
    var pattern: LightPattern { didSet { save(pattern.rawValue, "pattern") } }
    var swing: Bool { didSet { save(swing, "swing") } }

    private init() {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        themeID = defaults.string(forKey: "theme") ?? Theme.festivizer.id
        size = defaults.string(forKey: "size").flatMap(WrapSize.init(rawValue:)) ?? .slim
        pattern = defaults.string(forKey: "pattern").flatMap(LightPattern.init(rawValue:)) ?? .festivizer
        swing = defaults.object(forKey: "swing") as? Bool ?? true
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
        return Theme.all.first { $0.id == themeID } ?? .festivizer
    }

    /// FNV-1a hash. Swift's own `hashValue` changes every launch, and an app should keep its colours.
    static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash
    }
}
