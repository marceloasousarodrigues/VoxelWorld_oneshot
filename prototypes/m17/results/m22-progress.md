# M22 — Progress and evidence

Art/behaviour contract: `m22-visual-design.md`.

Status: **complete in the Godot project** (2026-10-19). The production Ursina
implementation was not modified.

## 1. Repository state at start

- Branch `main`, ahead of `origin/main`.
- Pre-existing uncommitted work preserved untouched:
  - `prototypes/m17/results/godot/game-capture.json` (modified)
  - `tests/test_m16_streaming_budget.py` (modified)
  - many untracked captures, `.verify_tmp*`, `.superpowers/`, `.opencode/` files.
- Godot `4.7.2.stable.mono.official.ed1daf0bf`.
- Existing M17/M18/M19/M20/M21 implementation inspected. The native Godot
  chunk renderer is retained; M22 extends it instead of replacing it.

## 2. Baseline (before M22 implementation)

Date: 2026-10-19. Seed 17017, radius 4, 1280×720, vsync off.

### Automated suites

| Suite | Command | Result |
| --- | --- | --- |
| Unit | `godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd` | **1693 assertions, exit 0** |
| Integration | `… --script res://scripts/tests/run_integration.gd -- --straight-to-game` | **391 assertions, exit 0** |
| Headless smoke | `… -- --straight-to-game --quit-after=14` | exit 0, `world_hash=7995773462820745781`, 392 chunks, 170492 faces, `faces_hash=6834793821708419232` |

Logs: `.verify_tmp/m22-baseline-unit.txt`, `m22-baseline-integration.txt`,
`m22-baseline-smoke.txt`.

### Performance baseline

| Scenario | p50 ms | p95 ms | p99 ms | worst ms | 1 % low fps | avg draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| settle | 1.586 | 5.899 | 11.463 | 70.72 | 50.6 | 332.3 |
| look | 1.563 | 3.504 | 6.665 | 79.835 | 87.6 | 487.6 |
| walk | 1.561 | 5.113 | 8.720 | 72.902 | 72.3 | 296.5 |

Reports: `results/godot/m22-before-settle.json`, `m22-before-look.json`,
`m22-before-walk.json`.

### Baseline captures inspected

- `results/godot/m22-baseline-normal-noon.png`
- `results/godot/m22-baseline-close-noon.png`
- `results/godot/m22-baseline-wide-noon.png`

Observed defects (pre-M22):

1. **Vegetation is one repeated green mass.** Oak/pine crowns read as uniform
   green cubes; no flowers, bushes or birch/blossom variety. The wide view is
   almost entirely foliage with little sky and no colour accents.
2. **The showcase has no architecture.** Only a plaza, table, furnace, brick
   pillar and material pads; no building, roof, fence, bridge or inhabited
   settlement detail.
3. **Ground material scale/repetition.** The stone-brick plaza uses one 1 m
   texture repeatedly and dominates the close view; there is no path or edge
   treatment that integrates it with the terrain.
4. **Washed-out distance.** The wide capture's sky/horizon is white and the
   middle distance loses colour; fog is too strong for the intended bright,
   colourful look.
5. **Flat canopy lighting.** Dense crowns block most sky, and the remaining
   ground is lit evenly; settlement lighting does not exist.
6. Pre-existing, not fixed by baseline: no live rotating-camera video evidence;
   no human keyboard/mouse play-through.

## 3. Implemented

### Materials and palette

- `tools/generate_m22_textures.py` generates **20 procedural textures** (no new
  third-party art): birch bark/leaves, blossom leaves, bush, three flowers,
  timber frame, roof tile/ridge/eave, packed path top/side, lantern side/top,
  fence rails, barrel side/top and a plank door. They are packed into the same
  `Texture2DArray` and recorded in `assets/texture_sources.json`.
- `BlockDB` ids 73–87 add the M22 vocabulary (the 67–72 M21 item range is left
  undefined, so existing saves and item ids are unchanged). New helpers:
  `is_custom_model`, `is_flower`.
- `ItemDB.COUNT` now tracks `BlockDB.COUNT`; mining classes add birch/fence/
  barrel/door to the axe family, path to shovel, roof tiles to pickaxe.
- Stronger grass-side grading and a low-frequency 24-block macro tint in the
  mesher break up the old one-note green while keeping grass sides neutral.
- `Crafting` gains recipes for birch planks, timber frame, packed path, fence,
  door, barrel, lantern and fired roof tiles, so the building set is playable.

### Terrain and vegetation

- Steep columns now expose rock/dirt instead of a green carpet: slope ≥ 4 →
  stone, slope ≥ 2 on grass/dry grass → dirt. This removes the harsh grass-side
  striping on hills and adds the layered rocky silhouette.
- Tree library expanded with **birch** (tall pale trunk, light crown) and a rare
  **blossom** tree in temperate biomes, alongside oak/pine. Shared
  `_place_broadleaf` shape function and deterministic per-column placement.
- Forest/plains/savanna decoration now includes three flower colours and
  bushes; flowers use three crossed planes and bushes four. Flowers keep their
  own hue instead of a green biome multiply.
- Breaking the block under a flower/tuft/bush/lantern clears the decoration in
  `VoxelWorld.set_block`, so harvesting never leaves floating plants.

### Medieval architecture

- `StructureDB` gains **Timber Cottage** (9×7, 9 layers): cobble foundation,
  stone-brick floor, timber-framed walls with glass windows, two-block door,
  stepped tiled hip roof with overhanging eaves and ridge, stone chimney, and a
  furnished interior (crafting table, furnace, chest, barrel, hanging lantern).
- **Market Stall** (5×3): packed-path apron, log posts, timber counter, barrel,
  crafting table and a tiled roof with ridge cap.
- Both are ordinary `StructureDB` ASCII definitions, validated and placed by
  normal deterministic world generation. `StructureDB.stamp()` lets the
  showcase write the same definition at a fixed anchor.
- Custom one-cell models: barrel, lantern and neighbour-aware fence. Lantern
  panes carry the emissive flag; fence posts use log texture and rails use the
  fence texture, so a single post no longer reads as stacked boards.
- Lantern light manager (`game/lantern_lights.gd`): registers lanterns from
  chunk creation/removal/edits, keeps at most 12 `OmniLight3D`s near the player,
  fades them out in daylight and removes a chunk's lanterns on unload (no node
  per lantern, no leaked lights).

### Showcase

`VisualTestArena` is now a 31×31 playable clearing at the existing deterministic
site (72, 65, −88). It contains:

- a winding two-wide packed path from the south gate to the cottage door, with
  cobble/gravel accents and a stone-brick apron,
- the timber cottage and market stall,
- an outdoor work area (furnace, chest, barrels, crafting table, cobble apron),
- a pond and a south-running stream crossed by a plank bridge with log supports
  and fence rails,
- a fence line with a gate and two gate lanterns, plus path lantern posts,
- oak, pine, birch and blossom trees, flower beds, bushes, ferns, fallen logs,
  worn-earth patches and ore-bearing boulders.

It remains behind `--visual-test` and is isolated from autosave, creatures,
NPCs and raids.  All three save paths are guarded: autosave already skipped the
showcase, and `_save_now`, `_save_silently` and the window-close request now
also refuse to write while `visual_test` is set, so the test-only placement can
never leak into a normal save.

### Lighting and atmosphere

- Brighter, more saturated blue sky; lighter blue horizon/ground-sky and weaker
  cloud cover remove the baseline white horizon band.
- Softer fog (`0.0009` default), less sky affect/aerial perspective.
- Subtle glow pass for emissive lantern panes (`glow_enabled`, intensity 0.55).
- Warm lantern pools at dusk/night; night remains navigable and the sky keeps
  stars and a readable gradient.

## 4. Changed files

Core:

- `scripts/core/block_db.gd`, `chunk_mesher.gd`, `world_gen.gd`, `voxel_world.gd`,
  `item_db.gd`, `texture_library.gd`, `day_night.gd`, `crafting.gd`,
  `structure_db.gd`, `npc.gd` (woodcutter accepts birch logs).
- `scripts/game/game.gd` (lantern manager, sky/fog/glow, new fixed views),
  `visual_test_arena.gd`, new `lantern_lights.gd`.
- `shaders/sky.gdshader`.

Assets/tools:

- `tools/generate_m22_textures.py`, `assets/texture_sources.json`, 20
  `assets/textures/m22_*.png`.

Tests:

- `test_block_db`, `test_mesher`, `test_generation`, `test_textures`,
  `test_visuals`, `test_structures`, `test_crafting`, `test_items`,
  `test_npcs`, `test_edits`, `test_persistence`, `run_integration`.

Evidence:

- `results/godot/m22-*.png`, `m22-before-*.json`, `m22-after-*.json`.

## 5. Verification (after implementation)

### Automated suites

| Suite | Result |
| --- | --- |
| Unit | **1767 assertions, exit 0** |
| Integration | **402 assertions, exit 0** |
| Headless smoke ×2 | exit 0, deterministic `world_hash=7821043820538758500`, 392 chunks, **174353 faces**, `faces_hash=665917304729475893` |

The world hash changed by design: tree species, decoration density, steep-slope
surface materials and the new structure catalogue all change generated content.
The two smoke runs agree exactly; background/threaded generation equivalence is
still pinned by `test_determinism.gd`. Baseline was `7995773462820745781` with
170492 faces.

### Performance after (same seed, radius 4, vsync off)

| Scenario | p50 ms | p95 ms | p99 ms | worst ms | 1 % low fps | avg draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| settle | 1.519 | 5.298 | 10.637 | 88.213 | 53.6 | 329.9 |
| look | 1.505 | 3.403 | 6.482 | 80.626 | 89.4 | 483.1 |
| walk | 1.455 | 4.859 | 8.500 | 70.674 | 75.7 | 286.2 |
| cross (additional) | 1.400 | 2.166 | 5.812 | 24.102 | 118.2 | 292.6 |

Reports: `m22-after-{settle,look,walk,cross}.json`. The M22 scene adds 2.3 %
more emitted faces and roughly the same draw calls; p50/p95/p99 are at or below
the baseline in all three comparable scenarios. The settle worst frame is
higher by one 17 ms outlier (88 vs 71 ms), still far below a multi-frame stall
and within run-to-run variation. The cross phase is a single after run (no M22
before run); it is reported as a compatibility check, not a before/after delta.

### Captures inspected

All paths are under `prototypes/m17/results/godot/`:

1. `m22-wide-noon.png` — east 3/4 view of the clearing, cottage, path, forest
   and sky (`--visual-test=wide --render-distance=5`).
2. `m22-normal-noon.png` — approach path, gate, lanterns, cottage and stall.
3. `m22-close-noon.png` — path/grass/flower/cottage material close-up.
4. `m22-cottage-noon.png` — full facade, timber frame, windows, door, chimney
   and tiled roof.
5. `m22-garden-noon.png` — flower bed, path, lantern post, cottage and blossom
   tree.
6. `m22-bridge-noon.png` — bridge deck, water, rails and the work area.
7. `m22-dusk.png` — time 0.50, warm horizon, lantern pools and windows.
8. `m22-night.png` — time 0.75, readable night silhouettes and stars.
9. `m22-tour-0.png` … `m22-tour-3.png` — a four-position scripted camera tour
   across the clearing.

Inspection results:

- No texture swimming, atlas bleed or face inversion was observed in the
  day/dusk/night captures or the tour.
- Grass sides, path edges, cottage foundation and roof eaves read as distinct
  materials; no z-fighting or seams were observed on the cottage, bridge or
  stations.
- Flowers, bushes and trees have readable silhouettes and colour; the birch and
  blossom species are visibly distinct from oak/pine.
- Lanterns produce warm local pools at dusk/night; no light leaks through
  unloaded chunks; the pool stays bounded.
- The bridge/water and the work area are visible but the market-stall roof
  crowds the bridge view from the south. The east bridge view was used instead.
- A distant background tree canopy block can appear as a lone green cube above
  the roofline in some eye-level frames. It belongs to a tree outside the
  clearing (the clearing air is cleared to 30 blocks); it is not a showcase
  prop, but a future canopy-distance treatment would remove the visual.
- The roof is a stepped voxel hip roof, not a smooth slope. It has overhanging
  eaves, a ridge, a chimney and contrasting tile/eave faces; a stairs/slab roof
  vocabulary is the highest-value next architectural step.

## 6. Procedural integration

The materials, tree/decor rules, flower/bush placement, slope surfaces,
crafting recipes and both building definitions are part of normal generation
and gameplay, not showcase-only:

- `test_structures` finds `timber_cottage` and `market_stall` in the normal
  deterministic structure scan.
- `test_generation` finds wildflowers and all four tree leaf types in normal
  chunks.
- `test_persistence` round-trips a `TIMBER_FRAME` edit through the save file.
- `run_integration` drives the real lantern manager: add/remove a lantern,
  reject a chunk unload leak, bound the light pool, and asserts a manual save is
  refused while the showcase mode is active.
- The showcase calls `StructureDB.stamp` on the same definitions the generator
  uses.

Not integrated: a settlement **layout/path network** across the procedural
world, village-scale building clusters, opening doors, window emission tied to
the clock, and a stairs/slab roof set. These are listed as follow-up work.

## 7. Commits and preservation

- Baseline/spec savepoint: `c154f19 M22: record the visual contract and verified baseline`
- Implementation savepoint: `8411e30 M22: add stylized materials, vegetation and medieval architecture`
- Evidence/documentation savepoint: the commit containing this document (see
  `git log -1 --format=%h` for the exact hash).
- `tests/test_m16_streaming_budget.py` was already modified before M22 and was
  **not** touched.
- Running the capture harness overwrote the generated
  `results/godot/game-capture.json` (it was already modified before M22). It is
  intentionally **not committed**; the pre-existing diff cannot be reconstructed
  from Git because it was uncommitted. No source or user-authored asset was
  affected.

## 8. Reproduction commands

```powershell
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=14

& $godot --path prototypes/m17/godot -- --capture --capture-name=m22-wide-noon.png --visual-test=wide --time=0.28 --hide-hud --settle=10 --render-distance=5
& $godot --path prototypes/m17/godot -- --capture --capture-name=m22-dusk.png --visual-test=dusk --time=0.50 --hide-hud --settle=10
& $godot --path prototypes/m17/godot -- --capture --capture-name=m22-night.png --visual-test=dusk --time=0.75 --hide-hud --settle=10

& $godot --path prototypes/m17/godot --script res://scripts/tests/run_perf.gd -- --straight-to-game --seed=17017 --scenario=look --label=m22-after-look
```

Regenerate the textures with:

```powershell
python prototypes/m17/godot/tools/generate_m22_textures.py
```

## 9. Limitations / next highest-value work

1. Roof silhouette: add roof stairs/slabs (four orientations or a small set of
   shapes) and rebuild the cottage roof as a smoother gable.
2. Procedural villages: cluster cottages/stalls with a path network and
   settlement lighting, rather than isolated definitions per 96-block region.
3. Window emission tied to the day/night clock and interior visibility.
4. A distant-canopy treatment (fade or remove isolated canopy tops) for
   high-vantage captures.
5. No human keyboard/mouse play-through; movement was inspected through the
   scripted four-frame tour and automated integration, not a live session.
6. `game-capture.json` evidence overwrite noted above; the rest of the
   pre-existing working tree is untouched.
