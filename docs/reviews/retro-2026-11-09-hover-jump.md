# Dock hover jump retrospective

The user reported that the earlier Dock snow problem persisted after installation. Previous checks covered fullscreen disappearance, contour rendering, mass transfer and ball contacts, but did not exercise the zero-height reserved-rectangle branch with the pointer above the ordinary shelf.

Passive observation caught that exact branch: the tracker inferred that the shelf had disappeared while the pointer was on an enlarged icon. The simulation then correctly followed the incorrect deletion event and shed the snow. Changing its final distribution could not repair that ownership error.

The regression now drives the real WindowTracker and SnowSimulation through repeated pointer leave/return cycles and verifies layer identity, unchanged mass and zero emitted particles/ground deposits. Elevated-icon geometry is tested separately. This session's evidence is recorded in `docs/verification/dock-hover-jump.md`.

No global skill or instruction change is proposed. No native acceptance is inferred from passing model tests or from a passive run without hovering.

A post-fix passive hover exposed a second source of jumping: early Dock reveal samples were processed as a window jerk, lifting the snow above the break threshold and shedding it before it redeposited. A regression using the earlier reveal frame reproduced the effect (891 particles and an empty shelf). A later reveal frame did not reproduce it, so matching the early part of the measured transition mattered. The physical Dock now follows its system geometry without the ordinary-window inertia response.

The AX layout was sampled before the new window frame and still carried the prior vertical origin. Another regression measured a contact at 137.58 pt rather than below 101 pt. The current physical frame now supplies vertical geometry. Changing shelf widths is separately protected by a mass-preserving resampling regression.

The user then explicitly requested CUA Driver verification within 15 minutes. CUA immediately showed a permanently visible Dock while the tracker considered it absent away from the pointer. The actual autohide setting was false, despite the zero-height SLS reserved rectangle. The final correction uses that setting rather than inferring autohide from reserved height alone. A new regression reproduced the absent shelf before correction. The installed fix completed seven controlled native hover/leave cycles, with visible snow remaining on and following the Dock. Native screenshots and scope limits are recorded in the verification document. Temporary GUI changes were restored and persisted preferences compare equal.
