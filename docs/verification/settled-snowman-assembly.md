# Settled snowman assembly

Latest delivery: 7 November 2026, 17:06 MSK.

User reported that three stacked snowballs remained separate and requested deeper joints. Earlier assembly ran only in endDragging. Three delayed-landing/deep-placement tests failed on that version. The new step-level check follows stable objectSupports chains and combines exactly three components after 0.2 simulated seconds. Pending stable chains keep the fast timer running. Two resting balls remain separate until manual assembly or completion of a three-component chain. Four components produce a snowman plus a separate ball. Brief contact and held/parked/moving components do not complete assembly.

Overlap is now 30% of the smaller diameter (formerly 15%). The standard [28, 21, 14] figure is 105 pt high, previously 115.5 pt. Shadow contact geometry and top torso button placement account for the deeper joints. Arms and all previous appearance changes remain.

## Evidence

- Full native-session `swift test --disable-sandbox`: 210 tests, zero failures, no skips. /tmp/seasonart-assembly-full-final.log.
- `SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v`: 19 tests, OK. /tmp/seasonart-assembly-packaging.log.
- Release build/sign and installation exited 0. /tmp/seasonart-assembly-build.log and /tmp/seasonart-assembly-install.log.
- Strict codesign verification passed. Installed and built executable hashes matched: 4bca7083306a9136c50d13ffb436a7764cf4b5e2674f91bd1a71e24ce1c8c37d.
- Full preference dictionaries compared equal before/after installation. Installed process found by exact executable path, background launch.
- Backup: build/backups/20261107-170635-MSK-1293a897/SeasonArt.app.
- Tests cover 30/60/120 fps, delayed placement, head landing on a pair, deep contact, brief contact, held head, fourth component, decoration overlap, existing throws and preservation of all components in dense scenes.
- AppKit preview inspected: docs/verification/artifacts/contact-shadows/deeper-joints.png. The preview compares shading on/off with the new joint geometry.

Native pointer-driven assembly was not performed. This verifies the model and actual view rendering, not a live user gesture. Earlier global-input restrictions remain. Worktree remains dirty at 8f70403, fix/winter-object-capacity. Earlier changes retained, no commits/integration/publication requested.
