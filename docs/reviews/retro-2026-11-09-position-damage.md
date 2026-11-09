# Dock placement and impact damage retrospective

The user clarified that Dock placement is one exclusive choice, rather than two independent toggles. Keep the approved menu labels and selection model in the feature spec. No global instruction change is needed.

The initial view invalidation fixture used a detached NSView, for which needsDisplay did not behave like a live content view. Attaching it to the same nonactivating panel used by production made the check meaningful without showing or focusing a window. A separate pixel comparison verifies the real silhouette.

Independent review caught deferred mode transitions bypassing ScreenSnow.mode, plus the gap caused by using ideal circles above a damaged base. Regression tests reproduced both before correction. The final contact test checks visible contours, rather than only nominal frames. A transfer test at the screen edge also exposed deposit overflow and now protects mass conservation.

No skill or global rule changes are proposed. Native hover and manual Spaces acceptance are separate from model and rendering tests.
