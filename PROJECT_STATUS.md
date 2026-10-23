# Project status

Updated: 2026-10-23

## Canonical project

- **Engine:** Godot 4; the active project is [`godot/project.godot`](godot/project.godot).
- **Repository:** `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`, branch
  `codex/m34-canopy-composition`.
- **M40 v2 (current):** commit `c6bc97b`
  (`M40: overhaul inventory, character and crafting UI`), with the
  evidence/report commit following it. This supersedes the earlier inline-grid
  M40 screen (`195b105`, `13c574a`, `47fd5fa`, `c4ac3c5`, `2afab28`), which
  remains in history.
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

## Validation

Validated with Godot 4.7.2 after the overhaul:

- Unit suite: `M17_TESTS_PASS 3092 assertions` (pre-overhaul: 3043).
- Integration suite: `M17_INTEGRATION_PASS 503 assertions` (pre-overhaul: 491;
  includes real-scene preview-stability, navigation, crafting and amount-dialog
  checks).
- Regression: `M17_REGRESSION_PASS assertions=52`.
- Runtime captures: `prototypes/m17/results/godot/m40v2-inventory-1280.png`,
  `m40v2-inventory-1600.png`, `m40v2-character-1280.png`,
  `m40v2-crafting-1280.png`, `m40v2-crafting-missing-1280.png`,
  `m40v2-amount-1280.png`, `m40v2-hud-1280.png`, plus the old-defect evidence
  `m40v2-preview-bug-before.png` / `m40v2-preview-bug-after.png`.
  These are rendered viewport captures from the running game, not desktop
  screenshots or mockups. The fixed preview rect remained `(148, 119, 200, 290)`
  through the runtime focus/actions/page-switch/reopen checks.
