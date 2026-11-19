import Foundation

/// The Festivizer's blinking, as seen in the TF2 tool demo.
///
/// Every bulb is one of three colours (bulb 0 → colour 0, bulb 1 → colour 1, bulb 2 → colour 2,
/// bulb 3 → colour 0, …). At any moment two of the colours are lit and the third is dark, and on
/// every beat the dark one moves along:
///
///     beat:       0     1     2     3     4 …
///     colour 0:  off    on    on   off    on
///     colour 1:   on   off    on    on   off
///     colour 2:   on    on   off    on    on
///
/// WindowTracker ticks the beat; BulbBank fades each colour on or off to match.
enum FestivizerPattern {
    /// Seconds per beat. Lower is more frantic.
    static let beat: TimeInterval = 0.9

    /// Seconds a colour takes to fade on or off.
    static let fade: TimeInterval = 0.15

    static func isLit(group: Int, beat: Int, pattern: LightPattern) -> Bool {
        switch pattern {
        case .steady: return true
        case .festivizer: return group != beat % 3
        }
    }
}
