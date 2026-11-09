# Dock snow caps implementation plan

- [x] Add failing tests for local lift, actual icon rectangles, graceful fallback, smooth return, disabled/hidden Dock, and draw-buffer thickness/bounds.
- [x] Implement `DockSnowCap.swift` as a pure presentation model. Wire passive settings/icon geometry through `ScreenSnow` and `DockIconGeometry.swift`. Lift only the Dock columns in `SnowSimulation.writeLayers` and include the lift in `PileLayer.top`.
- [x] Validate with focused tests, the full Swift suite, a rendered comparison, signed build and packaging. Install with backup, verify unchanged settings and matching hashes. Record remaining native acceptance limitations.
