# Snow on Dock notification badges

The user explicitly selected snow on top of the red notification circles, rather than leaving them exposed above the drift.

Read the current AXStatusLabel with the icon geometry. Treat a present badge as a rounded support attached to the upper-right corner of that icon, scaled with its current size. Combine the icon alpha roof and badge roof by taking their maximum, then use the existing single DockSnowSurface and shared toy/sculpting contact buffer. A disappearing/changed badge updates the same surface on the next geometry sample. Do not add a separate snow layer or modify accumulated physical mass.

Dock exposes badge text, but no child element or badge rectangle on this Mac. Its capsule geometry is therefore modeled from measured native screenshots, not claimed to be a directly reported AX rectangle. Normal 47 pt icon samples have an 18 by 18 pt red badge at the upper-right corner, about 4 pt below the logical image top. Longer labels may widen the capsule. Verify the model visually against native one- and two-digit badges after magnification.

No new user setting is needed. The existing above/below choice and Dock visibility fixes remain in effect.
