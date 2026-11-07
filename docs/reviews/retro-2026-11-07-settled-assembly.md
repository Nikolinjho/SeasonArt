# Settled assembly retrospective

Signal: user reported failure to create a snowman after stacking three balls, following the appearance delivery. Earlier tests covered synchronous release at a prepared contact and explicitly preserved independent resting balls. They missed the complete three-component resting stack.

Finding: release-time checks do not cover placement that finishes through simulation. New tests cover the complete settling lifecycle and verify delayed assembly, realistic release speed, stability, frame rates and fourth-ball handling. The full-scene assertion now verifies component conservation because object count legitimately decreases on assembly. No skill/rule changes proposed.

Native acceptance still remains separate. Do not equate model tests or render previews with a successfully executed desktop gesture.
