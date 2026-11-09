# Dock badge snow retrospective

The native Dock badge text is available through AXStatusLabel, but no separate badge child geometry is exposed. The implementation models the visible capsule from measured native images and records that limitation rather than presenting inferred geometry as AX data.

A scaling regression caught optical-size changes in NSFont metrics. Measuring at one reference size and applying the icon scale keeps capsule width continuous.

The user's terminal-line report arrived during this feature. Implementation and installation of the badge feature continued independently, while the new bug was observed passively. Shared desktop input was not taken during active use. The new line report remains unresolved rather than being folded into a false completion claim for the badge feature.

No global skill or instruction changes are proposed.
