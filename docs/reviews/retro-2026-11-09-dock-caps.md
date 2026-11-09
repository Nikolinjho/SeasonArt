# Dock caps retrospective

The first mass assertion filled the whole open Dock ledge, so ordinary edge spilling reduced the ledge mass during simulation. The fixture now fills an interior patch and checks unchanged mass separately from rendering offsets. This was a fixture issue, not evidence of snow loss caused by caps.

The Metal test validates the actual pile shader, including its vertex bounds. The resulting preview is a synthetic snow profile, not a native Dock hover capture. Native alignment and edge-icon behavior remain unverified. No shared input was used and no additional permission was requested.

No new global rules or skills are proposed.

## User rejection of the first appearance

The user rejected the cap as a floating, unrealistic wave. The previous fallback used cursor position and settings rather than a real icon boundary. Its GPU test checked visible pixels above Dock, which allowed the wrong visual design to pass.

The revised test composes the real Finder image with the actual snow shader. Contact tests use the opaque image contour, exclude transparent margins and reject any geometry-free wave. Native hover and the AX-to-image padding still need verification. Test success is not user acceptance of the appearance.

## Accessibility boundary

A subsequent in-app probe found AXIsProcessTrusted=false and zero icons, despite terminal probes having access. The installed app and the terminal have separate TCC identities. Diagnose the actual process before interpreting native behavior or asking for another hover. No geometry adjustment is justified until the installed process can read the Dock.

## Rejection after layout and continuity changes

After Accessibility was granted, native capture exposed a 960-to-1065-point Dock width change and stale child positions. Fixing layout and splitting the drawing into base/cap layers passed 246 tests but the user still rejected the appearance as chopped. The separation of the base and caps is now the design under question. Further installation was deferred while two continuous-surface previews were prepared for visual selection. Tests do not substitute for agreement on the desired visual topology.
