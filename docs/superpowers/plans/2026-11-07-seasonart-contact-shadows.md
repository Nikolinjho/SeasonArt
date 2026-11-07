# Winter object contact shadows

Goal: soft blue-grey contact shadows beneath stacked snowballs, including snowman joints and separate stacked figures.

Design: derive shadows from component circles in scene coordinates, return receiver-local descriptors, clip each radial gradient to its receiving ball. Render bottom to top so upper balls cover joint overlap. Recompute on scene refresh and invalidate views when shadow descriptors change. Preserve physics, input, window bounds and decorations.

- [x] Add image-based regression coverage for joints, separate stacks, separation and transparent silhouettes.
- [x] Implement geometry in WinterContactShadow.swift, drawing in WinterObjectView.swift and delivery through WinterObjectWindow.swift / WinterSceneController.swift.
- [x] Add wooden forked arms at the user's follow-up request. Extend presentation bounds without changing the physical ball frames. Check window bounds at different torso sizes.
- [x] Run focused tests, inspect rendered before/after images, then run the full Swift suite and build a signed app.

Verification: `swift test --disable-sandbox --filter WinterContactShadowTests`, `swift test --disable-sandbox`, `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh`.

Work in the existing dirty snowball-sculpting worktree. Preserve earlier changes. No publication or commits requested. Native pointer-driven acceptance requires a separate agreed input window.

Evidence: full native Swift suite passed 204 tests with zero failures. A subsequent preview-layout-only change passed 15 focused appearance/window tests. See docs/verification/winter-appearance.md for delivery evidence.
