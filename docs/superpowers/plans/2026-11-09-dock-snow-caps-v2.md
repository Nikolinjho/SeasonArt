# Attached icon snow caps

- [x] Reproduce the rejected fallback: no icon geometry still generated a 28.99 pt wave. Add a failing regression forbidding it.
- [x] Replace the broad wave with per-icon alpha-contour caps, exclude AX item margins, remove positional lag and vary only snow thickness. Keep physical mass unchanged.
- [x] Add explicit user-driven Accessibility setup instead of an approximate geometry fallback. Never request access on startup.
- [x] Check real Finder image composition and Metal output, transparent image margins, direct contact, shrinking at 30/60/120 fps, and absence of distant deformation.
- [x] Run full tests, signed build and packaging, install with backup and verify signature/settings. Record native acceptance limits.
