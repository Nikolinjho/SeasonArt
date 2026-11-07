# Settled snowman assembly and deeper joints

User report: three stacked snowballs did not create a snowman. Request: seat the component balls deeper for a natural joint.

Root cause: assembly was only attempted synchronously in endDragging, with a strict speed/contact gate. Later resting contacts were recorded for physics but never reconsidered for assembly.

- [x] Reproduce delayed three-ball assembly, head landing on a pair and deeper placement rejection. All three new tests failed on the old implementation.
- [x] Detect stable root-to-top chains from objectSupports after integration. Three balls resting for 0.2 simulated seconds form one snowman. A pair remains independently stackable. A fourth component remains separate. Keep the fast timer while awaiting stable contact.
- [x] Centralize joint overlap at 0.6 times the smaller radius (30% of its diameter). Update contact acceptance, shadow geometry and top torso button placement.
- [x] Preserve component counts in dense-scene tests, check 30/60/120 fps, held head, brief contact, fourth ball, decorations, existing motion and window tests.
- [x] Run final full native Swift suite, release/sign/package/install and verify signature/hash/preferences. 210 Swift tests, zero failures. 19 packaging tests, OK. Installed at 17:06 MSK, signature/hash/preferences verified. See docs/verification/settled-snowman-assembly.md.

Files: WinterScene.swift, WinterContactShadow.swift, WinterAssemblyTests.swift, WinterSceneTests.swift, WinterCollisionTests.swift and WinterObjectWindowTests.swift.

Native pointer-driven verification remains subject to the previously agreed input restriction. No commits or publication requested.
