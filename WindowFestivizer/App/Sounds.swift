import AVFoundation

/// The sound effects: TF2's crate opening, and two Christmas sounds from TF2 sound mods. The files
/// live in the Sounds folder, and Xcode copies them into the app. They aren't covered by this
/// project's licence.
enum Sound: String, CaseIterable {
    /// Lights switching on, including at launch.
    case crate = "Item_open_crate"
    /// A window getting lights: a brand-new one, or one chosen in Choose Windows.
    case chime = "Christmas_notification"
    /// A window shaken: each time it's flung back the other way.
    case hit = "Christmas_hitsound"

    /// How many copies can play at once. Shaking a window fires hits faster than one finishes,
    /// so they overlap rather than cut each other off; everything else restarts.
    var voices: Int { self == .hit ? 4 : 1 }
}

/// Plays the sound effects, unless Sounds is switched off in the menu.
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Loud enough to hear, quiet enough not to make you jump.
    private static let volume: Float = 0.5

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]

    /// Load every sound now, at launch, so the first one to play doesn't stall a frame while it
    /// loads (the first ding of a shake, say).
    func preload() {
        for sound in Sound.allCases { _ = players(for: sound) }
    }

    func play(_ sound: Sound) {
        guard Settings.shared.sounds else { return }
        let voices = players(for: sound)
        guard !voices.isEmpty else { return }
        // Take the next copy in turn, starting it again from the top if it's still playing.
        let index = nextVoice[sound, default: 0] % voices.count
        nextVoice[sound] = index + 1
        voices[index].currentTime = 0
        voices[index].play()
    }

    /// Each sound is loaded the first time it's needed and kept, so later plays start instantly.
    private func players(for sound: Sound) -> [AVAudioPlayer] {
        if let loaded = players[sound] { return loaded }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else { return [] }
        let loaded = (0..<sound.voices).compactMap { _ -> AVAudioPlayer? in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.volume = Self.volume
            player.prepareToPlay()
            return player
        }
        players[sound] = loaded
        return loaded
    }
}
