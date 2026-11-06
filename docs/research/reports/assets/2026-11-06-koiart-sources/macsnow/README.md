# MacSnow

Tiny macOS snow vibes for your desktop. No Electron, no background circus, no dependency pile. Just a menu bar app, some SpriteKit weather, and a very serious commitment to making your Mac look like it wandered into winter.

MacSnow is a SwiftPM-based AppKit/SpriteKit prototype inspired by the old-school Xsnow idea: snow falls across your desktop, seasonal bits drift around, and the whole thing stays out of your way while you work.

## The Quick Take

MacSnow is:

- A native macOS menu bar app.
- Built with Swift, AppKit, SpriteKit, CoreGraphics, and Foundation.
- Zero third-party runtime dependencies.
- Packaged as an unsigned local `.app` and `.dmg`.
- Designed to run as a click-through overlay across one or more displays.
- Release-build only by design.
- Strictly single-instance: launching MacSnow again replaces the currently running MacSnow process instead of creating duplicates.

MacSnow is not:

- A signed or notarized production app yet.
- A Mac App Store app.
- An auto-updating app.
- A screen recorder.
- A heavyweight desktop customization suite.

Current repository version: `1.21.84`

Latest generated local release artifact currently available in this checkout:

```text
dist/MacSnow-1.21.84.dmg
```

## Screenshot

![MacSnow running on macOS with snow, moonlight, retro Xsnow-style sprites, and the original Xsnow SourceForge page open](docs/screenshots/macsnow-sourceforge.png)

This is the vibe: a modern Mac desktop, old-school Xsnow energy, and the original SourceForge project close by for the nostalgia receipt.

## Why This Exists

The goal is simple: bring the cozy Xsnow-style desktop effect to modern macOS without turning the app into a monster.

MacSnow is very much a nostalgia project: it takes the classic Xsnow vibe and rebuilds it for a MacBook-era desktop. The app intentionally references the original Xsnow image assets from [the SourceForge Xsnow project](https://sourceforge.net/projects/xsnow/) so the trees, snowmen, Santa bits, and tiny winter scene pieces keep that old-school desktop-toy flavor instead of feeling like a shiny modern remake with the soul sanded off.

Modern macOS makes this trickier than it sounds:

- Menu bar items can show up in System Settings under "Allow in the Menu Bar".
- Status items can get weird on newer macOS builds, especially around duplicate registrations.
- Multiple local build products can accidentally register as separate apps.
- Debug SwiftPM builds can create `.build/.../debug/MacSnow`, which macOS may treat as another menu bar app.
- Overlay windows need to be click-through, transparent, multi-display aware, and polite around fullscreen spaces.

MacSnow leans into that reality. The project now tries hard to keep only one real MacSnow app identity alive.

## What's New In 1.21.84

This patch makes moving objects feel more 2.5D:

- Added a shared depth profile for moving desktop objects so objects near the bottom of the screen render larger, faster, brighter, and in front.
- Objects farther up the scene now render smaller, slower, dimmer, and behind closer objects.
- Birds, falling gifts, ground agents, moving winter animals, reindeer, moose, and polar bear movement now use depth-based scale, alpha, z-order, speed, bobbing, and parallax drift.
- Santa already had route-based perspective scaling, so this release keeps that behavior aligned with the new depth model.

## What's New In 1.21.83

This patch makes the new winter objects controllable from the menu:

- Added grouped `Visibility` submenus for winter objects: `Places`, `Props`, `Holiday`, `Animals`, `Sports`, and `Retro Toys`.
- Each new object can now be toggled on or off individually, including penguin, igloo, icicles, ski lift, toy train, husky sled, snowboarder, and the rest of the 1.21.82 object set.
- Winter object visibility is persisted in settings and defaults to enabled for existing users.
- Disabled winter objects are removed from both static scenery generation and moving object spawning.

## What's New In 1.21.82

This patch adds a bigger cold-weather toy box while keeping the controls simple:

- Added new scenery objects: igloo, icicle clusters, ice fishing hole, lamp post, snow mound, ice patch, snowy mailbox, sign post, hot cocoa mug, lantern, candy cane, winter fence, ski lift chair, owl, snow angel, snow shovel, mittens, scarf, wool hat, wreath, stocking, bells, Christmas lights, toy train, chimney smoke, snowball stack, and frost-corner crystals.
- Added new moving winter characters: penguin, arctic fox, seal, husky sled, skier, snowboarder, distant wolf silhouette, and rolling snowball.
- New objects follow the existing `Scenery`, `Ground Agent`, `Object Amount`, and visual scale controls instead of adding a giant menu full of one-off switches.
- The new assets are drawn with lightweight SpriteKit primitive shapes, so they stay zero-dependency and match the existing desktop-toy style.

## What's New In 1.21.81

This patch tightens the menu bar experience and display toggles:

- Turning a display off in `Displays` now clears every visual object on that display, not just active snowfall.
- Cleared display content includes falling flakes, celestial effects, birds, scenery, ground agents, Santa, gifts, accumulation, collapse particles, and window tracking state.
- Disabled displays are skipped during window snapshot and collision-edge updates, so accumulation does not quietly come back after the display is unset.
- Debug UI is gone from the menu: `Show Edge Debug` and the `Debug: overlays ...` status row were removed.
- Edge-debug settings and scene rendering code were removed from the app path.
- Stale LaunchServices registrations from old DMG mounts and local `dist/MacSnow.app` builds were cleaned up during validation, leaving `/Applications/MacSnow.app` as the only registered MacSnow app.
- The app bundle and DMG build scripts now unregister local staging bundles after packaging so local build artifacts do not reappear as duplicate menu bar entries.

## Feature Tour

### Menu Bar First

MacSnow lives in the menu bar. The snowflake status item opens the app controls, and the app has no Dock icon.

The menu gives you control over:

- Snow on/off
- Density
- Wind strength
- Wind direction
- Visual scale
- Snow color mode
- Celestial effects
- Aurora
- Moon
- Stars
- Meteors
- Birds
- Santa flight
- Santa style
- Santa speed
- Santa scale
- Scenery
- Trees
- Gift tree
- Snowman
- House
- Reindeer
- Moose
- Polar bear
- Ground agent
- Gifts
- Object amount
- Small flake accumulation
- Accumulation spill behavior
- Accumulation rate
- Accumulation style
- Overlay level
- Per-display enable/disable
- Edge debug display
- Clear accumulation
- Quit

It is intentionally a menu bar utility, not a full settings-window app.

### Snow Rendering

The snow layer is rendered with SpriteKit inside transparent AppKit overlay windows. Each display gets its own overlay controller and scene.

The current rendering model includes:

- Small falling flakes
- Larger flakes
- Wind-influenced drift
- Density presets
- Visual scale presets
- Color mode options
- Seasonal scene objects
- Window-edge accumulation logic

### Multi-Display Support

MacSnow watches display topology changes and rebuilds overlay controllers when screens change.

That means the app is designed to react when you:

- Plug in a monitor
- Unplug a monitor
- Change display arrangement
- Move between display configurations

Each display gets a stable display identity and a user-facing label for menu controls.

### Click-Through Desktop Overlay

The overlay window is transparent and click-through, so it should not steal focus from your real apps.

The goal is:

- You keep using Finder, Safari, Xcode, Terminal, or whatever else.
- MacSnow paints above or around the desktop depending on overlay mode.
- Mouse events keep going to the apps underneath.

### Window-Aware Accumulation

MacSnow has a CoreGraphics-based window scanner that samples visible third-party window bounds. The scanner feeds window-edge data into the snow scene so accumulation can happen around useful edges instead of only at the bottom of the screen.

Current scanner behavior:

- Uses on-screen window metadata.
- Excludes desktop elements.
- Filters very small windows.
- Tracks owner PID, owner name, window number, layer, bounds, and z-order.
- Sends snapshots into the scene pipeline.

This is intentionally metadata-based. It is not a screen recording feature.

### Seasonal Bits

MacSnow has moved beyond plain flakes. Depending on menu settings, the scene can include:

- Santa flight
- Trees
- Gift tree
- Snowman
- House
- Reindeer
- Moose
- Polar bear
- Birds
- Gifts
- Celestial effects like aurora, moon, stars, and meteors

Some visual assets and behavior are inspired by the bundled Xsnow source/reference material under `xsnow-org/`.

### Persistent Settings

Settings are stored with `UserDefaults`. MacSnow remembers the core controls across launches, including global and per-display preferences.

Examples:

- Snow enabled state
- Density
- Wind
- Visual scale
- Color mode
- Celestial toggles
- Scenery toggles
- Accumulation preferences
- Overlay level
- Per-display enabled state

Older settings are handled defensively so new fields can be added without breaking existing saved preferences.

### Single-Instance Runtime

MacSnow is strict about process ownership.

If MacSnow is already running and you launch it again, the new process does not sit next to the old one. It replaces it:

1. The new process checks the shared lock file.
2. If an existing MacSnow process owns the lock, the new process sends it `SIGTERM`.
3. If the old process does not exit, the new process escalates to `SIGKILL`.
4. The new process waits for the lock.
5. Only after the lock is acquired does the new MacSnow instance continue.
6. If the lock cannot be acquired, the new process exits rather than allowing duplicates.

This is here because duplicate menu bar registrations are annoying, and macOS System Settings can remember stale app identities for longer than anyone wants.

### Release-Only Builds

MacSnow intentionally blocks debug builds.

Do not run:

```bash
swift build
swift run MacSnow
```

SwiftPM defaults those commands to debug mode. Debug mode can create `.build/.../debug/MacSnow`, and macOS may treat that as a separate menu bar app.

Use release mode instead:

```bash
swift build -c release
swift run -c release MacSnow
```

The package manifest also blocks debug configuration with a compile-time error. This is deliberate.

## Install From GitHub Release

Use the GitHub Release when you want the packaged app without building it yourself.

1. Open the release page:

   <https://gitlab.com/heroyik/macsnow/-/releases>

2. Expand `Assets`.
3. Download the DMG named like:

   ```text
   MacSnow-<version>.dmg
   ```

4. Open the DMG.
5. Drag `MacSnow.app` to the `/Applications` shortcut.
6. Launch `MacSnow.app` from Finder or Spotlight.

### First Launch Warning

MacSnow is currently unsigned and not notarized. macOS may block the first launch.

If that happens:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Find the blocked `MacSnow.app` message.
4. Choose `Open Anyway`.

You can also:

1. Control-click `MacSnow.app`.
2. Choose `Open`.
3. Confirm the launch prompt.

That is normal for this prototype stage.

## Update MacSnow

To update from an older build:

1. Download the newest `MacSnow-<version>.dmg`.
2. Open it.
3. Drag the new `MacSnow.app` into `/Applications`.
4. Replace the old app when Finder asks.
5. Launch the new app.

If an older MacSnow process is already running, the new launch should terminate the old process and continue as the only MacSnow instance.

## Uninstall

To uninstall:

1. Quit MacSnow from the menu bar.
2. Delete `/Applications/MacSnow.app`.

User preferences are stored in the macOS defaults database. They can be removed later if a cleanup flow is added or if you manually clear the `local.macsnow.prototype` defaults domain.

## Build From Source

### Requirements

- macOS 14 or newer target
- Swift Package Manager
- Apple Command Line Tools or Xcode toolchain
- No third-party package install required

### Compile

Use release mode:

```bash
swift build -c release
```

Default debug builds are blocked on purpose:

```bash
swift build
```

Expected result:

```text
error: ... debug/MacSnow.build is not a directory
```

or a compile-time error explaining that debug builds are forbidden.

### Run From SwiftPM

Use release mode:

```bash
swift run -c release MacSnow
```

Prefer the packaged app for manual testing:

```bash
bash Scripts/build_app_bundle.sh
open dist/MacSnow.app
```

### Build The `.app`

```bash
bash Scripts/build_app_bundle.sh
```

Output:

```text
dist/MacSnow.app
```

The app bundle includes:

- `Contents/MacOS/MacSnow`
- `Contents/Info.plist`
- `Contents/PkgInfo`
- `Contents/Resources/AppIcon.icns`
- `Contents/Resources/Pixmaps`

### Build The DMG

```bash
bash Scripts/build_dmg.sh
```

Output:

```text
dist/MacSnow-<version>.dmg
```

The DMG contains:

- `MacSnow.app`
- `/Applications` shortcut

The DMG build script also unregisters the temporary staging app from LaunchServices during cleanup. That keeps packaging runs from polluting macOS menu bar settings with stale app records.

## Debug Builds Are Banned Here

This repo has multiple layers of defense against accidental debug artifacts:

- `Package.swift` defines `MACSNOW_FORBID_DEBUG_BUILD` for debug configuration.
- `Sources/MacSnow/ReleaseOnlyBuild.swift` fails debug compilation with `#error`.
- `Scripts/build_app_bundle.sh` rejects `CONFIGURATION=debug`.
- `.build/debug` is a sentinel file, not a directory.
- `.build/arm64-apple-macosx/debug` is also a sentinel file.

Why so intense?

Because debug build products can register with macOS as their own app. That can create duplicate `MacSnow` entries under System Settings -> Menu Bar -> Allow in the Menu Bar. This repo is optimized for one app identity: the release bundle.

## Project Map

```text
.
|-- 1.XSNOW PRD.md
|-- 2.XSNOW ADD.md
|-- 4.MVP 1.1 VALIDATION PLAN.md
|-- 5.DISTRIBUTION CHECKLIST.md
|-- 7.PERFORMANCE LOG.md
|-- AGENTS.md
|-- Package.swift
|-- README.md
|-- docs/
|   `-- screenshots/
|       `-- macsnow-sourceforge.png
|-- Resources/
|   `-- AppIcon.icns
|-- Scripts/
|   |-- build_app_bundle.sh
|   `-- build_dmg.sh
|-- Sources/
|   `-- MacSnow/
|       |-- AppDelegate.swift
|       |-- AppVersion.swift
|       |-- Diag.swift
|       |-- DisplayController.swift
|       |-- DisplayDetector.swift
|       |-- DisplayIdentity.swift
|       |-- MacSnowManager.swift
|       |-- OverlayWindow.swift
|       |-- ReleaseOnlyBuild.swift
|       |-- SettingsStore.swift
|       |-- SnowScene.swift
|       |-- StatusMenuController.swift
|       |-- WindowCoordinateMapper.swift
|       |-- WindowLayoutScanner.swift
|       |-- XPMTextureCache.swift
|       `-- main.swift
|-- VERSION
|-- releases/
|   |-- v1.21.78.body.md
|   `-- v1.21.78.md
`-- xsnow-org/
    `-- xsnow-3.9.1/
```

## Architecture

### `main.swift`

Bootstraps the AppKit app, sets accessory activation policy, installs the app delegate, and runs the main loop.

It also owns the single-instance lock:

- lock file: `/tmp/local.macsnow.prototype.lock`
- records the active PID
- terminates old MacSnow processes before allowing a new one to continue
- refuses to start if it cannot guarantee single-instance behavior

### `AppDelegate`

Keeps startup intentionally small. It waits for the run loop before starting the manager because newer macOS status item behavior can be sensitive to timing.

### `MacSnowManager`

The central coordinator.

It wires together:

- display detection
- status menu callbacks
- settings loading and saving
- overlay controller lifecycle
- window scanning
- fullscreen power-save behavior
- per-display scene updates

### `StatusMenuController`

Owns the menu bar status item and every menu control.

It is responsible for:

- building the menu
- applying the snowflake status image
- showing version/debug status
- reflecting current settings
- routing user actions back to `MacSnowManager`

### `DisplayDetector`

Listens for display configuration changes and triggers overlay rebuilds.

### `DisplayIdentity`

Creates stable display IDs and readable display labels.

### `DisplayController`

Owns one overlay window and one SpriteKit scene for a display.

### `OverlayWindow`

Creates the transparent, borderless, click-through AppKit window.

Overlay levels are configurable so MacSnow can be tuned for desktop, normal, fullscreen-friendly, or stronger overlay behavior.

### `SnowScene`

The SpriteKit scene. This is where the visual weather happens.

It handles:

- flakes
- wind
- accumulation
- falling fragments
- debug edges
- seasonal objects
- scene scaling
- object movement
- per-frame updates

### `WindowLayoutScanner`

Samples visible windows through CoreGraphics metadata.

The scanner is used for collision and accumulation behavior. It does not capture screenshots or record screen contents.

### `WindowCoordinateMapper`

Converts CoreGraphics window coordinates into display-local AppKit/SpriteKit coordinates.

### `SettingsStore`

Persists app settings with `UserDefaults`.

### `XPMTextureCache`

Loads XPM-style pixmap resources from the bundled resources or local source tree fallback paths.

## Menu Options In Plain English

### Snow

Turns the whole snow effect on or off.

### Density

Controls how much snow is on screen:

- `Low`
- `Normal`
- `High`

### Wind

Controls horizontal drift. Wind has strength and direction, so the snow can feel calm, pushed, or fully weathered.

### Visual Scale

Scales the visual footprint of the scene objects.

### Snow Color Mode

Lets snow styling move beyond plain white when configured.

### Celestial Effects

Controls the sky-flavored layer:

- aurora
- moon
- stars
- meteors

### Birds

Adds moving birds to the scene.

### Santa Flight

Adds the seasonal Santa pass with style, speed, and scale options.

### Scenery

Controls grounded seasonal objects:

- trees
- gift tree
- snowman
- house
- reindeer
- moose
- polar bear
- ground agent
- gifts

### Accumulation

Controls small-flake buildup.

Options include:

- accumulation enabled/disabled
- spill behavior
- accumulation rate
- accumulation style
- clear accumulation

### Overlay Level

Controls where MacSnow sits in the window stack.

Use this when you need it to behave differently around desktop windows, fullscreen apps, Spaces, or Stage Manager.

### Displays

Lets you toggle MacSnow per display.

When a display is toggled off, MacSnow clears that display's overlay instead of merely pausing snow generation. That means no leftover moon, stars, birds, trees, snowmen, animals, gifts, Santa sprites, accumulated snow, or collision artifacts should remain on the disabled display.

## Validation

Use this stack when validating a change:

```bash
swift build -c release
bash Scripts/build_app_bundle.sh
bash Scripts/build_dmg.sh
```

Expected:

- release compile succeeds
- `dist/MacSnow.app` exists
- `dist/MacSnow-<version>.dmg` exists
- default debug build remains blocked
- only one MacSnow process can run at a time

Manual validation should cover:

- launch from Finder
- menu bar item appears
- menu opens
- start/stop snow works
- density changes render visibly
- wind changes render visibly
- per-display toggles work
- display connect/disconnect rebuilds overlays
- click-through works over common apps
- fullscreen-friendly overlay behavior is acceptable
- accumulation builds and clears
- window scanner debug count looks reasonable
- sleep/wake does not leave broken overlays
- CPU and memory are recorded in `7.PERFORMANCE LOG.md`

The canonical manual checklist lives in:

```text
4.MVP 1.1 VALIDATION PLAN.md
```

## Troubleshooting

### I see duplicate MacSnow entries in System Settings

This usually means macOS remembered an older build product.

Things to check:

1. Quit all MacSnow processes.
2. Do not run `.build/.../debug/MacSnow`.
3. Use only the release `.app`.
4. Rebuild with:

   ```bash
   bash Scripts/build_app_bundle.sh
   ```

5. Launch:

   ```bash
   open dist/MacSnow.app
   ```

The current runtime lock should prevent two MacSnow processes from staying alive at the same time.

If System Settings still shows a second off-state MacSnow entry with a generic icon, check LaunchServices for stale DMG or development registrations. In one confirmed case, the stale item pointed to a missing mounted-DMG app:

```text
/Volumes/MacSnow 1.21.73/MacSnow.app
```

The active installed app should be the only remaining registration:

```text
/Applications/MacSnow.app
```

Development builds under `dist/MacSnow.app` can also appear as separate app registrations while testing. Unregister stale paths before judging whether System Settings is clean.

### `swift build` fails

Good. That is expected.

Use:

```bash
swift build -c release
```

Default `swift build` means debug mode, and debug mode is intentionally blocked.

### `CONFIGURATION=debug bash Scripts/build_app_bundle.sh` fails

Also expected.

The bundle script is release-only.

### macOS says the app cannot be opened

MacSnow is unsigned.

Use `System Settings` -> `Privacy & Security` -> `Open Anyway`, or Control-click the app and choose `Open`.

### The menu bar icon is missing

Check:

- System Settings -> Menu Bar -> Allow in the Menu Bar
- whether the app is running from `/Applications/MacSnow.app` or `dist/MacSnow.app`
- whether another menu bar utility has crowded the menu bar
- whether a stale older build is still running

Then quit/relaunch MacSnow.

### The app feels too busy

Turn down:

- density
- object amount
- celestial effects
- birds
- Santa
- scenery
- accumulation

MacSnow is meant to be adjustable, not permanently chaotic.

## Release Flow

For a local release build:

```bash
bash Scripts/build_dmg.sh
```

Then verify:

```bash
shasum -a 256 dist/MacSnow-<version>.dmg
```

Release notes live under:

```text
releases/
```

For example:

```text
releases/v1.21.78.md
releases/v1.21.78.body.md
```

Suggested GitHub CLI shape:

```bash
gh release create v<version> \
  dist/MacSnow-<version>.dmg \
  --title "MacSnow <version>" \
  --notes-file releases/v<version>.body.md
```

## Development Rules

The project tries to stay boring in the best way:

- Keep it native.
- Keep it zero-dependency unless there is a real reason.
- Prefer AppKit, SpriteKit, CoreGraphics, and Foundation.
- Do not add screen-recording behavior without updating the product requirements.
- Do not reintroduce debug build products.
- Keep DMG filenames aligned with `VERSION`.
- Regenerate the DMG after bundle-affecting changes.
- Keep menu bar identity stable.
- Avoid duplicate app registrations.

## Testing Notes

There is no automated test target yet.

Future tests should live under:

```text
Tests/MacSnowTests/
```

High-value test areas:

- coordinate conversion
- display topology changes
- settings persistence
- window filtering
- single-instance behavior
- release-only build behavior

## Known Gaps

Still not done:

- signing
- notarization
- auto-update
- Mac App Store packaging
- automated test target
- polished onboarding for menu bar permissions
- full performance benchmark automation

## Credits

MacSnow is a modern macOS prototype inspired by the Xsnow desktop effect. The repository includes Xsnow source/reference material under `xsnow-org/` for historical context, asset reference, and behavior inspiration.

Special credit goes to the original Xsnow project hosted on [SourceForge](https://sourceforge.net/projects/xsnow/). MacSnow deliberately keeps close to those original image assets and their low-fi charm, because the whole point is to make a MacBook feel like it inherited a tiny piece of that classic desktop snowfall era.

## Bottom Line

MacSnow is here to make your Mac a little more winter-coded while staying native, tiny, and predictable. Build it in release mode, run one instance, keep the menu bar clean, and let it snow.
