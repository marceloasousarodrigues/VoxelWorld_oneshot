# M33 — Vegetation Distribution and Biome Ecology: Design Spec

**Date:** 2026-10-21
**Milestone:** M33
**Status:** Proposed — revised after independent spec review; independent re-review required before implementation.

## Scope guard

M33 is a targeted Godot world-generation and vegetation-placement change. It does not
redesign terrain, rendering, materials, structures, gameplay systems, or the Ursina
implementation. Terrain heights, surface materials, block IDs and biome classification stay
unchanged. The only new behaviour is where and what kind of vegetation is placed.

The work builds on the M32 tip (`e9120bb`) in a dedicated worktree
`C:/Users/Admin/Documents/Projects/VoxelWorld_m33`, branch `codex/m33-vegetation-ecology`.

## 1. Problem and evidence

The supplied current-game screenshot (`-7.3, 101.5, -29`, looking at the island mountain)
shows an almost continuous bright canopy covering a steep hillside and reaching the rocky
top. The same problem appears in the committed M32 captures (`m32-canopy.png`,
`m32-forest-clearing.png`, `m32-mountain-vista.png`).

A read-only probe (`m33_vegetation_probe.gd`, seed 17017, version 3, 2-block grid over
`[-256, 256]`) measured:

| Metric | Current v3 |
|---|---|
| Tree columns / all sampled columns | 2,130 / 66,049 = 3.22% |
| Tree columns on forest biome | 1,910 / 15,540 = 12.29% |
| Tree coverage, elevation `SEA+21..30` | 289 / 2,022 = 14.3% |
| Tree coverage, elevation `SEA+31..40` | 151 / 1,186 = 12.7% |
| Tree coverage, slope >= 3 | 364 / 5,804 = 6.3% |
| Tree coverage, slope <= 1 | 1,458 / 54,196 = 2.7% |
| Broadleaf trees above `SEA+30` | 127 |
| Any tree above `SEA+40` | 41 (all pine) |
| Broadleaf above `SEA+40` | 0 |
| Forest area designated as tree-free patch (`_forest_patches < -0.32`) | 2,839 / 15,540 = 18.3% |
| Trunk-free forest columns (candidate-grid effect) | 13,630 / 15,540 = 87.7% |
| Tree coverage inside river bank band | 64 / 26,929 = 0.24% |
| 32×32 local-cell trunk coverage | p10 0.0%, p50 0.8%, p90 10.6% |
| Window around `224,288` (the canopy capture) | 8.9% tree columns; steep coverage 12.3% |
| Window around `76,-40` (mountain foot) | 14.5% tree columns; steep coverage 20.1% |

The screenshot's “summit” is mostly a high hill (roughly `SEA+20..+40`), not only the
`MOUNTAIN` biome above `SEA+40`. That is why the existing `MOUNTAIN`/snow tree limits did not
prevent the visible summit trees.

### Root causes

1. **No elevation gate in the forest path.** `_forest_canopy_tree()` checks only river
   distance and forest-patch noise. Every v3 highland column is `FOREST` up to `SEA+40`, so
   flat lowland and steep upper slopes receive the same candidate density.
2. **Slope is sampled but not used as a density gate.** `_forest_canopy_tree()` calls
   `_column_slope()` only to lift broadleaf trunks by up to two blocks. It never suppresses
   trees on steep or rocky terrain; the v3 lift actually pushes crowns further over ridges.
3. **Broadleaf limit too high.** Broadleaf is allowed to the `MOUNTAIN` boundary
   (`SEA+40` ≈ 102). The probe found 127 broadleaf trees above `SEA+30`.
4. **Pine treeline too generous.** `MOUNTAIN` allows pines up to `SEA+46` at 9% column
   probability; 41 trees remain above `SEA+40`.
5. **Canopy overlap.** Dense candidate rates (0.98/0.78), a 2×2 candidate grid and 7–9 block
   crowns produce canopy closure even at 8–14% trunk coverage.
6. **Clearings are too rare and too simple.** One forest-patch threshold (`-0.32`) is the
   only opening rule; 18.3% of forest area is designated clearing. The candidate grid makes
   87.7% of forest columns trunk-free, so a trunk-free metric cannot measure visible
   openings. Crown overlap further erodes clearing edges.
7. **Loaded-save streaming uses the wrong generator.** `ChunkStreamer._start_generation_worker()`
   constructs `WorldGen.new(world.world_seed)` with the default `CURRENT_VERSION`. A loaded
   v0–v3 save can therefore stream new chunks with the current (v4) vegetation or terrain.
   This latent compatibility bug must be fixed before v4 can claim version safety.

## 2. Design decisions

### D1. New generator version 4

Add `M33_VERSION := 4` and `CURRENT_VERSION := 4`. All M33 behaviour is gated on
`terrain_version >= M33_VERSION`. Versions 0, 1, 2 and 3 keep byte-identical output and
pinned fingerprints. New worlds use v4; loaded saves keep their recorded version.

Terrain heights, surface materials and biome classification remain v3 behaviour. Only
vegetation placement and decor clearing rules change. A v4 world has the same landscape shape
as v3 with different plant cover.

Version pins after implementation:

- v0 `3214517825889907206`
- v1 `5947596836865492245`
- v2 `8397584315617538769`
- v3 `8802792587028581708` (measured at `e9120bb`)
- v4 `2164503133686526591` (measured after the M33 thresholds were final)

`test_m31_wilderness.gd`, `test_m32_landscape.gd` and `wilderness_probe.gd` version
assertions must use `CURRENT_VERSION` / `CURRENT_VERSION + 1` rather than hard-coded 4/5 where
they mean “current” and “future”.

### D2. Two-scale, spatially coherent density field

Keep `_forest_patches` and add a v4-only `_woodland` noise (`TYPE_SIMPLEX_SMOOTH`,
frequency `0.007`, 2 octaves, gain 0.55). Define:

```
vegetation_score(x,z) = 0.68 * forest_patches(x,z) + 0.32 * woodland(x,z) + 0.04
```

The small positive bias keeps real woodland/forest above the clearing threshold while still
leaving roughly a fifth of the forest open in the measured sample. This is still a local,
deterministic noise evaluation. The second field breaks the single threshold line into
irregular lobes so clearings do not become circular or grid-aligned. No global search or
per-frame vegetation work is introduced.

Density is expressed as **candidate probability** (one candidate per 2×2 cell, so expected
column coverage is roughly probability / 4):

```
base_density = smoothstep(-0.16, -0.06, vegetation_score)
density = base_density * elevation_factor * slope_factor
if vegetation_score < -0.16: density = 0
```

`elevation_factor` and `slope_factor` are multipliers in `[0,1]` on this candidate
probability. They are not column percentages.

### D3. Elevation and slope rules

Elevation is measured above `SEA_LEVEL = 62`:

| Band | Broadleaf factor | Pine factor | Expected column coverage intent |
|---|---|---|---|
| `<= SEA+18` (<=80) | 1.0 | 1.0 | dense lowland forest |
| `SEA+19..+24` (81–86) | 1.0 → 0.55 | 1.0 → 0.80 | forest thins, crowns smaller |
| `SEA+25..+27` (87–89) | 0.55 → 0.15 | 0.80 → 0.45 | broadleaf treeline |
| `SEA+28..+30` (90–92) | 0.15 → 0.0 | 0.45 → 0.25 | last broadleaf, pine only |
| `SEA+31..+40` (93–102) | 0.0 | 0.25 → 0.08 | grassy/rocky upper slope, isolated pines |
| `SEA+41..+44` (103–106) | 0.0 | 0.06 → 0.02 | sparse treeline |
| `> SEA+44` (>106) | 0.0 | 0.0 | snow/rock summit |

Hard broadleaf rejection is at `height > SEA+30`. A broadleaf tree is never returned above
that line. `SNOW` and `MOUNTAIN` do **not** use the forest base density or this factor table;
they use D4's explicit candidate cap.

Slope is the existing 4-neighbour maximum height delta:

| Slope | Broadleaf factor | Pine factor |
|---|---|---|
| 0–1 | 1.0 | 1.0 |
| 2 | 0.65 | 0.80 |
| 3 | 0.15 | 0.40 |
| >= 4 | 0.0 | 0.05 |

The v3 broadleaf slope lift is removed for v4. `_column_slope()` is called only after a column
has passed the candidate and river checks, so the cost is bounded to actual candidates.

Biome precedence:
- `SNOW` and `MOUNTAIN` do not use the forest base density or the elevation factor table.
  They use the explicit D4 per-column probability of `0.006`, falling to 0 at their elevation
  limit.
- `PLAINS` target 0.5–2% column coverage with clumped placement and the same elevation/slope
  filters.
- `SAVANNA` target 1–3% column coverage, oak/woodland only.
- `DESERT` cactus unchanged at low elevation.

### D4. Species rules

- Lowland forest (`<= SEA+18`): 62% oak, 16% birch, 17% pine, 5% blossom in dense groves;
  more birch/blossom in transition woodland.
- `SEA+19..+30`: broadleaf share fades; pine becomes dominant above `SEA+24`.
- `SEA+31..+40`: pine only.
- `> SEA+44`: no tree.
- Snow: pines only below `SEA+38`, slope <=2, explicit per-column probability `0.006`
  (0.6% column coverage); no trees above.
- Mountain: pines only below `SEA+44`, slope <=2, explicit per-column probability `0.006`;
  no trees on the snowy summit. This cap replaces the forest base density; it is not an
  additional multiplier.

### D5. Clearings and canopy openings

- Forest clearing: `vegetation_score < -0.16` → zero trees.
- Target: >=20% of forest area is designated clearing; surrounding forest retains >=6%
  trunk coverage in the defined lowland box.
- Add a **crown-footprint** test metric: for every tree whose crown disc intersects
  `LOWLAND_CANOPY_BOX` (including trees rooted just outside it), mark a 2D disc of its crown
  radius. Inside the box, compute the connected 4-neighbour components of columns outside
  every crown footprint. At least one open component must contain >=100 columns (roughly a
  10×10 clearing), and >=50% of designated clearing columns must be crown-free as a secondary
  check. This proves a real visible opening rather than a checkerboard of isolated gaps,
  without requiring a mathematically impossible open-sky fraction in dense lowland forest.
  This is a test metric, not runtime rendering.
- V4 removes the v3 slope height lift; crowns stay at normal trunk height.

### D6. River rules

- `river_distance < 1.25 * RIVER_BANK_LIMIT`: no trees (matches the M32 bank material band).
- `1.25..1.55 * RIVER_BANK_LIMIT`: candidate density × 0.25, slope <=1 only. This retains
  occasional riverside trees without closing the corridor.
- Beyond `1.55 * RIVER_BANK_LIMIT`: normal rules.
- Bank materials and water behaviour are unchanged.

### D7. Crown size

For v4 broadleaf:
- `<= SEA+18`: current v3 crown radius (3–4);
- `SEA+19..+24`: radius reduced by one;
- `SEA+25..+30`: radius 2;
- above `SEA+30`: no broadleaf.

Pine tier radii stay as v3; density and slope gates do the ecological work.

### D8. Decorations and clearings

`decoration_at()` uses the same `vegetation_score` clearing threshold for v4 so flowers and
tall grass appear in the same openings as the tree-free areas. No surface materials change;
“rocky upper slope” means existing slope-exposed stone plus sparse vegetation, not a new
material rule. Fallen logs and boulders keep their existing slope/flat checks.

### D9. Loaded-save streaming fix

Pass the world's generator version into the background generator:

```
_gen_worker_gen = WorldGen.new(world.world_seed, world.generator.terrain_version)
```

Add a test that creates a version-3 world, streams a chunk outside the initially loaded area
with threaded generation, and compares it with a synchronous v3 `ensure_chunk`. This proves
old saves keep old terrain/vegetation through streaming, not only through direct generation.

## 3. Compatibility and determinism

- v0, v1, v2 and v3 fingerprints remain pinned and byte-identical.
- v4 is a pure function of `(seed, x, z, generator_version)`.
- No mutable remembered state, global scan, or streaming-order dependency.
- Chunk-boundary tree pads stay at `M32_TREE_PAD = 8`; v4 crowns never exceed the pad.
- Save files record generator version 4 for new worlds; old saves keep their version.
- Block IDs, terrain heights, surface materials, water, player edits and M29 structures are
  untouched.
- v4 `height_at()` and `biome_at()` must equal v3 over a representative region; only
  `tree_at()` and decor decisions differ.

## 4. Tests

New `test_m33_vegetation.gd` with exact seeded regions and denominators. The global sample is
`[-192, 192]` at step 1 (148,225 columns) so candidate-grid parity is not biased. Minimum
sample size per class is 100 columns; cells are 32×32.

Fixed regions:
- `LOWLAND_BOX = Rect2i(200, 280, 48, 24)` — trunk density and species.
- `LOWLAND_CANOPY_BOX = Rect2i(192, 256, 64, 64)` — clearing/crown-footprint openness.
  Clearing columns in this box must number >=100.

1. **Determinism** — two v4 generators produce identical `tree_at` results and identical
   chunk fingerprints for a fixed region; two chunk load orders agree across a border.
2. **Historical pins** — v0/v1/v2/v3 hashes match the pins; v4 is distinct; v4 height and
   biome functions equal v3 over the sample.
3. **Broadleaf elevation limit** — global sample: zero broadleaf `tree_at` above `SEA+30`;
   broadleaf tree columns / all sampled columns in `SEA+27..30` <=2%, with N>=100.
4. **Summit sparsity** — all columns above `SEA+40` (N>=100): tree coverage <2%, broadleaf 0;
   all columns above `SEA+44`: zero trees.
5. **Lowland density** — `LOWLAND_BOX`: forest tree-column coverage >=6% and <=20%.
6. **Spatial variation** — global 32×32 cells: p10 <=2%, p50 <=6%, p90 >=8%, max >=12%;
   at least five cells <=1%, at least five cells >=8%, and at least three cells >=12%.
   At least ten cells are required.
7. **Steep terrain** — global forest columns below `SEA+30`, slope <=1 vs slope >=3, each
   N>=100: steep tree coverage <50% of flat coverage.
8. **Clearings** — global forest columns: `vegetation_score < -0.16` has zero trunks/trees
   (`tree_at == NONE`); clearing area >=20% of forest columns; in `LOWLAND_CANOPY_BOX`,
   >=100 clearing columns, a crown-free connected component of >=100 columns, and >=50% of
   clearing columns outside every crown footprint as a secondary check. Crowns rooted outside
   the box are included when their disc intersects it.
9. **River corridor** — core `<1.25 * RIVER_BANK_LIMIT`: tree coverage <1%; outer
   `1.25..1.55`: >0.5% and <20%; both N>=100.
10. **Chunk boundaries** — v4 chunks on both sides of the x=48 border have identical blocks
    in both generation orders; tree coordinates within eight blocks of the border are
    identical; a known crown crossing the border is complete in both orders.
11. **Species and biome composition** — `LOWLAND_BOX` contains oak/birch/pine/blossom; upper
    slope `SEA+30..40` contains pine only; no broadleaf above the limit; mountain/snow summit
    samples contain no trees above `SEA+44`.
12. **Save/version behaviour** — a v4 save records and restores generator 4; a v3 world
    streamed with threaded generation matches synchronous v3 generation (D9).
13. **Decorations** — v4 clearing columns have no trunk/tree (`tree_at == NONE`) and a
    decoration decision is present where the existing ground rules allow it. Leaves from
    adjacent crowns may overhang a clearing and are not treated as tree placement. Steep/rocky
    high ground has no high-elevation trees and no inappropriate flower carpet.

The v4 thresholds in tests 3, 5, 6, 8 and 9 must be confirmed with the extended v4 probe
before they are pinned. The probe gains a v4 mode that computes `vegetation_score`, effective
crown radius, crown footprints, and the exact step-1 samples. If a threshold cannot be met
without making the lowland forest unconvincingly empty, the threshold is adjusted with
measured margins rather than weakening the visual requirement.

Requirement-to-test matrix:

| M33 requirement | Tests |
|---|---|
| 1 determinism | 1, 10 |
| 2 historical pins | 2 |
| 3 broadleaf elevation | 3, 11 |
| 4 summit density | 4, 11 |
| 5 lowland density | 5 |
| 6 spatial variation | 6 |
| 7 steep terrain | 7 |
| 8 clearings | 8, 13 |
| 9 river corridors | 9 |
| 10 chunk boundaries/streaming | 10, 12 |

Existing tests must not be weakened. Affected tests:
- `test_m31_wilderness.gd`: current/future version assertions.
- `test_m32_landscape.gd`: `CURRENT_VERSION`, supported version 4, future version 5; add
  v3 pin (`8802792587028581708`) and keep v3-specific expectations explicit.
- `test_generation.gd`: v4 clearing rule uses `vegetation_score`; version 3 keeps
  `_forest_patches < -0.32` for historical behavior.
- `wilderness_probe.gd`: include version 4 in fingerprint/density loops.
- `m33_vegetation_probe.gd`: add a v4 mode for `vegetation_score`, crown footprints and the
  exact test samples; use it to derive the pinned thresholds.
- `run_tests.gd`: register the new module.
- streaming lifecycle: D9 version-3 streamed-vs-synchronous test.

## 5. Performance

Measure before and after with seed 17017, render radius 6, fixed time-of-day 0.28, no HUD,
same graphics settings, three runs each at:
- normal gameplay camera `-7.3,101.5,-29` yaw 270 pitch −12;
- river camera `80,92,180` yaw 0 pitch −25.

Report medians and ranges for average FPS, p95/p99 frame time, 1% low, worst sampled frame,
draw calls, generation total, mesh-build total, and loaded/wanted/queued/in-flight chunks.
Expect fewer tree faces/triangles and lower mesh cost; draw calls are per chunk and may not
change much. A >5% median FPS drop or >10% p99 increase must be investigated and explained
before completion.

## 6. Visual evidence

Capture v3 before and v4 after at the same seed, camera, render radius and graphics settings:

- normal gameplay view comparable to the supplied screenshot: `-7.3,101.5,-29`, yaw 270;
- lowland forest with clearings: `224,92,288`, yaw 75;
- forest/grassland transition: `80,72,160`, yaw 90;
- mountain upper slope and summit: `76,140,-40`, yaw 180;
- river corridor: `80,92,180`, yaw 0 and `80,72,160`, yaw 0.

Per-shot checklist:
- no broadleaf above `SEA+30`;
- no continuous canopy on the summit above `SEA+40`;
- at least one clear lowland opening and visible ground;
- readable river and banks with some riverside trees;
- no circular clearings, straight vegetation cutoffs, or repeated density bands.

The milestone does not pass if summit trees remain widespread, clearings are absent, or the
lowland forest becomes unconvincingly empty.

## 7. Risks and mitigations

- **Over-thinning:** lowland coverage and crown-footprint openness are measured; captures
  guard the visual result.
- **Hard clearing edges:** second woodland noise and visual checklist.
- **Slope cost:** slope sampled only for candidate trees.
- **Chunk seams:** pad and border-order tests.
- **Loaded-save streaming:** D9 fix and version-3 streamed test.
- **Test brittleness:** exact regions, minimum N, step 1, and thresholds with margin verified
  by the probe before pinning.

## 8. Out of scope

Far-field terrain, renderer changes, new tree assets/models, terrain or surface-material
redesign, structures, NPCs, gameplay systems, and Ursina/Python changes.
