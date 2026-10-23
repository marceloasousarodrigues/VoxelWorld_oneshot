# Project status

Updated: 2026-10-23

## Canonical project

- **Engine:** Godot 4; the active project is [`godot/project.godot`](godot/project.godot).
- **Repository:** `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`, branch
  `codex/m34-canopy-composition`. M40 code is commits `195b105`
  (`M40: implement inventory, crafting and gameplay UI`) and `47fd5fa`
  (`M40: finalize HUD hint clearance and refresh captures`).
- The Godot project was promoted from `godot` to the top-level `godot/`
  folder. Its project-relative `res://` layout is preserved.
- The previous Python + Ursina runtime and its Python tests, scripts, dependencies,
  settings, and source textures are retained under `archive/ursina/` as deprecated
  reference material. They are not part of the active development path.

## Milestones

- **M33–M36** are recorded as complete.
- **M37** remains **partial**: generator v8 improves forest openings but the
  normal gameplay view still contains a dense tree line on the right hillside.
  See [`prototypes/m17/results/godot/m37-report.md`](prototypes/m17/results/godot/m37-report.md).
- **M38 and M39** remain deferred.
- **M40 — Inventory, Crafting and Gameplay UI is COMPLETE**, with documented
  limitations. The unified screen adds the reference-style navigation, player
  and equipment presentation, 27+9 inventory, real 3x3 crafting grid, hotbar,
  hearts/hunger HUD and contextual controls. Equipment gameplay, experience/level
  and the Map screen are not implemented in the game and are presented as
  unavailable rather than faked. See
  [`prototypes/m17/results/godot/m40-report.md`](prototypes/m17/results/godot/m40-report.md).

## Validation

Validated with Godot 4.7.2 after the M40 implementation:

- Unit suite: `M17_TESTS_PASS 3043 assertions` (M40 baseline: 2923).
- Integration suite: `M17_INTEGRATION_PASS 489 assertions` (baseline: 463;
  includes 26 real-scene M40 checks).
- Regression: `M17_REGRESSION_PASS assertions=52`.
- Runtime captures: `prototypes/m17/results/godot/m40-inventory-1280.png`,
  `m40-inventory-1600.png`, `m40-character-1280.png`, `m40-hud-1280.png`.
  These are rendered viewport captures from the running game, not desktop
  screenshots or mockups.
