# Project status

Updated: 2026-10-24

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
- **M41: Player Character, First-Person Arms and Third-Person Camera is
  COMPLETE**, including the M41b visual correction pass. First person remains
  the default and renders a deliberately modelled tool with a wrapped grip in a
  visible voxel hand at the lower right. Third person renders the shared
  articulated character (backpack, bedroll, pouches and layered clothing) left
  of the crosshair, with a collision-safe over-the-shoulder camera (3.8 m
  default, 0.70 m side offset), F4 view toggle and persisted Settings controls.
  Both views use the same controller, inventory, targeting and placement
  transaction. See
  [`prototypes/m17/results/godot/m41b-report.md`](prototypes/m17/results/godot/m41b-report.md)
  and the external asset review
  [`m41b-external-asset-review.md`](prototypes/m17/results/godot/m41b-external-asset-review.md).
- **M41c (current): First-Person Hand and Tool Visual Polish is COMPLETE**, with
  documented limitations. The M41b detail layers had been authored on the side
  of the tool facing away from the camera; M41c moved every face plate, boss,
  rivet and edge to the camera-facing side and rebuilt the pickaxe, axe, shovel
  and sword as layered metal heads on segmented wooden hafts. The fist is now
  built in the item frame with four finger wraps, a thumb, knuckles, creases and
  a wrist strap, so it closes around the haft. The hand/tool assembly sits in
  the lower-right quadrant and stays clear of the reticle (measured pickaxe
  footprint 38.3% width / 45.1% height, highest local point `-0.0559`). The
  camera, aiming, mining, placement and inventory behaviour are unchanged. See
  [`prototypes/m17/results/godot/m41c-report.md`](prototypes/m17/results/godot/m41c-report.md)
  and [`m41c-asset-review.md`](prototypes/m17/results/godot/m41c-asset-review.md).

## Validation

Validated with Godot 4.7.2 after the M41c visual pass:

- Unit suite: `M17_TESTS_PASS 3605 assertions`, exit 0 (M41b baseline 3497;
  the new `test_tool_visuals.gd` adds 108 assertions). The only stderr is the
  intentional corrupt-save parse error from `test_m26_protection.gd`.
- Integration suite: `M17_INTEGRATION_PASS 621 assertions`, exit 0, empty
  stderr (includes real F4 switching, camera collision, third-person placement,
  mining, creature targeting and menu-state checks).
- Regression: `M17_REGRESSION_PASS assertions=52`, exit 0, empty stderr.
- M41c captures: `prototypes/m17/results/godot/m41c-before-after.png`,
  `m41c-grip-closeup.png`, `m41c-states.png`, `m41c-demo-00.png` through
  `m41c-demo-10.png`, `m41c-demo-manifest.json`, plus the supplementary
  `m41c-model-lineup.png` and `m41c-model-pickaxe.png`. The gameplay images are
  offscreen viewport captures from the running game, not mockups.
- External resource review for M41c: `m41c-asset-review.md`. Quaternius Cube
  World Kit (CC0) was previewed but its tools are simpler than the target;
  Kenney Voxel Kit (CC0) was downloaded to a temporary folder and contains only
  plain cubes; Kenney Voxel Pack (CC0) is 2D. Nothing was imported.
- M41b captures: `prototypes/m17/results/godot/m41b-first-person-pickaxe.png`,
  `m41b-first-person-axe.png`, `m41b-first-person-shovel.png`,
  `m41b-first-person-sword.png`, `m41b-third-person-rear.png`,
  `m41b-third-person-walking.png`, `m41b-third-person-jumping.png`,
  `m41b-third-person-swing.png`, `m41b-third-person-sword.png`,
  `m41b-first-person-axe-swing.png`, `m41b-before-after.png`,
  `m41b-character-preview.png`, `m41b-settings-camera.png`, plus the ten-frame
  `m41b-camera-demo.gif` and `m41b-demo-manifest.json`. These are rendered
  viewport captures from the running game, not desktop screenshots or mockups.
- External resource review: `m41b-external-asset-review.md` with inspected
  previews under `m41b-asset-previews/`. No external asset was integrated.
- Camera captures: `prototypes/m17/results/godot/m41-first-person.png`,
  `m41-first-person-sword.png`, `m41-third-person.png`,
  `m41-third-person-sword.png`, `m41-character-preview.png`,
  `m41-settings-camera.png`, plus the eight-frame `m41-camera-demo.gif` and
  `m41-demo-manifest.json`. These are rendered viewport captures from the running
  game, not desktop screenshots or mockups.
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
