import AppKit

/// Where the app starts.
///
/// It's a plain AppKit app with no storyboard and no Dock icon (LSUIElement is switched on in the
/// target's build settings), so all you see of it is the sparkles icon in the menu bar.
///
/// `@main` makes this the entry point. With the target's default actor isolation set to MainActor,
/// `main()` runs on the main actor, which AppKit requires.
@main
enum WindowFestivizerApp {
    static func main() {
        // Developer option: `WindowFestivizer --render out.png` saves a picture of the lights on some
        // pretend windows and quits, without touching your real windows. See PreviewRenderer.swift.
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--render"), i + 1 < arguments.count {
            PreviewRenderer.render(to: arguments[i + 1])
            return
        }

        let app = NSApplication.shared
        // NSApplication only holds its delegate weakly; keeping it alive for as long as the app runs.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
