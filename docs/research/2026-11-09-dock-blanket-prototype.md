# Continuous Dock snow prototype

The user rejected the installed two-layer implementation as still looking chopped. Do not treat the 246 passing tests as visual acceptance. The currently installed executable remains SHA-256 `52095f8cae7357c52811df57a078e6e640c4c6c4aa3d3e1ec3825b5ddfbd5c29`. No product source or installed app changed during this prototype round.

The proposed replacement is one continuous snow height field. Its lower boundary is the maximum of the Dock shelf and the real opaque icon contours, with slight overlap. The upper boundary includes a short, concave shoulder filling gaps between icon supports. Smoothing applies to the snow surface, not to the supporting geometry. This gives the gaps actual snow volume instead of disconnected thin caps or a floating bent ribbon.

Two variants were rendered with real local Finder, Chrome, Telegram, Slack, VS Code, Obsidian, Safari, Xcode and Settings images and the existing Metal pile shader:

- `docs/verification/artifacts/dock-blanket/compact.png`: 7 pt nominal depth.
- `docs/verification/artifacts/dock-blanket/fluffy.png`: 11 pt nominal depth.

Both were inspected and shown to the user. The user selected both appearances depending on accumulated snow. The single-surface implementation is installed and documented in `docs/verification/dock-snow-surface.md`. These previews are synthetic scenes, not native Dock captures. Native appearance and animation remain unverified.

The standalone source is retained locally in `docs/verification/artifacts/dock-blanket/preview.swift` and `Uniforms.swift`. The preview builds against `DockSnowCap.swift`, `DockIconGeometry.swift` and `Shaders.swift`. Output is local and ignored by Git. No GUI input, focus change, settings change, installation or publication occurred.

After the user selects or revises the appearance, implement a single presentation surface instead of separate base/cap draw layers. Preserve the corrected AXList layout and per-layer column width, blizzard, physical mass and winter object supports. Replace continuity tests with assertions on a single connected surface, actual icon contact, no rectangular masks and moving/shrinking layout. Validate the actual native result before claiming acceptance.
