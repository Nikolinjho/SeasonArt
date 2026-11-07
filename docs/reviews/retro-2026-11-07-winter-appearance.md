# Winter appearance retrospective

Scope: contact shadows and wooden snowman arms.

Signals: the first image test detected increased alpha at antialiased edges with source-over drawing. Source-atop fixed the actual rendering problem. An unattached NSView did not retain a redraw flag, so the invalidation test now uses a hidden real WinterObjectWindow. AppKit rounds window bounds to whole points, so bounds assertions allow one point of rounding. Native Dock tests require graphics-session access, as documented in the earlier checkpoint.

No user correction of requirements occurred. Adding arms was an explicit extension of the scope. Existing dirty changes were retained, no global pointer input was used, and no commits or publication were requested. No instruction/skill changes proposed.
