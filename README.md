# Window Festivizer

A macOS menu-bar app that wraps the top of your windows in a string of festive lights. A twisted
cable hugs each window's top edge and wraps round both corners, with slim bulbs splayed along it.
The lights blink the way TF2's Festivizer does: three colours, two lit at a time, with the dark one
moving along every beat.

![The lights on pretend windows, in each theme and size](docs/preview.png)

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
- **Show On**: All Windows or Front Window Only, then a checkbox for each app. Untick an app to leave
  its windows bare.
- **Lights**: Festivizer (green, blue, yellow), Classic (red, amber, lime), RED, BLU, Warm White,
  Pastel, or Mixed (a different set for each app)
- **Size**: Slim, Regular (the default) or Chunky
- **Pattern**: Festivizer (two of three colours lit) or Steady

Full-screen windows, popovers, sheets and small dialogs go without lights. The cable sits on the
window's edge, so it never covers the red, yellow and green buttons, and clicks always pass through.

## How it works

| File | What it does |
| --- | --- |
| `App/WindowFestivizerApp.swift` | Entry point. Starts the menu-bar app, or handles `--render`. |
| `App/AppDelegate.swift` | The menu-bar icon and its menu, including Show On. |
| `App/Settings.swift` | Menu choices, saved in UserDefaults. Sizes are defined here. |
| `Windows/WindowTracker.swift` | Reads the window list about 7 times a second (60 while something moves), decides which windows get lights, keeps the lights stacked above them, and ticks the blink beat. |
| `Windows/LightsOverlay.swift` | One window's lights, in an overlay covering just the strip along its top edge. |
| `Windows/OverlayWindow.swift` | The see-through, click-through window the lights are drawn in. |
| `Lights/WrapGeometry.swift` | Where everything goes: the cable along the window's outline, and bulbs at slightly uneven spacing and angles so it looks hung by hand. |
| `Lights/BulbArt.swift` | Draws the twisted cable and the bulbs with Core Graphics, in TF2's painted style. There are no image files. |
| `Lights/LightLayers.swift` | Turns the drawings into Core Animation layers: one picture for the cable and unlit bulbs, plus each lit bulb on top, grouped by colour. |
| `Lights/FestivizerPattern.swift` | The blink rule: on beat *n*, colour *n mod 3* is dark. |
| `Lights/Theme.swift` | The colour sets. |
| `Dev/PreviewRenderer.swift` | The `--render` developer option below. |

Why it looks crisp: every bulb is drawn as vector shapes at its final position and angle, onto a
bitmap whose edges sit on whole pixels for your display. Nothing is drawn once and then rotated or
scaled, and there are no large blurred glows.

Why it's light on your Mac: the blink is a few opacity changes per window per beat, animated by
Core Animation, and nothing is redrawn unless a window is resized or a setting changes. Idle cost is
mostly reading the window list, about 2% of one CPU core on an M1 with 9 windows open.

## Developer options

Save a picture of the lights on pretend windows (the image above), without touching your real windows:

```sh
xcodebuild -project WindowFestivizer.xcodeproj -scheme WindowFestivizer -configuration Release -derivedDataPath build/DerivedData build
build/DerivedData/Build/Products/Release/WindowFestivizer.app/Contents/MacOS/WindowFestivizer --render docs/preview.png
```

Log when and why the tracker speeds up: set the environment variable `FESTIVIZER_LOG=1`
(in Xcode: Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables).

Clear saved settings: `defaults delete com.aayanrahman.windowfestivizer`

## Known issues

- Clicking a window that's behind others can briefly cover its lights until they're re-stacked a
  frame later. Window Scarves avoids this by lifting the overlay just above normal windows while
  the pointer is over it.
- During Show Desktop and Mission Control, the lights catch up with the windows a moment late.
- The cable assumes a 12-point window corner. Windows with much rounder corners show a small gap
  at the corners.

## Roadmap

- Unboxing: open a crate from the menu to unlock new light sets, with a reveal animation
- Sounds for unboxing and for switching the lights on
- App icon and a downloadable release build
