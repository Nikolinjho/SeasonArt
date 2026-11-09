# Dock badge snow implementation plan

**Goal:** Cover live notification badges with the same snow surface as Dock icons.

**Architecture:** AXStatusLabel feeds DockSnowBadge geometry, attached to DockSnowIcon. The roof query combines both supports. Existing simulation/rendering/contact paths consume that combined roof.

- [x] Add failing regressions using measured native badge bounds, rounded capsule shoulders, absent labels, scaling and badge removal.
- [x] Read AXStatusLabel in the existing batched AX call, build badge geometry and include it in icon roof queries and interaction bounds.
- [x] Verify the production simulation buffer at the badge roof, shared snowball contacts and unchanged mass. Run focused and full Swift checks, build and packaging.
- [ ] Install with backup, verify preferences/signature/hash, inspect native CUA screenshots when the shared desktop is available, and document the observed scope.

Installed and signature/preferences verified. Native CUA acceptance remains pending shared desktop availability. The terminal input-line report remains open. See ../../verification/dock-badge-snow.md.
