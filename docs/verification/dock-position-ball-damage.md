# Dock placement and snowball impact damage

9 November 2026, 15:26 MSK. Local installation over master `7562add`, still version 0.1.5/build 6. Product changes remain uncommitted and are not part of the published release.

## Behavior

The snow-only menu “Расположение снега” selects “Над Dock” or “Под Dock”. Above remains the default. The selection persists and applies to existing/new screens. Deferred mode transitions reconcile the overlay level through the simulation's wake callback. Below mode bypasses Dock particle collisions and accumulation while retaining ordinary window collisions. Winter toys retain solid Dock support.

Selecting below transfers existing shelf snow to the ground without losing deposit overflow at screen edges. Dormant shelf snow transfers when its surface returns. Selecting above routes ground snow out of the Dock footprint through the existing mass-preserving path.

Hard landings on ground, windows, Dock and other balls create bounded directional dents and a small fragment burst. Gentle placement and resting do not damage balls. Rolling rotates dents and assembly preserves their orientation. Damaged object contacts use contour bounds instead of the original ideal circle, closing the reproduced vertical gap above a damaged base.

## Verification

- `swift test --disable-sandbox`: 269 tests, zero failures, one skipped. The existing Dock window-order test requires a visible system Dock. Log: `/tmp/seasonart-position-damage-full.log`.
- Regressions cover selection persistence, both accumulation positions, window collisions, mass preservation including screen edges, deferred mode transitions, impacts at 30/60/120 fps, gentle placement, resting, bounded repeated damage, assembly orientation, view invalidation, actual rendered pixels and contacts between damaged balls.
- The vertical contact test failed before correction: upper ball bottom 56 pt, damaged base roof 50.68175 pt. It now passes within 0.1 pt. Log: `/tmp/seasonart-damage-contact-red.log`.
- Review tests reproduced edge transfer mass 13.75 instead of 20, an incorrect autumn overlay level and missing damage after landing on another ball. Final focused tests pass. Logs: `/tmp/seasonart-position-damage-review-{red,green}.log`.
- Synthetic production drawing PNGs at `docs/verification/artifacts/ball-damage/{intact,damaged}.png` were generated and the damaged silhouette inspected.
- `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh`: exit 0. `SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v`: 19 tests, OK.
- `bash Scripts/install.sh`: exit 0, installed and launched `~/Applications/SeasonArt.app`. Backup: `build/backups/20261109-152643-MSK-a997a4a2/SeasonArt.app`.
- Strict installed codesign: exit 0. Build and installed executable SHA-256 match: `8fc82a8b5e032defc4afd6a9adaa7c94f5551858e42b9a233ef596a06419f125`. One installed process was observed.
- Full persisted preferences before/after compare equal. Screenshot preference was unchanged. Pointer/focus were not controlled.
- Final build, packaging and install logs: `/tmp/seasonart-position-damage-{build,packaging,install}.log`.
- Independent read-only review of the fixes found no further important regressions. README prose lint and `git diff --check` passed.

## Limits

Native menu selection, live Dock hover appearance and manual Spaces transitions were not accepted in this session. External display and sleep remain unverified. Synthetic drawings do not establish native visual acceptance. Toy mass/size use nominal radii. Object-to-object contact approximates the damaged outline with its bounding ellipse, rather than every small chip.
