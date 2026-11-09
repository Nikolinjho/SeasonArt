# Optional snow blizzard

The user requests slight chaotic motion resembling a blizzard, controlled by a separate toggle.

Add “Метель” to the existing menu, visible only in Snow mode. Default off, persist the choice independently of mode and intensity. Apply it to existing and newly attached displays. Turning the option on/off must wake a sleeping renderer.

Use a small deterministic wind field with smooth gusts and local variation in position, time and flake phase. Ramp its contribution in/out over about one second. Keep the existing particle count, accumulation and winter object physics. Apply wind only to falling snow, before the existing collision and deposition code. Do not repurpose the snow-clearing gust, which removes accumulated snow.

The default strength is mild. Bound the added horizontal wind to 100 pt/s and vertical wind to 20 pt/s before the existing velocity response. Different depths react differently. No per-frame random impulses or new dependencies. Other modes ignore the option and keep its saved value.

Validate persistence, smooth onset/decay, time/spatial variation, bounds and consistent ramps at 30/60/120 fps. Verify the actual simulation reacts to the toggle, retains collision handling, and does not generate particles at intensity Off. Run the full Swift suite with graphical-session access, signed build and packaging checks. Install locally with a backup. Native pointer automation remains excluded without an agreed time.
