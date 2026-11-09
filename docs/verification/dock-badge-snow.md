# Snow on Dock notification badges

9 November 2026, 16:22 MSK. Installed local uncommitted changes over master `7562add`. Version remains 0.1.5/build 6.

## Implementation

Dock exposes AXStatusLabel (observed values “2” and “19”) but no child badge elements or separate badge rectangle on this Mac. DockIconGeometry reads that label in its existing batched AX request. DockSnowBadge models the measured round/capsule shape at the icon's upper-right corner and scales it with the icon. DockSnowIcon.top(at:) returns the higher of the image alpha roof and badge roof. Existing DockSnowSurface, snowball contact and sculpting buffers consume that same combined contour. Badge disappearance removes the support on the next geometry sample. No physical snow mass is created by the added support.

Normal native 47 pt icons had red badge bounds approximately 18 by 18 pt, with the top about 4 pt below the logical image top. The capsule model is derived from those screenshots and AX label text, rather than claimed to be an exact AX-reported rectangle. A fixed reference font is scaled with the icon to avoid changes from font optical sizing during magnification.

## Evidence

- `swift test --disable-sandbox`: 280 tests, zero failures, no skips. `/tmp/seasonart-badges-full.log`.
- New regressions cover measured native bounds for one/two digits, missing labels, wider labels, proportional scaling, rounded shoulders, disappearance, shared winter contact and unchanged mass.
- The first scale test exposed width ratio 1.550 instead of 1.617 because the system font's optical sizing changed with point size. The fixed reference font passes the proportional scaling check.
- Signed release build: exit 0. Packaging: 19 tests, OK. `/tmp/seasonart-badges-{build,packaging}.log`.
- Installed in `~/Applications/SeasonArt.app` at 16:22 MSK. Backup `build/backups/20261109-162246-MSK-7591ac89/SeasonArt.app`. `/tmp/seasonart-badges-install.log`.
- Build and installed executable SHA-256 match: `9d088cdf3b1acf52313e8788a05f25bdea3700305b75196b8f0505c13c538645`. Strict installed codesign returned 0. One installed process was observed.
- Full persisted preferences before/after installation compare equal. No screenshot or intensity setting was changed during this task.
- Independent read-only review found no important badge regression.

## Native acceptance and new report

Native hover acceptance of this badge model is pending. Passive CUA observations showed active keyboard/pointer use, then a browser meeting, so no desktop input was taken. A scheduling question is pending. Screenshots and passive AX measurements stay in ignored local `docs/verification/artifacts/dock-badges/`.

During this work the user reported snow along a terminal search/input line across the screen. The report steers the active task and remains open. A passive production WindowTracker probe recorded actual surfaces and owner processes without input control. The currently observed cmux window was its normal outer window, with no internal search/input support in the trace. The report itself was no longer visible on the active desktop when captured. No speculative product filter was added and this bug is not claimed fixed.

The trace also showed separate Chrome window fragments while a fullscreen browser Space changed. That is a diagnostic lead, not evidence that Chrome caused the reported terminal line. Native control/trigger identification and a capture while the line is present are still needed. The trace and AX observations are local artifacts, not published.

The user clarified that the affected line is the Codex prompt inside the cmux terminal, not Cmd+F search. A temporary in-process trace sampled actual pile supports, rendered pile bounds, target sizes and WindowServer geometry every 250 ms. It did not record terminal text or window titles. The captured interval had no pile at the reported prompt height. Main rendering used 1728×1117 logical/pixel dimensions; the Dock strip used 1728×160 logical and 3456×320 pixels. Interior full-width piles occurred only near screen Y=74 during the Chrome transition and had occluders. A second read-only renderer review found no substantiated cause. The trace cannot exclude a transient shorter than the sampling interval or a compositing artifact.

Diagnostic source and renderer hooks were removed after collection. The saved trace is ignored under `docs/verification/artifacts/terminal-input-line/surfaces.jsonl`. Clean-source validation at 16:45 MSK: 280 tests, zero failures, one skip; packaging 19 tests, OK. Logs: `/tmp/seasonart-terminal-clean-{tests,packaging,build,install}.log`. The terminal band remains unresolved.

Clean build installed at 16:46 MSK. Built and installed executable hashes match `6fc03e803b62a287a8e3643d64bf8a89f66060aaf4d672052c948f726718069a`; strict codesign passes and one installed process runs. The skipped test requires a visible system Dock to inspect native window ordering. No terminal-band fix is included in this build.

At 16:59 MSK a second, event-based diagnostic build was installed after the user narrowed the trigger: beginning to type sheds snow from the line above the Codex prompt. `SEASONART_SHEDDING_TRACE=1` temporarily records each release/shed source and source call site, plus geometry when a snowy window vanishes. No text or keys are recorded; only elapsed time since key-down. The log is bounded to 1 MiB at `/tmp/seasonart-snow-shedding.jsonl`. Packaging: 19 tests, OK. Persisted preferences compare equal. This diagnostic is intentionally active for the next user reproduction and must be removed afterward; it is not a fix. Separate CUA captures of the main/Dock overlays before that reproduction showed ground and Dock only. Foreground input has not been taken while a shared-desktop scheduling question is pending.

The user then clarified that the line itself appears infrequently and was absent during the requested typing attempt. Treat typing as the shedding trigger only when the anomalous line already exists, not as a reliable trigger for creating it. Keep the bounded event trace for natural recurrence; no repeated forced typing or speculative fix is warranted by this observation.
