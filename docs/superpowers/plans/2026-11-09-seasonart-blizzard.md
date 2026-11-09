# Optional blizzard implementation plan

**Goal:** Add a persistent snow-only “Метель” toggle with mild, smooth gusts.

**Architecture:** A small `BlizzardWind` value type owns its ramp and continuous wind field. `SnowSimulation` applies it to airborne snow before existing collision handling. Preferences and the AppKit menu own the switch.

**Tech stack:** Swift, AppKit, existing Metal rendering and XCTest. Execute sequentially in the current checkout, preserving research assets.

- [x] Add failing `BlizzardWindTests` for smooth on/off, temporal/spatial variation, bounded wind and frame-rate-independent ramp. Add persistence and real simulation coverage.
- [x] Implement `Sources/SeasonArt/BlizzardWind.swift`, wire `SnowSimulation`, `Preferences`, `ScreenSnow` and `AppDelegate`. Preserve all non-snow paths, particle budgets and accumulation. Verify with `swift test --disable-sandbox --filter 'BlizzardWindTests|PreferencesTests'`.
- [x] Run `swift test --disable-sandbox` with graphical-session access. Build with `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh`, run the 19 packaging checks, install with `bash Scripts/install.sh` and verify signature/settings. Update README and verification notes. Do not publish another release without a request.
