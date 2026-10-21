# M34 — Canopy Shape and Forest Composition: Design Spec

**Date:** 2026-10-21
**Milestone:** M34
**Status:** Proposed — revised after independent spec review; independent re-review required before implementation.
**Base:** M33 tip `c0b58c3` (`codex/m33-vegetation-ecology`)
**Worktree / branch:** `C:/Users/Admin/Documents/Projects/VoxelWorld_m34` / `codex/m34-canopy-composition`

## Scope guard

M34 is a targeted Godot tree-placement and tree-crown change. It does not redesign terrain,
the river, biomes, surface materials, rendering, structures, gameplay, or the Ursina
implementation. Terrain heights, river carving, snow-cap geometry, block IDs and biome
classification stay unchanged. Only where trees are placed and how their crowns are shaped
changes, plus the generator-version plumbing needed to keep old saves intact.

The work builds on the approved M33 work, not on `main`. `main` is at `32a104d`; the M33
tip is `c0b58c3` and is the base commit for this milestone.

## 1. Problem and evidence

M33 replaced the elevation-blind v3 canopy with a v4 ecology. It fixed the mountain and
river problems, but its own report records the remaining limitation: from an elevated
viewpoint, `m33-final-4.png` still shows a nearly continuous green block surface with
narrow gaps, not recognisable individual crowns. `m33-final-3.png` shows the same effect
at normal gameplay distance: a dense forest mass whose crowns merge into a single
silhouette.

A read-only diagnostic (`m34_canopy_probe.gd`, seed 17017, v4) measured the cause in the
`LOWLAND_CANOPY_BOX = Rect2i(192, 256, 64, 64)`:

| Metric | v4 |
|---|---|
| Forest columns in the box | 3,552 |
| Trees in/intersecting the box | 337 |
| Forest tree-column coverage | 9.49% |
| Median nearest-trunk distance | **1.41 blocks** |
| p25 / p75 nearest-trunk distance | 1.00 / 2.00 blocks |
| Crown-covered forest columns | 66.0% |
| Forest columns covered by 2+ crowns | **61.6%** |
| Forest columns covered by 3+ crowns | **57.6%** |
| Forest columns covered by exactly one crown | 4.4% |
| Open (crown-free) forest columns | 34.0% |
| Actual voxel top surface that is leaf | 58.5% |
| Broadleaf crown radii present | 4, 5, 6 (actual reach) |
| 32×32 global cells (all columns): p50 / p90 / max | 0.39% / 8.11% / 21.4% |

The same sample shows the forest is not globally sparse: lowland tree coverage is 11.03%,
and the v4 canopy box contains a 564-column connected crown-free opening. The problem is
therefore **not** a missing clearing rule and **not** a rendering bug.

### Root causes

1. **The 2×2 candidate grid allows near-adjacent trunks.** `CANOPY_CELL = 2` places one
   candidate per 2×2 cell, but candidate jitter is `0..1` in both axes. Two adjacent cells
   can therefore place trunks one block apart. The measured median nearest-trunk distance
   is 1.41 blocks. Dense forest is a set of clumps, not spaced trees.
2. **Broadleaf crowns are very wide.** v4 oak/birch/blossom crowns use canopy radii 3–4;
   with lean and per-layer shelf the actual horizontal reach is 5–6 blocks. At 1–2 block
   trunk spacing, every crown overlaps many neighbours.
3. **Crown tops are broad and coplanar.** The v4 profiles put a radius-2 leaf plate at two
   consecutive top layers and use the same four profiles for every tree. Even where there
   are gaps, the upper surface reads as a stepped green slab rather than a set of peaks.
4. **Clearings exist but are not enough.** v4 has 22.8% designated clearing area and a
   564-column crown-free opening. Crowns rooted outside a clearing still overhang its edge,
   and the remaining forest is so tightly packed that the canopy between clearings is
   continuous.

Rendering is not the cause. Leaves are cutout blocks with `cull_same = 1`; overlapping
crowns legitimately cull internal faces and produce one outer leaf surface. No chunk-mesher
change is needed or planned.

## 2. Design decisions

### D1. New generator version 5

Add `M34_VERSION := 5` and set `CURRENT_VERSION := 5`. All M34 behaviour is gated on
`_is_m34()` (`terrain_version >= M34_VERSION`). Versions 0–4 keep byte-identical output and
their existing pins. New worlds use v5; loaded saves keep their recorded version. The M33
streaming fix (`ChunkStreamer` uses `world.generator.terrain_version`) already ensures a
v4 save streams v4 chunks and is preserved unchanged.

Terrain heights, surface materials and biomes remain v4 behaviour. Only tree placement,
tree species/crown construction and the resulting generated blocks differ. A v5 world has
the same landscape shape as v4.

Version pins after implementation:

- v0 `3214517825889907206`
- v1 `5947596836865492245`
- v2 `8397584315617538769`
- v3 `8802792587028581708`
- v4 `2164503133686526591`
- v5 measured and pinned by the M34 test after the final thresholds are fixed.

### D2. Grove-aware woodland thinning (dense groves keep their density)

The v4 2×2 candidate grid is kept. For v5 forest candidates, add one deterministic
grove-aware thinning step **after** the candidate column is chosen and **before** the
expensive density/species work:

```gdscript
const M34_GROVE_PATCH := 0.34
const M34_WOODLAND_KEEP := 4   # out of 9

var patch := _forest_patches.get_noise_2d(x, z)
if patch <= M34_GROVE_PATCH \
        and _hash2(cell_x, cell_z, 9101) % 9 >= M34_WOODLAND_KEEP:
    return {"type": TreeType.NONE}
```

- `patch > 0.34` is the existing M33 dense-grove class (`test_generation.gd` already uses
  this threshold). Dense groves keep **all** v4 candidates, so their tree density is not
  reduced.
- Open and transition woodland keeps 4 of 9 candidates (about 44%), so it gains larger
  gaps and a more irregular tree distribution. The hash is on the candidate cell, not on
  the column; it is deterministic but deliberately irregular at the 2-block cell scale,
  which the visual checklist checks for speckle.
- Clearings (`vegetation_score < -0.16`) still return no tree before this step matters.

This is deliberately **not** a uniform density-field reduction: dense groves keep their v4
candidate rate; only the surrounding woodland is thinned. It also keeps the existing
candidate positions, so the change is small and does not introduce a new grid.

The diagnostic simulation (`m34_canopy_probe.gd`, seed 17017) predicts:

| Metric | v4 | v5 simulation |
|---|---|---|
| Global forest tree-column coverage | 9.54% | 5.55% |
| Dense `LOWLAND_BOX` tree coverage (in-box trunks) | 11.03% | 4.78% |
| Open-woodland canopy box tree coverage (in-box trunks) | 9.49% | 3.58% |
| Full forest-cell p50 / p90 / max | 8.91% / 18.94% / 25.59% | 4.44% / 10.38% / 25.59% |
| Canopy box open / 2+ / 3+ | 34.0% / 61.6% / 57.6% | 43.6% / 46.5% / 36.3% |
| Canopy box median nearest-trunk distance | 1.41 | 2.00 |
| `LOWLAND_BOX` crown union | not measured | 63.2% |
| Canopy box crown union | 66.0% | 56.4% |

The box trunk-coverage numbers count trunks rooted inside the box. An earlier
simulation counted trees in the box's +10 margin and over-reported box coverage; the
crown-union figures are the lushness guard and are measured with the same crown-disc
metric as tests 9–11.

The simulation models the D3 radius distribution (oak 2/3, birch and blossom 2/3) and the
D4 understory cap, so the overlap numbers are not the optimistic all-radius-2 case. The
dense-grove maximum stays identical to v4, while the open woodland and the canopy box
improve substantially. The actual v5 generator must reproduce these placement numbers
before the test thresholds are pinned; the probe output is committed as
`prototypes/m17/results/godot/m34-diagnosis.txt`.

Non-forest trees (plains, savanna, snow, mountain, desert cactus) keep their existing
per-column rules and are not affected by the woodland thinning. River core/outer rules, the
elevation factor table and the slope factor table are reused unchanged from v4.

### D3. Smaller, more varied broadleaf crowns

For v5 broadleaf trees only:

- Oak: canopy radius 2 or 3, roughly even split, deterministic per tree.
- Birch: canopy radius 2 normally; radius 3 on roughly one tree in four.
- Blossom: canopy radius 2 normally; radius 3 on roughly one tree in three.
- No v5 broadleaf crown exceeds radius 3. The v4 maximum of 4 is removed for v5 only.
- Pines keep their v4 conical tiers and radii.

This keeps the chunky voxel vocabulary and the existing species, while reducing the
horizontal reach from 5–6 blocks to 4–5 blocks (canopy radius 3 + lean 1 + shelf 1 = 5).
It also produces a mixed canopy with smaller understory crowns and occasional larger oak
crowns instead of a field of identical wide domes.

### D4. Crown silhouette and height-class variation

`_place_broadleaf()` gains a v5-only profile branch before the existing M32 branches:

- Radius 3 uses six deterministic profiles with different shoulder heights, including
  taller/narrower, bottom-heavy and asymmetric variants. Every profile tapers to a narrow
  top instead of repeating a radius-2 plate at two consecutive top layers.
- Radius 2 uses four deterministic profiles with an uneven shoulder and a one-block top.
- The existing per-layer shelf and per-tree lean remain at their v4 ±1 limits. v5 does
  **not** add a two-block lean, so the maximum horizontal reach stays
  `canopy radius 3 + lean 1 + shelf 1 = 5` and the crown-disc test (`canopy + 2`) matches
  the actual geometry.
- Emergent-class broadleaf trees (the ~12% open / ~20% dense share in the height-class
  table below) get one extra leaf block above the normal top, producing a small spire.
  This is a vertical silhouette cue, not a new tree model or a new block type.
- The outer crown ring is trimmed slightly harder for v5 (at most one third of corner
  cells and two thirds of edge cells survive the hash test) so crown edges stay ragged and
  flat contact surfaces are reduced.

v5 also introduces three deterministic broadleaf height classes:

| Class | Share (open woodland) | Share (dense grove) | Effect |
|---|---|---|---|
| Emergent | ~12% | ~20% | trunk +2, extra top leaf (radius follows the species rule) |
| Canopy | ~68% | ~55% | existing trunk height |
| Understory | ~20% | ~25% | trunk −1, crown radius capped at 2 |

The class is chosen from a hash of world coordinates and biased by the local forest patch.
The minimum trunk remains at least four blocks, so no tree floats or becomes a stump. The
purpose is to break the flat, coplanar top surface in dense groves even where the canopy is
closed: emergents and understory trees create readable layers and crown peaks. This is a
height/shape variation on the existing tree model, not a new asset or block type.

For v5 broadleaf trees the class is exposed as a `height_class` key in the `tree_at`
dictionary (`0` canopy, `1` emergent, `2` understory). Placement code ignores the extra
key; tests use it to verify the three classes exist without re-deriving the hash.

All variation is a pure hash of world coordinates, tree top and generator seed. No mutable
state, no per-frame work and no non-deterministic randomness is introduced.

### D5. Clearings and forest composition

The v4 `vegetation_score` field, `M33_CLEARING_SCORE = -0.16` clearing rule, river rules and
decor clearing rule are reused unchanged for v5. No new clearing shape is invented.

The expected composition after D2–D4 is:

- genuinely dense groves (`forest_patch > 0.34`) keep their v4 candidate density; the
  full forest-cell maximum stays identical to v4 (simulated 25.59%) and the dense grove
  subset is directly compared with v4 in test 18;
- irregular open woodland with roughly 3.5–5.5% in-box trunk coverage and 56–63% crown
  union, so it stays lush while individual crowns become readable;
- the existing large clearings, now more effective because crowns are smaller and the
  woodland between them is less tightly packed;
- no uniform global thinning: the dense-grove candidate rate is unchanged, and the
  open-woodland thinning is a composition rule, not a lower density field;
- no artificial circular or grid-aligned openings.

The absolute forest tree-column coverage falls from 9.54% to about 5.6% because open
woodland is thinned. That is intentional spacing, not a blanket density change: dense
groves remain at v4 density, the clearings are unchanged, and the lowland crown-union floor
below guards against a sparse world.

If the measured `LOWLAND_BOX` crown union falls below 55%, the `LOWLAND_CANOPY_BOX` crown
union falls below 45%, or the dense-grove comparison shows that groves were thinned, the
implementation is tuned by adjusting the woodland keep fraction (4/9 to 5/9), the crown
radius distribution, or the height-class shares within this spec before completion. A
blanket reduction of the density field is not an acceptable fix.

### D6. Mountain, river and terrain preservation

M34 does not change:

- `height_at()`, `biome_at()`, river carving, bank materials, snow caps or biome boundaries;
- the v4 **density** elevation factor table (broadleaf hard limit `SEA+30`, conifer limit
  `SEA+44`, snow limit `SEA+38`). v5 crown radii are a separate, elevation-independent
  geometry rule; the density table itself is unchanged;
- the v4 slope factor table;
- the v4 river core `<1.25 × RIVER_BANK_LIMIT` exclusion and outer `1.25..1.55` thinning.
  The woodland thinning applies to forest candidates in the outer band too, so v5
  river-outer coverage is measured on the actual generator; it must stay above the
  existing 0.5% floor. If it does not, the outer-band factor is adjusted within the
  existing rule rather than weakening the river core;
- the v4 snow/mountain 0.6% per-column pine cap;
- the v4 decoration clearing rule and high-ground decor thinning.

Mountain silhouettes are checked visually against `m33-final-2.png`; no broadleaf may
reappear on upper slopes and no summit tree carpet may return.

### D7. Chunk boundaries and save compatibility

- `M32_TREE_PAD = 8` is unchanged. The v5 maximum horizontal reach is radius 3 + lean 1 +
  shelf 1 = 5, inside the pad.
- Tree placement remains a pure function of `(seed, x, z, generator_version)`. The 2×2
  candidate cell and the woodland-thinning hash are world-aligned and work in negative
  coordinates with floor division.
- The chunk generator still loops the padded neighbourhood, so a crown crossing a chunk
  border is written by every chunk that owns part of it, in any load order.
- v5 saves record generator 5. v4 saves keep generator 4 and continue to stream v4 chunks
  through the existing M33 streaming fix.
- Block edits, save/load, chunk streaming and tree interaction are unchanged.

## 3. Tests

Add `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd` and register it in
`run_tests.gd`. Use seed 17017, the existing `[-192,192]` step-1 sample, the existing
`LOWLAND_BOX = Rect2i(200, 280, 48, 24)` and `LOWLAND_CANOPY_BOX = Rect2i(192, 256, 64, 64)`,
and explicit thresholds. Existing v4 tests remain in place and must still pass.

### 3.1 Version and historical compatibility

1. `M34_VERSION == 5`, `CURRENT_VERSION == 5`, `M33_VERSION == 4`.
2. Versions 0–5 are supported; version 6 is rejected.
3. v0–v4 region hashes equal the existing pins; v5 is deterministic, distinct, and pinned
   after the final implementation measurement.
4. v5 `height_at()` and `biome_at()` equal v4 over the representative sample.
5. A v5 save records/restores generator 5; a v4 save still records/restores 4.

### 3.2 Crown variation and determinism

6. Two v5 generators produce identical tree types, canopy radii and chunk fingerprints;
   a different seed changes the layout.
7. Lowland broadleaf trees contain at least two distinct canopy radii (2 and 3) with each
   radius represented by at least 5% of the sample, and no broadleaf canopy radius >3.
8. Broadleaf trunk heights contain at least four distinct values; the `height_class` key
   contains all three classes (canopy, emergent, understory) in the lowland sample; no
   arbitrary/unstable randomness is used (all values reproduce across generator instances).

### 3.3 Crown overlap and spacing reduction

Compute 2D crown discs from the tree dictionaries (`canopy + 2` for broadleaf, `5` for pine)
in `LOWLAND_CANOPY_BOX`, including trees rooted just outside the box. All ratios in tests
9–11 are **fractions of forest columns in the box**, matching `m34_canopy_probe.gd`
(`multi_ratio`, `triple_ratio`, `open_ratio`), not fractions of crown-covered columns.
Compare v4 and v5:

9. v5 forest columns covered by 2+ crowns is at least 0.08 lower than v4 and <=0.50
   (v4: 0.616; simulated v5: 0.465).
10. v5 forest columns covered by 3+ crowns is at least 0.10 lower than v4 and <=0.40
    (v4: 0.576; simulated v5: 0.363).
11. v5 open (crown-free) forest columns is at least 0.05 higher than v4 and >=0.40
    (v4: 0.340; simulated v5: 0.436).
12. v5 median nearest-trunk distance in the box is >=1.9 blocks and at least 0.4 blocks
    higher than v4 (v4 box: 1.41; simulated v5: 2.00).

### 3.4 Dense forest, composition and clearings

13. `LOWLAND_BOX` is the dense lowland sample: in-box forest tree-column coverage is
    >=4.5% and <=13%, and its 2D crown-disc union (the same metric as tests 9–11) covers
    >=55% of forest columns (measured 4.78% and 63.2%; v4 was 11.03%). `LOWLAND_CANOPY_BOX`
    is the open-woodland sample: in-box forest tree-column coverage is >=3% and <=8.5%, and
    its crown union covers >=45% of forest columns (measured 3.58% and 56.4%). This proves
    that dense lowland forest is preserved while the open woodland gains gaps.
14. **Full** 32×32 forest cells — cells with at least 512 all-column samples and at least
    256 forest columns, so edge slivers are excluded — use forest columns as the
    denominator. Require p50 <=8%, p90 >=9%, max >=18%, at least five full cells >=8%,
    and at least two full cells >=12% (simulated: p50 4.44%, p90 10.38%, max 25.59%,
    13 cells >=8%, 5 cells >=12%). This preserves dense groves and rejects a uniformly
    sparse world. Open-ground evidence comes from the existing clearing test (17), not
    from full forest cells, which are dense by construction.
15. Global forest tree-column coverage is >=5% and <=8% (simulated 5.55%).
16. `vegetation_score < -0.16` forest columns still contain zero trees; designated clearing
    area remains >=20% of forest columns.
17. `LOWLAND_CANOPY_BOX` still has >=100 clearing columns, a crown-free connected component
    of >=200 columns (simulated 726), and >=50% of clearing columns outside every crown
    footprint.
18. Dense grove columns (`forest_patch > 0.34`) still contain trees of at least three species
    and at least 10 trees in the existing generation sample. For every sampled forest
    column with `forest_patch > 0.34`, v5 and v4 must return the same `tree_at` `type` and
    `base` fields (not `base + height`, because v5 height classes intentionally change
    `height`); the woodland thinning is skipped in this class, so tree presence and species
    cannot change. This directly proves that dense groves were not thinned, instead of
    relying on an arbitrary dense-cell definition.

The thresholds in tests 9–15 are derived from the committed diagnostic simulation, not
from an implemented v5 generator. Before pinning them, run the actual v5 probe and record
the measured values in `m34-diagnosis.txt`. Tests 7–8 (radius shares and height classes)
must also be confirmed against the actual v5 probe before their minimum shares are pinned.
Adjust a threshold only with the measured value and a stated margin; do not weaken the
visual requirement to fit an implementation that still looks continuous.

### 3.5 Mountain, river, boundaries and persistence

19. No broadleaf above `SEA+30`; broadleaf in `SEA+27..30` is <=2% of columns.
20. Tree coverage above `SEA+40` is <2%, no broadleaf above `SEA+40`, and zero trees above
    `SEA+44`.
21. Upper-slope trees (`SEA+30..40`) are pine only.
22. River core has zero trees in every biome; outer river coverage is >0.5% and <20%.
23. v5 chunks on both sides of the x=48 border match in both generation orders, including a
    crown that crosses the border.
24. A v5 world with a player edit saves, reloads and preserves the edited block; chunk
    streaming still uses the saved generator version.

### 3.6 Existing tests to update

- `test_m33_vegetation.gd`: keep `M33_VERSION == 4` and the v4 pin; update
  `CURRENT_VERSION == 5` and the future-version assertion. Its sample stays on v4 so M33
  behaviour is not silently retested as v5.
- `test_m32_landscape.gd`: update `CURRENT_VERSION == 5` and the current-version wording.
- `test_m31_wilderness.gd`: uses `CURRENT_VERSION`; verify it still passes.
- `test_generation.gd`: v5 inherits the M33 clearing branch; verify dense-grove assertions
  still pass.
- `wilderness_probe.gd`: include v4 and v5 in the fingerprint loops.
- `m33_vegetation_probe.gd`: it defaults to `CURRENT_VERSION`; update its version gate so
  it reports v5 correctly instead of silently treating v5 as the v4 branch. Keep the v4
  mode available for historical comparison.
- `m34_canopy_probe.gd`: commit the diagnostic and its output; use it to confirm the v5
  thresholds before they are pinned in the test.
- `run_tests.gd`: register the new module.
- `test_streaming_lifecycle.gd` / `test_persistence.gd`: verify the v5 default and v4 saved
  versions without weakening the existing v3/v4 checks.

## 4. Performance

Measure before (v4, M33 worktree) and after (v5, M34 worktree) with seed 17017, render
radius 6, fixed time 0.28, no HUD, same graphics settings, three runs per camera:

- normal gameplay `-7.3,101.5,-29`, yaw 270, pitch −12;
- river `80,92,180`, yaw 0, pitch −25.

Report medians and ranges for average FPS, p95/p99 frame time, 1% low, worst sampled frame,
draw calls, generation total, mesh-build total, and loaded/wanted/queued/in-flight chunk
counts.

Expected direction: fewer candidate trees and smaller crowns reduce generation, leaf faces
and mesh cost, so no material regression is expected. A >5% median FPS drop or >10% p99
increase is investigated and explained before completion. If the woodland-thinning or
crown path unexpectedly increases cost, profile it rather than dismissing it as variance.

## 5. Visual evidence

Capture matched v4-before and v5-after images at the same seed, cameras, render radius 6,
`--fly`, `--hide-hud`, `--settle=25`, 1280×720, frozen time 0.28.

Required shots:

1. **Elevated canopy**: `224,92,288`, yaw 75, pitch −24 (the M33 `m33-final-4.png` camera),
   plus an oblique `224,110,288`, yaw 75, pitch −35.
2. **Normal gameplay**: `-7.3,101.5,-29`, yaw 270, pitch −12 (`m33-final-3.png`).
3. **Clearing transition**: `80,72,160`, yaw 90, pitch −8 (`m33-final-1.png`).
4. **Mountain and summit**: `76,140,-40`, yaw 180, pitch −14 (`m33-final-2.png`).
5. **River and forest**: `80,92,180`, yaw 0, pitch −25 (`m33-final-0.png`) and
   `80,72,160`, yaw 0, pitch −8 (ground river/banks).
6. **Forest interior at ground level**: `224,74,288`, yaw 90, pitch 0 (the canopy-box
   surface at that column is about y=72), to show trunks, ground and depth.

Per-shot checklist:

- individual crowns or small groups are readable from above, with visible gaps;
- no single flat green slab across the elevated view;
- dense groves still look lush, not uniformly sparse;
- clearings expose terrain/undergrowth and have irregular edges;
- no circular, grid-like or straight vegetation boundaries;
- open woodland does not show a 2-block checkerboard or salt-and-pepper tree speckle;
- no broadleaf on the upper mountain, no summit tree carpet;
- river and banks remain readable and unchanged.

The milestone does not pass on density percentages alone. The images are inspected directly;
if the elevated view still reads as a continuous surface, the implementation is revised
before completion.

## 6. Requirement-to-test matrix

| M34 requirement | Tests / evidence |
|---|---|
| A distinct crowns | 6–12, 13–14, elevated captures |
| B natural composition | 13–18, elevated/clearing captures |
| C ground-level readability | 12–13, forest-interior capture |
| D mountain ecology | 19–21, mountain capture |
| E river and terrain | 4, 22, river captures |
| determinism / historical pins | 1–5, 6, 23–24 |
| performance | section 4 measurements |
| visual acceptance | section 5 captures |

## 7. Risks and mitigations

- **Over-thinning**: lowland tree/crown coverage and dense-cell counts are measured; the
  density field is not reduced. If coverage falls below the thresholds, increase crown
  radius variation or adjust the woodland keep fraction within this spec.
- **Grid regularity / speckle**: the 2×2 candidate jitter, per-tree lean/shelf and varied
  profiles break the cell pattern; visual checklist rejects straight lines. If the
  per-cell thinning produces salt-and-pepper speckle, replace the thinning hash with a
  low-frequency woodland noise threshold or raise the keep fraction to 5/9, then re-check
  the open-woodland metrics.
- **Still-continuous canopy**: if the elevated view remains a slab, reduce the broadleaf
  maximum to radius 2 in dense groves, trim the outer ring further, or adjust the woodland
  keep fraction within the 4/9–5/9 tuning range. Re-measure the crown-union floor; do not
  blanket-thin the forest.
- **Dense groves stay closed by design**: dense groves keep v4 candidate density, so their
  canopy may remain connected. Height classes, smaller crowns and pointed profiles must
  make individual crowns readable inside that canopy; the elevated captures decide whether
  this is sufficient. Near-adjacent trunks are intentionally retained in these groves.
- **Chunk seams**: world-aligned cells, unchanged pad, both-order border test.
- **Old saves**: v5 only for new worlds; v4 pins and v4 streaming remain.
- **Performance**: expected improvement; measured before/after with matching settings.

## 8. Out of scope

Far-field composition, renderer or shader changes, terrain/river/biome redesign, new tree
assets or texture-pipeline changes, structures, NPCs, gameplay systems, unrelated
refactoring, and the Python/Ursina implementation.
