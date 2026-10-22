# M37 — Forest Composition and Larger Openings (generator v8)

## Status

**PARTIAL — substantial improvement, not complete.** v8 is the default for newly created
worlds. It opens dense groves and open woodland much further than v7, preserves the v7
treeline, and produces larger connected openings. However, the normal gameplay capture
still contains a dense tree line on the right hillside; that remaining continuous-canopy
feature is disclosed rather than claimed as fixed.

## Preflight

- Worktree: `C:/Users/Admin/Documents/Projects/VoxelWorld_m34`.
- Godot project: `godot`.
- Base: `47d1327` (v7 head).
- No uncommitted user changes were present at the start of this pass.
- Seed 17017 is the primary evidence seed; seed 424242 is the additional seed.

## What changed

### Version 8 is the new default

`M37_VERSION = 8`, `CURRENT_VERSION = 8`. v0–v7 remain pinned and unchanged. v8 keeps the
v7 root treeline (`SEA+24`) and full-canopy ceiling (`SEA+30`), including the emergent
top-leaf allowance.

### Dense groves

- v7 kept 1/3 of dense-grove candidates; **v8 keeps 1/2**.
- A low-frequency opening field (`_grove_openings`, 0.018) removes contiguous patches
  rather than every Nth tree.
- Dense-grove and open-woodland thresholds differ: `-0.2` for dense groves, `0.35` for
  open woodland; slopes use a 0.25-lower threshold.
- A coarse 16×16 deterministic clearing mask removes 70% of slope cells and 20% of
  open-woodland cells, guaranteeing large openings even where the smooth noise is low.
- The v8 forest broadleaf crown is capped at radius 2, so the remaining trees read as
  compact crowns rather than broad surfaces.

### Clearings and treeline

- v8 uses a tree-clearing score threshold of `-0.08` instead of `-0.16`, enlarging existing
  forest openings.
- Treeline behaviour is unchanged from v7: no root above `SEA+24`; no full tree top above
  `SEA+30`. `_tree_top_y()` still includes the emergent extra top leaf.

### Determinism and boundaries

Placement remains a pure hash of `(seed, x, z, generator_version)`. The coarse clearing
cells and low-frequency noise are world-aligned, and the chunk-boundary test compares both
load orders.

## Measured result

Seed 17017, `[-192,192]` step 1.

| Metric | v7 | v8 |
|---|---:|---:|
| Global forest tree coverage | 3.58% | **2.08%** |
| Dense-grove trees (`patch > 0.34`) | 293 | **128** |
| Open lowland trees (`patch <= 0.34`, low elevation) | 456 | **300** |
| Canopy box open / 2+ / 3+ | 43.6 / 46.5 / 36.3% | **61.5 / 25.2 / 15.8%** |
| Dense box (60,−104,64,64) open / 2+ / 3+ | 15.8 / 77.4 / 69.4% | **53.4 / 35.7 / 22.3%** |
| Dense box largest open component | 383 | **899** |
| Canopy box largest open component | 726 | **1866** |
| Median trunk spacing | 2.00 | 2.00 |
| River core trees | 0 | 0 |
| River-outer coverage | 0.58% | 0.71% |

Dense groves lose about **56%** of their v7 trees (293 → 128); open woodland also loses
trees (456 → 300). The dense box gains a connected 899-column opening, and the canopy box
has a 1,866-column opening. This is the requested shift from a continuous canopy toward
larger irregular openings, but global coverage is low (2.08%) and some regions read as
sparse woodland.

### Treeline

| Metric | v7 | v8 |
|---|---:|---:|
| Highest root | 83 | 82 |
| Highest full top | 92 | 92 |
| Roots above `SEA+24` | 0 | 0 |
| Tops above `SEA+30` | 0 | 0 |
| Trees in `SEA+31..40` | 0 | 0 |

The mountain captures remain clear: `m37-final-3.png` and `m37-v8-seedB-3.png` show no
trees on the upper snow/rock slopes.

### Additional seed 424242

- Global forest coverage: **3.25%** (1,182 / 36,374).
- Dense box open / 2+ / 3+: **69.6 / 20.6 / 14.3%**; largest opening 936 columns.
- Treeline: max root 82, max top 92, zero above either limit.

## Visual evidence

Matched v7/v8 captures, seed 17017, radius 6, `--fly --hide-hud --settle=25`, 1280×720,
time 0.28.

| View | Camera | v7 / v8 |
|---|---|---|
| Mountain/forest boundary | `51.9,120.2,19.4`, yaw 90, pitch −35 | `m35-before-0.png` / `m37-final-0.png` |
| Dense high ridge | `91.8,98.5,-72.2`, yaw 180, pitch −20 | `m35-before-2.png` / `m37-final-1.png` |
| Dense canopy | `224,120,288`, yaw 75, pitch −30 | `m35-before-3.png` / `m37-final-2.png` |
| Mountain/summit | `76,140,-40`, yaw 180, pitch −14 | `m35-before-4.png` / `m37-final-3.png` |
| Normal gameplay | `-7.3,101.5,-29`, yaw 270, pitch −12 | `m35-before-5.png` / `m37-final-4.png` |
| Clearing/forest edge | `80,72,160`, yaw 90, pitch −8 | `m35-before-6.png` / `m37-final-5.png` |
| River/forest | `80,92,180`, yaw 0, pitch −25 | `m35-before-7.png` / `m37-final-6.png` |

Additional seed 424242:

- `m37-before-seedB-0..4` (v7) / `m37-v8-seedB-0..4` (v8), same cameras.
- The dense ridge and forest-edge pairs show v8 with clearly separated crowns and open
  ground; the v7 versions are denser walls.

Direct inspection:

- The dense ridge and canopy pairs are much more open; crowns are separate and ground or
  water is visible between them.
- The clearing pair remains lush but readable.
- The mountain/summit pairs stay clear of trees.
- **Remaining problem:** the normal gameplay v8 capture still has a dense tree line on the
  right hillside. It is narrower than v7’s broad mass, but it is still a continuous canopy
  feature. The forest improvement is therefore reported as partial, not complete.
- The coarse 16×16 clearing mask produces some straight-edged openings; this is visible in
  the additional-seed captures.

## Checks

| Check | Result |
|---|---|
| Unit | `M17_TESTS_PASS 2923 assertions` |
| Integration | `M17_INTEGRATION_PASS 463 assertions` |
| Regression | `M17_REGRESSION_PASS assertions=52` |
| Smoke ×2 | `world_hash=6244082895220264557`, `faces_hash=4560890229176639593`, `faces=306321`, `edits=525` |

New `test_m37_forest_composition.gd` covers: v8 pin, determinism, v7 terrain equality,
v7→v8 density and crown-overlap reduction, larger connected openings, preserved treeline,
river rules, chunk-boundary load order, v8 save version, and an additional seed.

Generator pins:

| Version | Hash |
|---|---|
| 0 | `3214517825889907206` |
| 1 | `5947596836865492245` |
| 2 | `8397584315617538769` |
| 3 | `8802792587028581708` |
| 4 | `2164503133686526591` |
| 5 | `5133898688464144157` |
| 6 | `9184026728463986701` |
| 7 | `5732396842800747576` |
| 8 | `6693088695751418916` |

## Performance

Three `run_perf.gd` look-phase runs per camera per build.

| Camera | v7 FPS / p99 / draw | v8 FPS / p99 / draw |
|---|---|---|
| Normal `-7.3,101.5,-29` | 527.6 / 2.841 ms / 416.0 | 506.2 / 3.089 ms / 404.9 |
| River `80,92,180` | 447.5 / 3.227 ms / 643.6 | 442.6 / 3.350 ms / 625.4 |

v8 draws fewer calls and builds slightly cheaper meshes (6,968→6,767 ms normal,
10,125→10,318 ms river), but normal-camera median FPS is **4.0% lower** and p99 is
**8.7% higher**. This is under the 5% FPS / 10% p99 investigation thresholds, but it is
reported rather than dismissed; the extra low-frequency noise/hash work and run variance
are the likely causes.

## Limitations

- **Remaining dense ridge line** in the normal gameplay view. This is why the result is
  partial, not complete.
- Global forest coverage is 2.08% on seed 17017 (v7 3.58%); some areas read as sparse
  woodland rather than dense forest.
- The 16×16 coarse clearing mask can create straight-edged openings.
- No terrain, river, biome, snow-cap or renderer changes.
- Performance figures are local RTX 3080/Windows measurements.

## Files and commits

- Generator: `godot/scripts/core/world_gen.gd`
- Tests: `godot/scripts/tests/test_m37_forest_composition.gd`,
  `test_m35_world_creation.gd`, `test_m34_canopy_composition.gd`,
  `test_m33_vegetation.gd`, `test_m32_landscape.gd`, `test_streaming_lifecycle.gd`,
  `run_tests.gd`
- Probes: `m34_canopy_probe.gd`, `m33_vegetation_probe.gd`, `wilderness_probe.gd`
- Evidence: `m37-final-*.png`, `m37-v8-seedB-*.png`, `m37-before-seedB-*.png`,
  `m37-v8-*.json`, `m37-diagnosis.txt`, `m37-verification.txt`, this report
