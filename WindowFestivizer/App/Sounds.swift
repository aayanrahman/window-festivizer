import AppKit
import AVFoundation

/// The moments that can play a sound.
///
/// No sounds come with the app. You add your own by dropping audio files into the sounds folder
/// (menu > Open Sounds Folder), each named after the moment it plays at: `lights-on.wav`,
/// `new-window.mp3`, `shake.m4a`, and so on.
enum Sound: String, CaseIterable {
    /// The lights switching on, including when the app starts.
    case lightsOn = "lights-on"
    /// A window getting its lights: a brand-new one, or one chosen in Choose Windows.
    case newWindow = "new-window"
    /// A window being shaken: every time it's flung back the other way.
    case shake = "shake"

    /// What it's for, as written in the note in the sounds folder.
    var when: String {
        switch self {
        case .lightsOn: return "when the lights switch on, including when the app starts"
        case .newWindow: return "when a window gets its lights"
        case .shake: return "every swing when you shake a window while dragging it"
        }
    }

    /// How many copies can play at once. Shaking a window fires shakes faster than one sound
    /// finishes, so they overlap rather than cut each other off; everything else restarts.
    var voices: Int { self == .shake ? 4 : 1 }
}

/// Plays the sounds you've added, unless Sounds is switched off in the menu.
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// ~/Library/Application Support/Window Festivizer/Sounds
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Window Festivizer", isDirectory: true)
        .appendingPathComponent("Sounds", isDirectory: true)

    /// Audio formats that AVAudioPlayer can play.
    static let fileTypes = ["wav", "mp3", "m4a", "aiff", "aif", "caf"]

    /// Loud enough to hear, quiet enough not to make you jump.
    private static let volume: Float = 0.5

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]
    private var watcher: DispatchSourceFileSystemObject?

    /// Make the sounds folder (with a note saying what to put in it), load whatever's there, and
    /// watch it, so sounds added or removed while the app runs take effect straight away.
    func start() {
        makeFolder()
        reload()
        watch()
    }

    func play(_ sound: Sound) {
        guard Settings.shared.sounds, let voices = players[sound], !voices.isEmpty else { return }
        // Take the next copy in turn, starting it again from the top if it's still playing.
        let index = nextVoice[sound, default: 0] % voices.count
        nextVoice[sound] = index + 1
        voices[index].currentTime = 0
        voices[index].play()
    }

    /// The moments that have a sound added.
    var available: [Sound] { Sound.allCases.filter { !(players[$0] ?? []).isEmpty } }

    /// Show the sounds folder in Finder.
    func openFolder() {
        makeFolder()
        NSWorkspace.shared.open(Self.folder)
    }

    /// Load every sound in the folder now, so none of them stalls a frame loading the first time
    /// it plays (the first swing of a shake, say).
    func reload() {
        players = [:]
        for sound in Sound.allCases {
            guard let url = file(for: sound) else { continue }
            players[sound] = (0..<sound.voices).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.volume = Self.volume
                player.prepareToPlay()
                return player
            }
        }
    }

    /// The file for `sound`, in whichever audio format it was added.
    private func file(for sound: Sound) -> URL? {
        Self.fileTypes.lazy
            .map { Self.folder.appendingPathComponent(sound.rawValue).appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func makeFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let note = Self.folder.appendingPathComponent("README.txt")
        // Written once; if you edit or delete it, it's left alone.
        guard !FileManager.default.fileExists(atPath: note.path) else { return }
        let names = Sound.allCases.map { "  \($0.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))\($0.when)" }
        let text = """
        Window Festivizer sounds

        Drop audio files in this folder to give Window Festivizer sound effects. Name each file
        after the moment it should play at:

        \(names.joined(separator: "\n"))

        Any of these formats work: \(Self.fileTypes.map { "." + $0 }.joined(separator: ", ")).
        For example: shake.wav. Changes take effect straight away.
        Turn sounds on or off from the sparkles icon in the menu bar.

        """
        try? text.write(to: note, atomically: true, encoding: .utf8)
    }

    /// Reload whenever a file is added to, removed from or renamed in the folder.
    private func watch() {
        let descriptor = open(Self.folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
