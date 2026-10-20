# M31 Voxel Wilderness Visual Transformation Implementation Plan

> **For agentic workers:** Executed inline (executing-plans). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the playable Godot world read closer to the M31 reference: dense, varied, stepped lime canopies; a winding river as a composition anchor; and a generator path that keeps version 0 and version 1 saves byte-identical.

**Architecture:** A new generator version 2 (`WorldGen.WILDERNESS_VERSION`) becomes the path for new worlds. Versions 0 and 1 keep their existing branches untouched; all new behaviour is gated by `terrain_version >= WILDERNESS_VERSION`. Forest canopy placement moves to a jittered 2x2 candidate grid (one candidate tree per 2x2 block of columns, 85-95% density) for denser, non-repeating spacing. Crowns gain per-layer shelf offsets and a larger tree pad so crowns never cross an unseen chunk boundary.

**Tech Stack:** Godot 4.7.2 (GDScript), headless `run_tests.gd` / `run_integration.gd`, windowed `--capture --shots` for runtime evidence.

**Spec:** Milestone text supplied in the M31 user request (Priority 1-5, Definition of done). Reference roles: Image 1 is the primary target; Image 2 is secondary inspiration; Image 3 is the baseline.

## Global Constraints

- Existing block IDs are unchanged; no new block types.
- Generator version 0 output and version 1 output must stay byte-identical (pinned fingerprints in `test_m31_wilderness.gd`).
- New worlds use generator version 2; loaded saves keep the version recorded in their file.
- Deterministic: all new behaviour is a pure function of seed and world coordinates.
- Tree crowns must stay within the generator's tree pad so chunk seams remain correct.
- No new dependencies, assets or shader rewrites in this pass.

## Review Focus

1. A tree whose crown crosses a chunk boundary must render the same from both chunks (pad must cover the widest crown).
2. A version 1 save must keep regenerating the M30 terrain, including its trees.
3. Clearings and river corridors must stay open of trees after the canopy change.
4. Denser canopy must not push face counts or streaming spikes past the measured baseline by an unacceptable margin.
5. Player edits on tree and river cells must still persist after reload.

## Tasks

### Task 1: Version scaffolding and pinned legacy output
- Files: `scripts/core/world_gen.gd`, `scripts/tests/test_m31_wilderness.gd` (new), `scripts/tests/run_tests.gd`, `scripts/tests/wilderness_probe.gd`
- Add `WILDERNESS_VERSION := 2`, make `CURRENT_VERSION` 2, accept 0/1/2 in `is_supported_version`.
- Pin fingerprints for versions 0 and 1 (seed 17017, chunks x/z -2..2, y 0..5) in the new test module.

### Task 2: Forest canopy candidate grid (version 2 only)
- Files: `scripts/core/world_gen.gd` (`tree_at`, new `_forest_canopy_tree`), tests in `test_m31_wilderness.gd`.
- One jittered candidate column per 2x2 cell; density from forest patch noise; clearings and river corridors stay empty; species mix by grove strength.

### Task 3: Stepped crowns and tree pad (version 2 only)
- Files: `scripts/core/world_gen.gd` (`_place_broadleaf`, `_place_pine`, `_tree_pad`).
- Per-layer shelf offsets for broadleaf crowns; `WILDERNESS_TREE_PAD` covers radius 4 + lean + shelf.
- Test: a tree straddling a chunk border produces identical voxels from both chunks.

### Task 4: Runtime evidence
- Matched before/after captures (seed 17017, render radius 6, `--fly`, HUD hidden), face-count and streaming metrics.

### Task 5: Verification and documentation
- Unit suite, integration suite, regression runner, two deterministic smoke runs, legacy fingerprints, M31 report.

## Deferred (documented, not implemented in this pass)

- Far-field distant mountain silhouettes (needs a coarse off-chunk heightfield mesh).
- Mountain-range frequency and snowy peak redistribution.
- Rendering artifact investigation beyond the captured evidence.
