# M40 v3 - Block Placement Preview and Orientation Feedback

**Status: COMPLETE**, with the limitations listed below.

**Base:** `5da7cbb` (`M40: keep recipe details in sync with browser filters`).
**Code commit:** `68a8d8e`
(`M40: add block placement preview and orientation feedback`).
**Canonical project:** `C:/Users/Admin/Documents/Projects/VoxelWorld_Godot`.
No project copy or worktree was created, and no M38/M39 work was started.

## Problem

The running game already had a HUD line describing the next placement, but the
player could not see where the block would go, what partial shape it had, or how
a directional piece was rotated before committing the action. The HUD preview
and `VoxelPlayer.place_selected()` also implemented the same rules twice, so a
separate visual preview would have been able to disagree with the block that was
actually written.

## Implementation

### One authority for cell, shape and validity

`VoxelPlayer.placement_preview()` now returns the complete placement decision:
item, block id, hit target, destination cell, hit normal, orientation, validity,
refusal reason/message, and whether the destination is inside the supported
preview range. `place_selected()` consumes that exact dictionary instead of
recomputing the cell or orientation. The HUD and the world-space ghost read the
same result.

The existing rules are preserved:

- destination = targeted block + hit normal;
- occupied cells are refused unless the occupant is a liquid;
- cells intersecting the player capsule are refused;
- vertical build limits and loaded-chunk checks are applied;
- stairs/ramps/ridges keep the existing `placement_facing` rule and `R` control;
- slab halves keep the existing top-face/underside rule.

### Real geometry, not a second model

`BlockPlacementPreview` builds a one-cell isolated `ChunkData` with the previewed
block id and orientation and runs the project's real `ChunkMesher` over it. The
ghost therefore uses the same cube, slab, stair, ramp, ridge and custom-station
geometry as the placed block. A private mesher instance keeps preview rebuilds
out of the streaming mesher's performance counters.

### Visual language

- **Valid**: translucent green real geometry + green destination-cell outline.
- **Invalid**: translucent red real geometry + red outline; the red ghost uses
  no-depth-test when invalid so an occupied destination remains visible through
  the occupying block.
- **Targeted surface**: amber translucent face patch, separate from the
  destination cell.
- **Directional facing**: a 3D yellow arrow plus a cyan forward-face marker for
  stairs/ramps; a cyan long-axis strip for ridges. Cyan is deliberately reserved
  for rotation feedback.
- **Slabs**: the actual lower or upper half is rendered. The HUD names
  `bottom half` or `top half (upside down)` instead of a misleading horizontal
  facing.
- **Hidden**: no placeable item, no target, interface/overlay owns input, pause,
  death, outside the buildable height, or an unloaded chunk.

The ghost is visual-only: no collision shape, no physics body, no world write,
no chunk data write and no participation in `VoxelRay` or physics raycasts.

### Capture diagnostic

`--placement-capture=cube|slab|slab_top|stair|invalid` stages a deterministic
flat pad, a real aimed cell and a real loadout. It is capture-only and uses the
same live preview path. The `invalid` mode freezes the capture target because a
normal ray would hit the occupying block first; it is the only staged part of
that screenshot.

Commands used (Godot 4.7.2, 1280x720):

```text
godot --path godot -- --capture --placement-capture=cube \
  --capture-name=m40-place-cube.png --settle=10
godot --path godot -- --capture --placement-capture=slab \
  --capture-name=m40-place-slab.png --settle=10
godot --path godot -- --capture --placement-capture=slab_top \
  --capture-name=m40-place-slab-top.png --settle=10
godot --path godot -- --capture --placement-capture=stair \
  --capture-name=m40-place-stair.png --settle=10
godot --path godot -- --capture --placement-capture=invalid \
  --capture-name=m40-place-invalid.png --settle=10
```

## Verification

### Automated

- Unit: `M17_TESTS_PASS 3283 assertions` (M40 v2 baseline: 3092; 191 new).
- Integration: `M17_INTEGRATION_PASS 519 assertions` (baseline: 503; 16 new).
- Regression: `M17_REGRESSION_PASS assertions=52`.

New unit module `test_m40_placement_preview.gd` covers:

- cube placement on top of a block and against all four side faces, including
  exact ghost cell and final world cell;
- slab lower and upper half geometry from the real mesh bounds;
- all eight stair orientations, all eight slate stair orientations, all four
  ramp orientations and both ridge axes, with preview orientation compared to
  the orientation written by placement;
- occupied cells, cells inside the player, below-world cells and unloaded chunks;
- non-placeable items hiding the preview and changing the selected block
  changing the real ghost geometry;
- refusal of occupied/player-overlapping placement (world unchanged).

New integration section in `run_integration.gd` covers the real raycast, ghost
visibility, hiding while the inventory is open, a placement action being
swallowed by the UI input gate, food/non-placeable items hiding the ghost, item
changes and exact cell/orientation equality after `place_selected()`.

### Runtime captures

Rendered from the running game with no runtime errors or failed resource loads
in the final runs:

- `m40-place-cube.png` - green cube ghost above the targeted planks cell, amber
  surface patch, HUD "RMB place Stone".
- `m40-place-slab.png` - actual lower slab half geometry, HUD "bottom half".
- `m40-place-slab-top.png` - actual upper slab half under a ceiling, HUD
  "top half (upside down)".
- `m40-place-stair.png` - rotated stair ghost (+X), cyan forward face and 3D
  arrow, HUD "R rotate (+X)".
- `m40-place-invalid.png` - red ghost and red outline in an occupied cell, HUD
  "Cannot place Stone: space occupied".
- `m40-place-capture.json` - machine-readable capture summary from the final
  capture run.

The images are offscreen viewport captures written from inside the running game.
They are not desktop screenshots and were not produced from mockups.

## What was not verified

- No human mouse/keyboard play session was performed. The visual evidence is the
  offscreen running-game captures plus the real-scene integration test.
- No formal performance benchmark was run for the extra ghost draw calls. The
  ghost rebuilds only when the preview key changes; per-frame updates change
  material state and reuse the existing mesh.
- The existing R behaviour for stairs/ramps still cycles four horizontal
  facings; upside-down placement continues to come from targeting an underside.
- A slab's horizontal facing does not affect its geometry; its precise state is
  the selected half, which the HUD and geometry both show.
