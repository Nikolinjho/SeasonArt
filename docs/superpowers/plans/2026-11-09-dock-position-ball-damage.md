# Dock placement and ball damage implementation plan

**Goal:** Deliver the two behaviors approved in chat, preserving the current local Dock improvements.

**Architecture:** Persist DockSnowPosition in Preferences and propagate through ScreenSnow. SnowSimulation owns particle routing and accumulation. WinterBallDamage owns bounded ball-local contour damage, WinterScene applies impact events, and WinterObjectView draws the resulting path.

**Tech stack:** Swift, AppKit, Metal, XCTest.

Execution is sequential in the current checkout because this feature depends on the existing uncommitted Dock implementation. No unrelated changes are staged or published.

- [x] Add failing regression tests in PreferencesTests, DockSnowCollisionTests and WinterBallDamageTests. Run `swift test --disable-sandbox` with the relevant filters and capture expected failures.
- [x] Add DockSnowPosition, preference persistence, snow-only menu choices and propagation to existing/new screens. Bypass Dock snow collision and routing below it, keep ordinary window collisions, transfer existing shelf snow on selection and preserve the inactive snow mode behavior.
- [x] Add bounded directional dents, persistent ball-local state, landing integration and assembly preservation. Draw the same outline used for the damaged contact extent, invalidate the view when damage changes, and emit a bounded burst only on an actual damaging impact.
- [x] Run focused tests, full `swift test --disable-sandbox`, release build and packaging checks. Inspect a synthetic preview with the production drawing path.
- [x] Update README and verification notes with exact results and native verification limits. Build/install locally using the existing signed update workflow and verify the installed binary if authorized by the current session.

Verification results: [dock-position-ball-damage](../../verification/dock-position-ball-damage.md). Native acceptance remains open as recorded there.
