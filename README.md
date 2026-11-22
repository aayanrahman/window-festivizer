# Window Festivizer

A macOS menu-bar app that wraps the top of your windows in a string of festive lights, the way
TF2's Festivizer wraps a gun: a messy coil of twisted cable running from a taped-on battery pack,
capsule bulbs sticking out at every angle, and a loose end swinging off the corner. The lights blink
like the Festivizer's too: three colours, two lit at a time, with the dark one moving along every
beat. And it plays TF2 sound effects.

![The lights on pretend windows, in each style, theme and size](docs/preview.png)

Inspired by Team Fortress 2's Festivizer, and by [Window Scarves](https://github.com/fiof25/window-scarves)
by fiof25 (itself inspired by Sara Gordić's Window Sweaters). Window Festivizer is written from scratch
and shares no code with either; it borrows Window Scarves' approach of tracking windows with the public
window list and drawing in see-through overlay windows. Not affiliated with or endorsed by Valve.

## Build and run

Needs macOS 14 or later and Xcode.

1. Open `WindowFestivizer.xcodeproj`.
2. Pick the **WindowFestivizer** scheme and **My Mac**, then press **Cmd-R**.
3. Look for the sparkles icon in the menu bar. There is no Dock icon and no window.

Only one copy runs at a time: launching a new one (for example Cmd-R while an older build is running)
quits the old one. It needs no permissions (no Accessibility, no Screen Recording). The project signs
with "Sign to Run Locally", so it builds without an Apple developer account. To share a build, pick your
team under the target's **Signing & Capabilities** tab.

## The menu

- **Lights On / Off**
- **Choose Windows…**: dims the screen and spotlights the window under the pointer. Click the
  windows you want lights on: a click lights every window of that app (remembered across restarts),
  Option-click lights just that one window (until you quit). Click a lit window to take its lights
  off. It stays open until you press Done, Return or Esc.
- **Show On**: All Windows, Front Window Only, or Windows I Choose; plus Choose Windows and Forget
  My Choices
- **Style**: Wrapped Around (a loose, uneven coil wound round the top of the window) or Laid on Top
  (a cable along the window's top edge, like a scarf)
- **Lights**: BLU (green, light blue, yellow; the default), RED (green, yellow, red), Warm White,
  Pastel, or Mixed (a different set for each app)
- **Size**: Slim, Regular (the default) or Chunky
- **Pattern**: Festivizer (two of three colours lit) or Steady
- **Swinging Tail**: the end of the cable hangs off the window's top-right corner and swings when
  you drag the window
- **Sounds**: the TF2 sound effects below

## Sounds

| When | Sound |
| --- | --- |
| The lights switch on, including at launch | Item open crate |
| A brand-new window gets its lights | Christmas notification |
| You shake a window while dragging it (every swing) | Christmas hitsound |
| You choose a window in Choose Windows | Achievement earned |
| You take a window's lights off | Mantreads |
| You change Style, Lights, Size, Pattern or the tail | Doubledonk |

The files are in `WindowFestivizer/Sounds`. The TF2 ones come from the
[Team Fortress Wiki](https://wiki.teamfortress.com/wiki/Category:Audio_cues); the two Christmas ones
come from TF2 sound mods (a notification sound and a hitsound). To use different ones, replace a
file keeping its name, or change the names in `App/Sounds.swift`.

The new-window chime stays quiet for windows already open at launch, windows coming back from
another Space, and windows you choose in the picker, and plays at most every 1.5 seconds. A shake
is a fast drag that turns round sharply (see `Windows/ShakeDetector.swift`); a fast drag in one
direction, or round a corner, doesn't count.

Full-screen windows, popovers, sheets and small dialogs go without lights. Nothing covers the red,
yellow and green buttons, and clicks always pass straight through the lights.

## How it works

| File | What it does |
| --- | --- |
| `App/WindowFestivizerApp.swift` | Entry point. Starts the menu-bar app, or handles `--render`. |
| `App/AppDelegate.swift` | The menu-bar icon and its menu. |
| `App/Settings.swift` | Menu choices and chosen apps, saved in UserDefaults. Sizes and styles are defined here. |
| `App/Sounds.swift` | The sounds and the player. The files are in `Sounds/`. |
| `Windows/WindowTracker.swift` | Reads the window list about 7 times a second (60 while something moves or a tail swings), decides which windows get lights, keeps the lights stacked above them, and ticks the blink beat. |
| `Windows/WindowPicker.swift` | Choose Windows: the dimmed sheet, the spotlight and label, and the banner. |
| `Windows/ShakeDetector.swift` | Notices a window being shaken while it's dragged, for the hitsound. |
| `Windows/LightsOverlay.swift` | One window's lights: an overlay for the strip along its top and one for its tail. |
| `Windows/OverlayWindow.swift` | The see-through, click-through window the lights are drawn in. |
| `Lights/WrapGeometry.swift` | Where everything goes, for both styles. Wrapped Around treats the top of the title bar as a pole and winds a wandering helix round it; the back of each turn shows just above the window's edge. |
| `Lights/BulbArt.swift` | Draws the twisted cable, the capsule bulbs and the battery pack with Core Graphics, in TF2's painted style. There are no image files. |
| `Lights/LightLayers.swift` | Turns the drawings into Core Animation layers, grouped by colour so a blink is a few opacity changes. |
| `Lights/SwingingTail.swift` | Verlet rope physics for the tail, with a little stiffness so it curls rather than dangles. |
| `Lights/FestivizerPattern.swift` | The blink rule: on beat *n*, colour *n mod 3* is dark. |
| `Lights/Theme.swift` | The colour sets. |
| `Dev/PreviewRenderer.swift` | The `--render` developer option below. |

Why it looks crisp: every bulb is drawn as vector shapes at its final position and angle, onto a
bitmap whose edges sit on whole pixels for your display. Nothing is drawn once and then rotated or
scaled, and there are no large blurred glows.

Why it's light on your Mac: the blink is a few opacity changes per window per beat, animated by
Core Animation, and nothing is redrawn unless a window is resized, a setting changes, or a tail is
swinging (it settles a few seconds after you let go). Idle cost is mostly reading the window list,
about 2% of one CPU core on an M1 with 9 windows open.

## Developer options

Save a picture of the lights on pretend windows (the image above), without touching your real windows:

```sh
xcodebuild -project WindowFestivizer.xcodeproj -scheme WindowFestivizer -configuration Release -derivedDataPath build/DerivedData build
build/DerivedData/Build/Products/Release/WindowFestivizer.app/Contents/MacOS/WindowFestivizer --render docs/preview.png
```

Log when and why the tracker speeds up: set the environment variable `FESTIVIZER_LOG=1`
(in Xcode: Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables).

Clear saved settings and chosen apps: `defaults delete com.aayanrahman.windowfestivizer`

## Known issues

- Clicking a window that's behind others can briefly cover its lights until they're re-stacked a
  frame later. Window Scarves avoids this by lifting the overlay just above normal windows while
  the pointer is over it.
- During Show Desktop and Mission Control, the lights catch up with the windows a moment late.
- Laid on Top assumes a 12-point window corner. Windows with much rounder corners show a small gap
  at the corners.

## Roadmap

- Unboxing: open a crate from the menu to unlock new light sets, with a reveal animation
- App icon and a downloadable release build

## License

The code is MIT licensed; see [LICENSE](LICENSE). The sound effects in `WindowFestivizer/Sounds` are
from Team Fortress 2 (Valve) and from community TF2 sound mods; they aren't covered by that license.
