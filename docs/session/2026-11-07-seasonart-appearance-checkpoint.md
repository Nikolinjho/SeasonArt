# SeasonArt appearance checkpoint: 7 November 2026, 16:49 MSK

Latest delivery: [settled snowman assembly, 7 November 2026, 17:06 MSK](../verification/settled-snowman-assembly.md). It supersedes this installation hash and the earlier 15% joint overlap. The current app assembles a stable three-component stack after landing, with 30% overlap, and passes 210 Swift / 19 packaging tests. This appearance checkpoint is retained as history.

Latest delivery extends the context from 2026-11-07-seasonart-memora-current.md. Its previous installation hash and time are historical. All earlier interaction restrictions and unfinished native acceptance still apply.

User requested contact shadows on stacked snowballs/snowmen, then wooden snowman arms. Both are implemented and installed in ~/Applications/SeasonArt.app. Background launch, strict signature, identical build/install hashes and unchanged preference dictionaries verified.

Executable SHA256: 47b3c37268db88f36b028bfd2cc977ccdf1e1db64d4026d0f37135d4ee513105. Backup: build/backups/20261107-164951-MSK-77a722f1/SeasonArt.app.

Full native Swift suite: 204 tests, zero failures, no skips. Subsequent preview-layout-only change: 15 focused appearance/window tests, zero failures. Packaging: 19 tests, OK. AppKit rendered comparison inspected, native pointer-driven gestures not performed. No global input or focus changes used.

Source: ~/SeasonArt-worktrees/snowball-sculpting, fix/winter-object-capacity, HEAD 8f70403 plus uncommitted changes. All earlier dirty work retained. Main checkout unchanged, no commits/push/integration requested.

New source: WinterContactShadow.swift, WinterSnowmanArms.swift. Updated WinterObjectView, WinterObjectWindow and controller refresh delivery. Physical object frames remain the ball frames. Window presentation bounds include arm strokes. Shadows preserve alpha using source-atop and invalidate on neighbouring object movement.

Detailed evidence: docs/verification/winter-appearance.md. Rendered comparison: docs/verification/artifacts/contact-shadows/comparison.png. Local logs: /tmp/seasonart-winter-appearance-{full-tests,tests,build,packaging,install}.log.

Current cmux caller: workspace:86, surface:289. Workspace SeasonArt · тени и руки снеговика, tab проверка. Re-identify caller in a new session. Memora has not been updated by this delivery.
