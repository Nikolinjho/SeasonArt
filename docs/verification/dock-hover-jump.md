# Dock hover jump: verified locally with CUA

9 November 2026, 16:06 MSK. This document supersedes the intermediate passive-only checks. The final installed fix remains uncommitted over master `7562add`, version 0.1.5/build 6.

## Outcome

CUA Driver reproduced the reported movement on the earlier installed build. After the final fix, a controlled run completed seven hover/leave cycles across left, center and right Dock icons. Snow stayed on the shelf, followed the enlarged icon contours and returned to the shelf after leaving. The observed run did not reproduce the transfer under Dock or to its sides.

The user explicitly authorized CUA and limited this phase to 15 minutes. It started at 15:56:45 MSK. Input and cleanup finished by 16:06:07 MSK. A temporary change from light to heavy snowfall made the accumulation visible. Light snowfall and the collapsed menu bar were restored, the CUA session was ended, and the complete persisted preferences dictionary compared equal to the pre-check snapshot.

## Causes and correction

1. The real Dock remained visible with macOS autohide disabled, while SLSGetDockRectWithReason returned a zero-height reserved rectangle. The tracker treated that as an auto-hidden Dock and only created its shelf under the pointer. New snowfall therefore landed on the floor while the pointer was away, and the ground-clearing path redistributed it when the shelf reappeared. The tracker now consults the actual autohide setting and keeps a non-hidden Dock shelf independently of the pointer.
2. With autohide enabled, enlarged icons extend beyond the ordinary shelf roof. The measured AX shelf/icon union now keeps the shelf present over those icons. A temporarily vanished Dock keeps its SnowLayer in dormant storage instead of shedding it onto the ground.
3. Dock reveal samples could jump vertically and trigger the ordinary-window inertia response. A passive capture saw 973 particles and a temporarily empty shelf. The early-reveal regression reproduced 891 particles and mass 3360 becoming zero. Dock layout/reveal now follows the system frame without that inertia, and width changes resample existing snow without dropping columns.
4. AX horizontal layout was sampled before the new physical window frame and still had the old vertical position. A regression measured contact at 137.58 pt rather than below 101 pt. Horizontal layout remains from AX, while vertical support uses the current physical frame.

## Native evidence

All screenshots are private local artifacts in the ignored `docs/verification/artifacts/dock-hover-jump/` directory.

- `cua-before.png`, `cua-hover-before.png`, `cua-away-before.png`: installed behavior before the final constant-Dock fix.
- `cua-above-setting.png`: the native menu confirms “Над Dock” and temporary heavy snowfall. No Accessibility prompt item was present.
- `cua-fixed-six-cycles-hover.png`: enlarged icons and the continuous snow surface after the controlled cycles.
- `cua-fixed-six-cycles-away.png`: snow back on the shelf after leaving. The filenames describe the six initial cycles, followed by a seventh center-icon cycle ending with the away capture.
- The corresponding `-dock-crop.png` files are inspection crops of the originals, with no visual corrections. They are not used to ground input coordinates.
- `cua-restored-intensity.png` confirms the native “Слабая” label after restoration. `cua-final-desktop.png` records cleanup.

CUA used actual desktop pointer moves on the observed 1728 by 1117 display: icon targets at x=410, 655 and 1200, y=1080, then y=1047, then away at (800,850). The formal batch used a 600 ms delay between moves. Every move was delivered through CUA Driver, with fresh desktop captures at checkpoints. No messages were sent to other people.

Passive production-code traces with synthetic snow mass are retained separately in the same artifact directory. The first captured the support deletion above the ordinary roof: shelf height sum about 3616 moved to the ground after 1038 particles were emitted. Those traces establish the faulty data path, while the final CUA captures verify the installed visual result.

## Automated and installation evidence

- `swift test --disable-sandbox`: 275 tests, zero failures, no skips. `/tmp/seasonart-cua-dock-full.log`.
- The constant-Dock regression failed before correction because no WindowUpdate or shelf existed with the pointer away. `/tmp/seasonart-cua-dock-red.log`.
- Other regressions cover elevated icons, four hide/return cycles retaining layer identity and exact heights, early reveal, current-frame contours and width changes preserving mass.
- Signed release build: exit 0. Packaging: 19 tests, OK. `/tmp/seasonart-cua-dock-{build,packaging}.log`.
- Installed `~/Applications/SeasonArt.app` at 16:01 MSK. Backup: `build/backups/20261109-160112-MSK-d722bca6/SeasonArt.app`. `/tmp/seasonart-cua-dock-install.log`.
- Build and installed executable SHA-256 both `1aae4f5e6b9f68fd887d5e3687b30e893cb96bae8345df131979ff1ba33c0447`. Strict installed codesign returned 0. One installed process was observed.
- Complete persisted preferences before/after GUI restoration compare equal, with zero changed keys. The screenshot setting was not modified.
- Independent read-only review of the final autohide branch found no concrete regression. `git diff --check` passed.

## Scope of proof

Native verification covers this Mac, the current display, magnification enabled, system autohide disabled and “Над Dock”. It does not establish every Spaces, external-display, sleep or autohide-enabled native case. Autohide reveal and repeated hide/return behavior are covered by tracker/simulation regressions.
