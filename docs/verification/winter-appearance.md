# Winter object appearance

Date: 7 November 2026, MSK.

Contact shadows use a soft blue-grey elliptical radial gradient clipped to the lower ball. Source-atop compositing preserves the silhouette's alpha. Internal snowman joints and separate stacked objects share the same circle geometry. Near contact fades on separation, side contacts and hidden/dragged neighbours do not cast these shadows. Internal shadows remain on a snowman while it is dragged. Shadow changes invalidate the receiving view even if its own model does not move.

Snowmen have brown wooden arms with forked ends, scaled to the middle ball. They render behind the snow. Window presentation bounds include all branch tips and stroke widths. Physical frames, supports and circle collisions continue to use the snowballs. Single balls and pairs have no arms. Reference inspected locally: docs/research/reports/assets/2026-11-06-koiart-winter-scenes/snowman-build.jpg in the main SeasonArt checkout.

## Verification

- `swift test --disable-sandbox` with access to the native graphics session: 204 tests, zero failures, no skips. Log: /tmp/seasonart-winter-appearance-full-tests.log.
- After adjusting only the comparison image layout: 15 focused shadow/arms/window tests, zero failures. Log: /tmp/seasonart-winter-appearance-tests.log.
- Image comparison inspected: docs/verification/artifacts/contact-shadows/comparison.png. Upper row has no contact shadows, lower row has shadows. Both rows include arms. This is AppKit rendering from the actual view, not a screenshot of live desktop objects.
- Pixel tests cover shadow darkening and unchanged silhouette alpha for pairs, snowmen with different radii, and separate balls/figures resting on a ball. Additional checks cover no shadows from distant/side/hidden/dragged neighbours, invalidation after separation, and arm/window geometry.
- The first sandboxed full run had three NSScreen=nil failures in existing Dock tests. Running with native graphics access resolved all three.

Native pointer-driven assembly/dragging has not been repeated. Earlier native acceptance limitations remain.

## Installed delivery

Installed and launched in the background on 7 November 2026 at 16:49 MSK: /Users/itsnikoko/Applications/SeasonArt.app. Signed with Oasis Dev. `codesign --verify --deep --strict` exited 0. Built and installed executable SHA256 matched: 47b3c37268db88f36b028bfd2cc977ccdf1e1db64d4026d0f37135d4ee513105.

`SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v`: 19 tests, OK. Build and install scripts exited 0. Complete preference dictionaries compared equal before and after installation. Installed executable process was found by its exact application path. Build has one existing unused-variable warning in SnowSimulation.swift, outside the appearance changes.

Backup: build/backups/20261107-164951-MSK-77a722f1/SeasonArt.app. Source remains the dirty fix/winter-object-capacity worktree at HEAD 8f70403, with all earlier changes retained. No commits, integration or publication performed.
