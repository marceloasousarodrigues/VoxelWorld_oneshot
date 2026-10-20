# M30 — Chunky Voxel Wilderness

## Status

**Partial — implementation and runtime evidence are complete, but save compatibility for pristine generated terrain is unresolved.** The new generator preserves deterministic output and player edit persistence tests pass. Existing saves do not store a generated-terrain version, so unedited areas regenerate with the M30 algorithm when loaded. A migration/versioning change belongs alongside the pending M29 edits to the shared save/world files and was deferred to avoid a conflict.

## Scope and ownership

- Active milestone: M30, as explicitly supplied by the user.
- Worktree: `C:/Users/Admin/Documents/Projects/VoxelWorld_m30`.
- Branch: `codex/m30-voxel-wilderness`, based on committed revision `92a9bdd`.
- Implementation commit: to be recorded after commit; documentation commit follows separately.
- M30 source changes are limited to `prototypes/m17/godot/scripts/core/world_gen.gd` and `prototypes/m17/godot/scripts/tests/test_generation.gd`.
- M29-pending changes are in a separate original checkout. M30 did not change the mesher, block definitions, texture manifest, rendering, game, or save manager.

## Plan

1. Add deterministic stepped highlands, sharper mountain ridges, and winding lowland river beds using the existing world generation and source-water systems.
2. Create spatially varied forest patches with open clearing bands and denser groves using the existing tree species and block IDs.
3. Cover generation order, negative chunk borders, terrain profiles, source water, clearings, and grove density with focused tests.
4. Run unit and integration suites; compare matched runtime captures and streaming/mesh reports against the committed baseline.
5. Capture and inspect representative gameplay views and record performance, scope, and compatibility limits.

Ground-detail block additions and rendering/fog changes were not justified for this isolated M30 change: the existing project already supplies ground decorations and water rendering, while the shared rendering and block systems overlap M29 ownership.

## Implementation

- Highland surfaces at least eight blocks above sea level snap to three-block height bands; lowland surfaces remain unquantized for gentler building areas.
- Mountain ranges gain narrow ridges for a more distinct skyline.
- A deterministic low-frequency contour carves tapered channels into suitable inland heights. Existing world generation fills the below-sea columns with source water up to sea level; no water simulation or save code was changed.
- Forest biome tree placement now varies by a broad seed-based noise field. Strongly negative patches remain open, transitional patches are sparse, and positive patches contain denser mixed groves.
- No new block IDs, assets, dependencies, or M29 building features were added.

## Automated verification

- Godot 4.7.2 stable on Windows, headless unit suite: **passed, 2,055 assertions** (`M17_TESTS_PASS 2055 assertions`).
- Godot integration suite, invoked with `-- --straight-to-game`: **passed, 438 assertions** (`M17_INTEGRATION_PASS 438 assertions`). This includes real scene startup and existing save/reload coverage.
- Generation tests compare positive and negative-coordinate chunks generated in different load orders and sample a `641×641` coordinate region at four-block intervals for terraces, peaks, level build sites, and carved rivers.
- The new river probe is generated as a water source at sea level. Forest patch tests verify broad open areas and populated dense areas.
- `git diff --check`: passed before commit.
- No separate human keyboard-and-mouse play-through was performed.

## Runtime and visual evidence

Captures are real 1280×720 gameplay windows using Godot 4.7.2, Vulkan, and an NVIDIA GeForce RTX 3080. The paired captures use seed `17017` and matching camera coordinates, yaw, pitch, render radius, and daytime settings within each pair.

| View | Baseline | M30 | What it demonstrates |
|---|---|---|---|
| Inland forest | `m30-before-inland.png` | `m30-after-inland.png` | The formerly continuous canopy is divided by a broad clearing/ravine; the M30 view has visibly stepped sides. |
| Forest river | `m30-before-forest-river.png` | `m30-after-forest-river.png` | A visible waterfall and stream in a wooded gorge. |
| Mountain slope | `m30-before-mountain.png` | `m30-after-mountain.png` | Stronger three-block terraces and exposed grass/dirt/stone bands. |
| River meadow | `m30-before-river-meadow.png` | `m30-after-river-meadow.png` | A broad carved channel through open terrain; the water surface is partly hidden by snow and vegetation in this view. |

All files are in `prototypes/m17/results/godot/`. Additional exploratory views include `m30-after-mountain-vista.png`, `m30-after-river-aerial.png`, `m30-after-river-approach.png`, `m30-after-river.png`, `m30-before-spawn.png`, `m30-before-wide.png`, and `m30-before-0.png` through `m30-before-2.png`.

The captures directly verify the woodland opening, stepped slopes, and one waterfall. They do **not** show the full breadth of the supplied reference: no new fantasy landmarks, bridges, islands, snow system, or ground-detail set was added. Existing landscape structures remain available from prior project functionality. The selected river-meadow capture is not strong visual proof of a shoreline because water is occluded there; the forest-gorge capture is the visible water-feature evidence.

## Performance comparison

Matched inland settled-stream reports (343 loaded/wanted chunks each):

| Metric | Baseline | M30 | Change |
|---|---:|---:|---:|
| Visible faces | 201,421 | 174,756 | −13.2% |
| Aggregate mesh work | 5,670.6 ms | 5,181.4 ms | −8.6% |
| Aggregate attachment work | 3,666.9 ms | 3,595.0 ms | −2.0% |
| Aggregate generation work | — | 896.2 ms | Startup/settle total |
| Worst mesh build | 63.5 ms | 53.0 ms | −16.5% |
| Sampled FPS after settling | — | 60 | Single runtime sample |

Mesh, attachment, and generation durations are startup/settling aggregates, not average frame-time benchmarks. These captures show no regression in the matched sample; they do not establish performance across long sessions, different hardware, or larger render radii.

## Compatibility, risks, and deferred work

- Deterministic generation and chunk-order behavior are covered by automated tests, including chunks at negative coordinates crossing both horizontal borders.
- The integration suite's save/reload coverage confirms existing player-edit persistence still works for the exercised current-version flow. This does not preserve pristine generated terrain across generator versions: save data has no terrain algorithm version, and untouched areas will now be regenerated using M30. Version migration was deferred because M29 currently owns uncommitted edits to `save_manager.gd` and `voxel_world.gd` in the original checkout.
- M30 changed terrain generation, so this save limitation prevents marking the milestone complete under its preservation requirement. Integrate a terrain-version policy with the M29 save/world changes before declaring M30 complete for existing saves.
- The reference asks for more environmental breadth than this pass implements. This change focuses on the largest verified improvements—landform silhouette, rivers, clearings, and forest density—without introducing new block types or rendering architecture.

## Changed files

- `prototypes/m17/godot/scripts/core/world_gen.gd`
- `prototypes/m17/godot/scripts/tests/test_generation.gd`
- `prototypes/m17/results/godot/m30-report.md`
- M30 before/after capture PNGs listed above, all under `prototypes/m17/results/godot/`.

## Commit record

- Independent read-only review found no source-scope or determinism-test issue. It flagged that the original report was a placeholder and asked for an explicit terrain compatibility qualification. This report now records the actual evidence and marks legacy pristine-terrain migration as deferred; this limitation remains a blocker to M30 completion.
- Implementation commit: `fc1c81174985a9e466934aba4380a8d5ea03466b`.
- Documentation commit: this report is committed separately; its final hash is reported in the task completion summary.
