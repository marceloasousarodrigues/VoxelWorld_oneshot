# M30 — Chunky Voxel Wilderness

## Status

**Partial — implementation and runtime evidence are complete, but save compatibility for pristine generated terrain is unresolved.** The new generator preserves deterministic output and player edit persistence tests pass. Existing saves do not store a generated-terrain version, so unedited areas regenerate with the M30 algorithm when loaded. A migration/versioning change belongs alongside the pending M29 edits to the shared save/world files and was deferred to avoid a conflict.

## Scope and ownership

- Active milestone: M30, as explicitly supplied by the user.
- Worktree: `C:/Users/Admin/Documents/Projects/VoxelWorld_m30`.
- Branch: `codex/m30-voxel-wilderness`, based on committed revision `92a9bdd`.
- Initial implementation commit: `fc1c81174985a9e466934aba4380a8d5ea03466b`; initial report commit: `62f6ab1`.
- M30 source changes are limited to `godot/scripts/core/world_gen.gd` and `godot/scripts/tests/test_generation.gd`.
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
- A fresh, independent read-only review found no blocking or important issues. It checked canopy and fallen-log chunk margins, negative-coordinate load-order coverage, and the available R6 performance sample.
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

- `godot/scripts/core/world_gen.gd`
- `godot/scripts/tests/test_generation.gd`
- `prototypes/m17/results/godot/m30-report.md`
- M30 before/after capture PNGs listed above, all under `prototypes/m17/results/godot/`.

## Commit record

- Independent read-only review found no source-scope or determinism-test issue. It flagged that the original report was a placeholder and asked for an explicit terrain compatibility qualification. This report now records the actual evidence and marks legacy pristine-terrain migration as deferred; this limitation remains a blocker to M30 completion.
- Implementation commit: `fc1c81174985a9e466934aba4380a8d5ea03466b`.
- Documentation commit: this report is committed separately; its final hash is reported in the task completion summary.

## M30 visual follow-up

The user requested another pass against the supplied reference, focusing on canopy variety and clearings, stronger landform composition, and the blank horizon. Work remains isolated to the M30 worktree and branch.

### Follow-up changes

- Added deterministic broadleaf crown profiles and based canopy shape, lean, and edge trimming on world coordinates. Trees crossing chunk boundaries now retain the same crown shape.
- Broadened forest openings, strengthened dense mixed groves, and added an explicit test for multiple tree species in dense patches.
- Sharpened mountain peaks and ridges, added a low-frequency valley cut, and increased mountain occurrence near the diagnostic seed/camera region. Added a sampled local-relief assertion.
- Updated integration fixtures to build an elevated test pad and position the creature target on the actual camera ray. Terrain is now taller around some old hardcoded test locations; without these fixture changes, the suite either collided with generated hills or could loop indefinitely after a missed creature hit.
- Updated the generation fingerprint test to mutate its block even when the chosen cell is already stone under the sharper terrain profile.

### Verification and horizon diagnosis

- Headless unit suite: **passed, 2,057 assertions** (`M17_TESTS_PASS 2057 assertions`).
- Integration suite: **passed, 438 assertions** (`M17_INTEGRATION_PASS 438 assertions`).
- Radius-6 runtime view at seed `17017`: all **791/791** requested chunks loaded; no queued, generating, or meshing jobs remained at settled capture. The view shows the nearer ridge and mixed canopy; an initial sample showed 60 FPS, while a later sample was 44.7 FPS, so this is not evidence of sustained 60 FPS.
- Radius-8 runtime capture shows the same generator and streamer working across a wider view, but the horizon remains mostly sky and ocean around the local landmass. The captured radius-8 run had **1,182 loaded/requested chunks** at vertical radius 6, 489,072 visible faces, and no remaining queued/in-flight jobs after settling. This points to the finite view radius and this seed/camera's coastline composition rather than a streaming backlog. These captures verify the tested view only; they do not establish that all camera positions or graphics configurations are free of visibility issues.
- Look-phase performance at radius 6, after streaming had settled: 3,764 frames, average 376 FPS with VSync off, p95 3.88 ms, p99 4.74 ms, and 0 queued chunks. During the initial settle phase, p95 was 9.04 ms and worst frame 78.17 ms. These are machine-specific harness readings, not a general performance guarantee.
- Captures: `m30-followup-horizon-r6.png`, `m30-followup-horizon.png`; performance report: `m30-followup-r6.json`.
- `git diff --check`: passed before the follow-up commits.

The follow-up improves local crown silhouettes, mixed groves, clearings, and mountain relief. The visual capture still falls short of the supplied wide fantasy panorama: radius 8 does not reveal a distant, continuous mountain range from the tested coast, and it contains no new fantasy landmark. The reference's broad horizon therefore remains a composition/visibility limitation, not a verified streamer failure. The terrain-version save compatibility limitation above also remains unresolved, so overall M30 status stays **Partial**.

### Follow-up commit record

- Implementation and test commit: `c34ab4d314acf9911151d571fb507c4b8301439e`.
- Report update for that follow-up: `a764311`.

## Visual quality pass — paired runtime comparison

This pass responds to the user's follow-up priorities: tree/canopy variety and natural openings, stronger local landform composition, and water/shoreline integration. It leaves M29 building systems, rendering architecture, save code, block IDs, and the Python/Ursina implementation untouched. The experimental higher-frequency mountain noise was discarded after a runtime capture showed a narrow spire rather than a better ridgeline.

### Changes

- Expanded broadleaf crown profiles from radii 2–3 to 2–4 and introduced deterministic, world-coordinate crown profiles for broadleaf and pine silhouettes so chunk seams do not change their shape.
- Increased mixed oak, birch, blossom, and pine distribution within forest patches; retained larger patch-scale openings; added flowering clearings and a tree-light strip along river channels.
- Added sparse, deterministic fallen logs on level forest ground using existing log block IDs.
- Added sand at low river banks and sandy subsurface there to make water edges read more clearly.
- Kept the previous lower mountain peak/ridge amplitudes and wider valley cuts. The tighter-frequency experiment was reverted after it did not improve the tested composition.
- Updated the integration movement fixture to use a level test pad under the steeper generated terrain, and added a fixed negative-coordinate chunk-seam test for fallen logs and generation order.

### Matched captures and visual result

The four before/after pairs below are actual Godot runtime captures from seed `17017`, render radius 6, and matching tour viewpoints. The before frames are from baseline `a764311`; the after frames use the final source settings for this pass. Captures use the game's 1280×720 Vulkan window.

| View | Baseline | Updated runtime | Observed change |
|---|---|---|---|
| Wide valley / river | `m30-visual-before-wide.png` | `m30-visual-after-wide.png` | Broader visible opening and more broken-up canopy; river banks read more distinctly. |
| Canopy | `m30-visual-before-canopy.png` | `m30-visual-after-canopy.png` | Crown sizes and silhouettes vary more, including lighter blossom/birch foliage; the close view is still crowded and heavily green. |
| Hills / cliffs | `m30-visual-before-hills.png` | `m30-visual-after-hills.png` | More exposed stepped terrain and less wall-like snow coverage in this matched view, but it still lacks the reference's layered distant peaks. |
| Natural clearing / coast | `m30-visual-before-clearing.png` | `m30-visual-after-clearing.png` | Clear open ground remains legible, with a sand/stone shoreline transition and varied surrounding trees. |

The pass improves local canopy variety, visible openings, forest-floor landmarks, and shoreline contrast. It is **not yet substantially matched to the full reference**: captures remain local island/ridge compositions, the canopy still reads as predominantly green at wide scale, and there is no broad, dramatic mountain-and-water vista or new memorable natural landmark. The user's priority was scene quality rather than distant continuity, so no horizon or world-boundary investigation was done in this pass.

### Verification and performance

- Godot 4.7.2 headless unit suite: **passed, 2,060 assertions** (`M17_TESTS_PASS 2060 assertions`).
- Godot integration suite: **passed, 438 assertions** (`M17_INTEGRATION_PASS 438 assertions`), including movement, saves/reloads, and the updated terrain-safe movement fixture.
- Runtime: the before/after views above were rendered by the running Godot game; these are not headless mesh previews.
- A fresh independent read-only review found no blocking or important issues with chunk margins, seam/load-order coverage, or generation cost.
- RTX 3080, seed `17017`, render radius 6, VSync off: the settled look phase recorded 3,850 frames, average 384.9 FPS, p95 3.453 ms, p99 4.422 ms, 191.9 FPS one-percent low, and near-zero queued chunks. Initial streaming had p95 8.302 ms and a worst sampled frame of 107.41 ms. These are harness measurements on one machine, not a hardware-independent guarantee. Raw frame telemetry is in `m30-visual-quality-r6.json`.
- `git diff --check`: passed before commit.

### Remaining limitations and status

- Runtime visuals are closer in the local features listed above, but the supplied reference is still materially richer and more expansive. More intentional large-scale ridge/valley composition and stronger forest-to-meadow transitions remain the highest visual opportunities.
- Save data still has no generator version. Unedited terrain in older saves can regenerate under the new terrain algorithm; existing player edits remain covered by the current integration flow. Resolve the compatibility policy with the M29-owned save/world work before claiming full milestone completion.
- Final status remains **Partial**, not complete. No broad performance regression was observed in this settled radius-6 look sample; streaming settle still has a high worst-frame spike.
