# Project status

Updated: 2026-10-23

## Canonical project

- **Engine:** Godot 4; the active project is [`godot/project.godot`](godot/project.godot).
- **Repository:** `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`, branch
  `codex/m34-canopy-composition`.
- **M40 v3 (current):** commit `68a8d8e`
  (`M40: add block placement preview and orientation feedback`), with the
  evidence/report commit following it. This adds the real-time placement ghost,
  exact partial/rotated geometry, valid/invalid states and the UI input gate to
  the completed M40 work. It builds on M40 v2 (`c6bc97b`), which superseded the
  earlier inline-grid M40 screen (`195b105`, `13c574a`, `47fd5fa`, `c4ac3c5`,
  `2afab28`); all remain in history.
- The Godot project was promoted from `godot` to the top-level `godot/`
  folder. Its project-relative `res://` layout is preserved.
- The previous Python + Ursina runtime and its Python tests, scripts, dependencies,
  settings, and source textures are retained under `archive/ursina/` as deprecated
  reference material. They are not part of the active development path.

## Milestones

- **M33–M36** are complete.
- **M37** remains **partial**: generator v8 improves forest openings but the
  normal gameplay view still contains a dense tree line on the right hillside.
  See [`prototypes/m17/results/godot/m37-report.md`](prototypes/m17/results/godot/m37-report.md).
- **M38 and M39** remain deferred.
- **M40 — Inventory, Character and Crafting UI Overhaul is COMPLETE**, with
  documented limitations. The screen now has three distinct pages (Inventory,
  Crafting, Character), a stable character preview, explicit full/half/single/
  amount stack movement, an item-actions card and quantity dialog, and a
  searchable recipe browser with categories, ingredient availability, station
  requirements and atomic quantity crafting. Equipment gameplay, experience/
  level, defence/armour and the Map screen are not implemented in the game and
  are presented as unavailable rather than faked.
  See [`prototypes/m17/results/godot/m40-report.md`](prototypes/m17/results/godot/m40-report.md).
- **M40 v3 — Block Placement Preview and Orientation Feedback is COMPLETE.**
  `VoxelPlayer.placement_preview()` is the single source for the destination,
  orientation and validity; `place_selected()` consumes the same result. A
  world-space ghost is meshed by the real `ChunkMesher`, so cubes, slabs, stairs,
  ramps, ridges and stations show their actual geometry. Valid/invalid states,
  the targeted surface, the destination cell, slab halves and directional
  facing are visually distinct, and the ghost hides while any interface owns
  input. See
  [`prototypes/m17/results/godot/m40-placement-preview-report.md`](prototypes/m17/results/godot/m40-placement-preview-report.md).

## Validation

Validated with Godot 4.7.2 after the M40 v2/v3 work:

- Unit suite: `M17_TESTS_PASS 3283 assertions` (M40 v2 baseline: 3092; v2
  pre-overhaul baseline: 3043).
- Integration suite: `M17_INTEGRATION_PASS 519 assertions` (M40 v2 baseline:
  503; includes real-scene preview-stability, navigation, crafting,
  amount-dialog and placement-ghost input/geometry checks).
- Regression: `M17_REGRESSION_PASS assertions=52`.
- Placement captures: `prototypes/m17/results/godot/m40-place-cube.png`,
  `m40-place-slab.png`, `m40-place-slab-top.png`, `m40-place-stair.png`,
  `m40-place-invalid.png`, with `m40-place-capture.json`. These show the real
  mesh ghost in the running game, the actual slab half, the rotated stair with
  its facing arrow/face, and the red invalid occupied state.
- M40 v2 captures: `prototypes/m17/results/godot/m40v2-inventory-1280.png`,
  `m40v2-inventory-1600.png`, `m40v2-character-1280.png`,
  `m40v2-crafting-1280.png`, `m40v2-crafting-missing-1280.png`,
  `m40v2-amount-1280.png`, `m40v2-hud-1280.png`, plus the old-defect evidence
  `m40v2-preview-bug-before.png` / `m40v2-preview-bug-after.png`.
  These are rendered viewport captures from the running game, not desktop
  screenshots or mockups. The fixed preview rect remained `(148, 119, 200, 290)`
  through the runtime focus/actions/page-switch/reopen checks.
