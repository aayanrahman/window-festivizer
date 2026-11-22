import AVFoundation

/// The sound effects, all from Team Fortress 2. The files live in the Sounds folder, and Xcode
/// copies them into the app. They belong to Valve, and aren't covered by this project's licence.
enum Sound: String, CaseIterable {
    /// Lights switching on, including at launch.
    case crate = "Item_open_crate"
    /// A window chosen in Choose Windows.
    case achievement = "Achievement_earned"
    /// A window's lights taken off in Choose Windows.
    case stomp = "Mantreads"
    /// A change of style, lights, size, pattern or tail in the menu.
    case donk = "Doubledonk"
}

/// Plays the sound effects, unless Sounds is switched off in the menu.
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Loud enough to hear, quiet enough not to make you jump.
    private static let volume: Float = 0.5

    private var players: [Sound: AVAudioPlayer] = [:]

    func play(_ sound: Sound) {
        guard Settings.shared.sounds, let player = player(for: sound) else { return }
        // Start again from the top if it's still playing from last time.
        player.currentTime = 0
        player.play()
    }

    /// Each sound is loaded the first time it's needed and kept, so later plays start instantly.
    private func player(for sound: Sound) -> AVAudioPlayer? {
        if let loaded = players[sound] { return loaded }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = Self.volume
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}
