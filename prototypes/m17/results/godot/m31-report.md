# M31 — Voxel Wilderness Visual Transformation

## Status

**PARTIAL.** The forest canopy and the mountain silhouettes improved in matched runtime captures, and the legacy-save and regression gates pass. The milestone is not met: the winding river is not a visible composition feature, there is no distant forest or snowy-range silhouette on the horizon, no rendering artifact was confirmed and fixed, and performance was sampled once rather than measured across the session.

## Preflight

- Original checkout: `C:/Users/Admin/Documents/Projects/VoxelWorld_oneshot`, branch `main`, HEAD `32a104d` (Restore M29 terrain generation for legacy saves). It was already dirty before this work (modified test file, many untracked evidence files). It was not modified.
- Confirmed in history: M29/M30 merge (`fae27be`), M29 architecture (`b3cf7f8`), legacy-save remediation (`32a104d`), and the M30 commits (`fc1c811` … `6581558`, branch `codex/m30-voxel-wilderness`, separate worktree `VoxelWorld_m30`, untouched).
- Work branch: `codex/m31-voxel-wilderness-visuals`, worktree `C:/Users/Admin/Documents/Projects/VoxelWorld_m31`, created from `main` HEAD `32a104d`.
- Godot 4.7.2 (mono build at `C:\Godot\...`), Vulkan, NVIDIA GeForce RTX 3080.
- Ursina/Python files were not touched.

## What changed

Generator version 2 (`WorldGen.WILDERNESS_VERSION`, now `CURRENT_VERSION`). New worlds use it. Versions 0 and 1 keep their output: every change is gated on `terrain_version >= 2`.

- **Forest canopy** (`_forest_canopy_tree`): one hashed candidate column per 2×2 block of forest columns, 85–95% fill, lower in transition patches. Clearings and river corridors stay tree-free. Species mix is oak/pine/birch with rare blossom (blossom was reduced after it read as pink speckle).
- **Crown shape**: per-layer shelf offsets (±1 block, world-coordinate hashed) for broadleaf crowns so they step out rather than forming a smooth dome.
- **Tree pad**: `WILDERNESS_TREE_PAD = 7` (was 5), covering radius-4 crown + lean 1 + shelf 1 = 6 blocks.
- **Mountains**: peak floor lowered and span shortened (`0.0 / 0.6` instead of `0.12 / 0.88`), so snow-height summits appear inside the streamed area.
- **River bed**: in version 2 the channel carve no longer requires the bed to start above `SEA_LEVEL + 1`, and the centre strength falls off over the full bank width. This was an attempt to make the channel reach below sea level so the existing source-water fill can flood it.
- **Version handling**: `is_supported_version` accepts 0..2. Saves record their generator version and reload on it (new test).

## Root causes found (Priority 5)

- **Sparse, gappy forest**: the original forest placement picked trees per column with a 0.5–0.9 roll, so the probe measured only 8.2% tree coverage on forest columns in version 1 and visible gaps in ground-level captures. The version 2 grid raises coverage to 13.7% (measured, see below).
- **Blossom speckle**: blossom crowns rendered as pink noise at distance. Reduced in version 2.
- **No inland water**: river beds in version 1 sit at heights 61–70 over the bank band, so only a few columns reach sea level (62). The river reads as a dry channel in captures. This is partly fixed for the generator (version 2 carves deeper), but not verified visually.
- **Pad/crown interaction**: none found. The shelf offset can push leaves ≤6 blocks, inside the pad of 7. The reviewer confirmed this by reading the code.

Not confirmed or fixed: thin dark vertical hairlines appear in the close-view capture `m31-after-2.png` (near x≈190 and x≈1100 px). I have not reproduced them, identified a cause, or tested a fix, so they are an open item.

## Measured results

Probe (headless, seed 17017, full resolution over x,z ∈ [−128, 127]):

| Metric | Version 1 (M30) | Version 2 (M31) |
|---|---|---|
| Forest columns | 15,588 | 14,386 |
| Tree coverage of forest columns | 8.2% | 13.7% |
| Tree columns on river corridors | 0 | 0 |
| Inland river-band columns (below sea level, min height) | min 61 | min 61 |

The river-band minimum of 61 applies to both versions, so the version 2 carve change did not measurably increase inland water in this sample. No quantified flooded-area figure is reported.

Mountains (probe, 8-block grid over x,z ∈ [−256, 256]): mountain + snow share rose from about 0.2% to about 3.6% of sampled columns; peaks at (72–80, 40) reach height 117 (snow line ~108).

## Runtime captures

Matched settings, both builds: seed `17017`, render radius `6`, `--fly`, `--hide-hud`, `--settle=25`, 1280×720, Vulkan on RTX 3080, frozen clock at 0.28. Shot list (yaw:pitch:x,y,z):
`75:-24:224,92,288 ; 38:-12:8.5,79,8.5 ; 0:-2:60.5,71,-30.5 ; 0:10:64.5,70,-36.5 ; 180:-14:76,140,-40`

Before = `main` `32a104d` (version 1). After = this branch (version 2). Files are in this folder as `m31-before-{0..5}.png` and `m31-after-{0..5}.png`.

- **Mountain (`-4`)** — strongest change. Before: a small green hill. After: a snow-capped, terraced peak with a second stepped ridge.
- **Wide elevated (`-0`)** — after shows a denser, stepped, lime-green forest with darker shaded faces. No river is visible in the frame. The reference's river-led composition is not achieved.
- **Ground forest (`-2`, `-3`) and spawn (`-1`)** — the two builds show different terrain at the same coordinates, because version 2 changes the terrain. These pairs are not content-matched and are not used as before/after evidence for the canopy.

The distant horizon remains empty ocean in both builds: no distant forest or mountain silhouette. This is the deferred far-field work below.

## Verification

Commands run from the worktree with `Godot_v4.7.2-stable_mono_win64.exe`:

| Suite | Command | Result |
|---|---|---|
| Unit | `--headless --path godot --script res://scripts/tests/run_tests.gd` | `M17_TESTS_PASS 2530 assertions`, exit 0 |
| Integration | `... run_integration.gd -- --straight-to-game` | `M17_INTEGRATION_PASS 463 assertions`, exit 0, stderr empty |
| Regression | `... regression.gd` | `M17_REGRESSION_PASS assertions=52`, exit 0, stderr empty |
| Smoke ×2 | `-- --straight-to-game --quit-after=30` | exit 0 both, `world_hash=9000566444367539267`, `edits=508`, `faces=176502`, stderr empty, hashes identical |

Legacy compatibility (`test_m31_wilderness.gd`):
- Version 0 region fingerprint pinned to `3214517825889907206` and passing (M29 output unchanged).
- Version 1 region fingerprint pinned to `5947596836865492245` and passing (M30 output unchanged).
- A version-1 save records version 1 and restores the M30 generator.
- Existing persistence tests for version-less legacy saves pass.

Test changes that were made deliberately (disclosed):
- Three fixtures that assert on the M30 tree layout now construct `VoxelWorld.new(17017, 1)`: `test_npcs.gd::_test_plot`, `test_m26_protection.gd` (pristine-clearing save), `test_m29_architecture.gd` (keep finial). Assertions unchanged.
- `run_integration.gd` chunk-boundary walk: a terrain-coupled failure (`dx=0.16`) was fixed by teleporting to a level pad at the walk start. The assertion itself is unchanged.
- Seam test: a crown crossing the x=48 border is asserted with a leaf count, and both chunk orders must match.

## Performance (single settle-phase sample each, not a benchmark)

Matched tour, same seed and settings. Settled streaming totals:

| Metric | Before (v1) | After (v2) |
|---|---|---|
| Loaded/wanted chunks | 904 | 791 |
| Visible faces | 399,048 | 397,816 |
| Generation total | 2,528 ms | 1,937 ms |
| Mesh total | 15,958 ms | 12,814 ms |
| Attach total | 9,204 ms | 8,417 ms |
| Worst single mesh | 72.7 ms | 74.7 ms |
| Draw calls at final frame | 264 | 403 |
| Primitives at final frame | 271,002 | 432,092 |

The draw-call and primitive rise at the final frame is real but is not a like-for-like frame comparison (the final view shows different terrain). Frame-time percentiles, FPS over time, and loaded/queued counts during a walk were **not** measured in this pass. The milestone's performance requirement is therefore **not verified**.

## Remaining limitations and deferred work

1. **River (Priority 2) not delivered.** No capture shows a continuous, visible inland river. The generator deepens channels in version 2, but the amount of inland water is not established. A future pass needs a flooded-channel probe, a camera placed on a verified channel, and a river-led composition check.
2. **Distant scenery (Priority 4) not delivered.** The horizon is empty ocean. Distant forest and snowy-range silhouettes need a coarse off-chunk heightfield or a streamed far-ring; neither exists in this codebase.
3. **Rendering artifacts (Priority 5) not confirmed.** Possible vertical hairlines in `m31-after-2.png` are unexplained. Texture shimmer, mipmap, and alpha-edge behaviour were not examined in runtime captures.
4. **Terrain composition (Priority 3) partly done.** Mountains are stepped and snow-capped; the ground-level forest is denser. Riverbank and clearing transitions were not revisited.
5. **Performance (required) not verified** beyond the single sample above.
6. **Reviewer.** An independent reviewer (read-only) returned **PASS** on the code change as a correctness review: no blocking defects, versions 0/1 unchanged by inspection, tree pad sufficient, carve seam-safe. It did not run the suites and did not review the visual definition of done. Its non-blocking findings were addressed or are listed here: the seam test was weak (fixed), the plan's grid size was stale (fixed), and a river comment overclaimed (fixed). The reviewer noted a pre-existing chunk-layer early-exit (`generate_chunk`, `base_y > max_height + 14`) that could theoretically skip crown layers; not reproduced, not changed.

## Files

- `godot/scripts/core/world_gen.gd` (generator version 2)
- `godot/scripts/tests/test_m31_wilderness.gd` (new)
- `godot/scripts/tests/wilderness_probe.gd` (new diagnostic tool, not in the suite)
- `godot/scripts/tests/run_tests.gd`, `run_integration.gd`, `test_npcs.gd`, `test_m26_protection.gd`, `test_m29_architecture.gd`
- `docs/superpowers/plans/2026-10-20-m31-wilderness-visuals.md`
- `prototypes/m17/results/godot/m31-{before,after}-{0..5}.png`, this report

Generated `.import` and `.uid` files produced by the Godot import pass are not part of this commit.
