# M35/M36 — World Creation: Forest Spacing and Treeline (generator v7)

## Status

**Complete; independent review pending.** Newly generated worlds use generator version 7.
Dense groves and open woodland are both more open than v5, and v7 removes trees from the
upper mountain slopes and summits, accounting for the full trunk and crown height.

The work preserves the uncommitted v6/v7 edits already present in `world_gen.gd` and
completes them: the v7 canopy-ceiling check now includes the extra emergent top leaf, the
versioned tests cover v6 and v7, and the default generator is v7.

## Preflight

- Worktree: `C:/Users/Admin/Documents/Projects/VoxelWorld_m34`.
- Godot project: `prototypes/m17/godot`.
- Base: `08fa745` (M34 v5 evidence head) plus uncommitted v6/v7 edits.
- Seed used for all measurements and captures: `17017`.
- The v6/v7 edits already defined `M35_VERSION = 6`, `M36_VERSION = 7`,
  `CURRENT_VERSION = 7`, `M35_TREELINE_LIMIT = SEA+24`, `M36_CANOPY_CEILING = SEA+30`,
  dense-grove thinning, and `_tree_top_y()`. They were preserved and not rewritten.

## Root causes

1. **Dense groves kept every v5 candidate.** v5 thinned open woodland to four of nine
   candidates but left dense groves at the full v4 rate, so groves still read as a
   continuous mass in the user's gameplay view.
2. **No full-height treeline.** v5 limited broadleaf roots to `SEA+30` and pines to
   `SEA+44`, but tall pines and broadleaf crowns could still rise onto upper slopes and
   summits; the mountain capture showed a pine at the snow/rock summit.

## Implementation

### Version 6: first spacing/treeline pass

- Dense groves (`forest_patch > 0.34`) keep one of two candidates.
- Open woodland keeps the v5 four-of-nine candidates.
- Tree roots above `M35_TREELINE_LIMIT = SEA+24` are rejected in every biome.
- v0–v5 behaviour is untouched.

### Version 7: current default

- Dense groves keep one of three candidates (`hash(cell_x, cell_z, 9103) % 3 == 0`).
- Open woodland keeps four of nine, unchanged from v5/v6.
- Tree roots above `SEA+24` are rejected.
- A tree whose **full generated top** exceeds `M36_CANOPY_CEILING = SEA+30` is rejected.
  `_tree_top_y()` computes the top from the tree dictionary and now includes the v5
  emergent extra top leaf, so tall trunks and crowns cannot slip past the ceiling.
- `CURRENT_VERSION = 7`, so newly created worlds use v7.

Determinism and chunk boundaries are unchanged: placement is still a pure hash of
`(seed, x, z, generator_version)`, the candidate grid and tree pad are unchanged, and the
treeline/canopy checks use only the column and tree dictionary.

## Measured behavior

Seed 17017, sample `[-192,192]` step 1 (43,603 forest columns).

| Metric | v5 | v6 | v7 |
|---|---|---|---|
| Global forest tree-column coverage | 5.55% | 4.34% | **3.58%** |
| Dense-grove trees (`patch > 0.34`) | 910 | 442 | **293** |
| Open lowland trees (`patch <= 0.34`, `height <= SEA+8`) | 456 | 456 | 456 |
| Canopy box open / 2+ / 3+ | 43.6% / 46.5% / 36.3% | — | **44.7% / 44.4% / 33.8%** |
| Canopy box crown union | 56.4% | — | **55.3%** |
| Median nearest-trunk spacing | 2.00 | 2.00 | 2.00 |
| River core trees | 0 | 0 | 0 |
| River-outer coverage | — | — | 0.58% |

Dense groves lose about **68%** of their v5 trees (910 → 293) while open lowland keeps the
same placement (456 trees), so the change targets the dense mass rather than blanket-thinning
the whole forest. The v7 canopy box has more crown-free columns and fewer 2+/3+ overlaps
than v5.

### Treeline

| Metric | v5 | v6 | v7 |
|---|---|---|---|
| Root treeline | none above `SEA+44` (pines) | `SEA+24` | `SEA+24` |
| Canopy ceiling | none | none | `SEA+30` |
| Highest root in sample | above `SEA+24` | 86 | **83** |
| Highest full tree top | above `SEA+30` | 102 | **92** |
| Roots above `SEA+24` | >0 | 0 | **0** |
| Full tops above `SEA+30` | >0 | 194 | **0** |
| Trees in elevation band `SEA+31..40` | present | 0 | **0** |

v7's maximum root is 83 and its maximum full top is exactly 92 (`SEA+30`); no root or crown
exceeds the limits. The v6 pass removed the roots but still allowed 194 crowns above the
ceiling; v7 closes that gap. The `76,140,-40` mountain capture shows the summit pine from
v5 is gone.

## Visual evidence

Matched v5 (`m35-before-*`) and v7 (`m35-v7-*`), seed 17017, render radius 6,
`--fly --hide-hud --settle=25`, 1280×720, time 0.28.

| View | Camera | Before / After |
|---|---|---|
| Mountain / forest boundary | `51.9,120.2,19.4`, yaw 90, pitch −35 | `m35-before-0.png` / `m35-v7-0.png` |
| Dense high-ridge forest | `91.8,98.5,-72.2`, yaw 180, pitch −20 | `m35-before-2.png` / `m35-v7-2.png` |
| Dense canopy | `224,120,288`, yaw 75, pitch −30 | `m35-before-3.png` / `m35-v7-3.png` |
| Mountain / summit | `76,140,-40`, yaw 180, pitch −14 | `m35-before-4.png` / `m35-v7-4.png` |
| Normal gameplay | `-7.3,101.5,-29`, yaw 270, pitch −12 | `m35-before-5.png` / `m35-v7-5.png` |
| Clearing / forest edge | `80,72,160`, yaw 90, pitch −8 | `m35-before-6.png` / `m35-v7-6.png` |
| River / forest | `80,92,180`, yaw 0, pitch −25 | `m35-before-7.png` / `m35-v7-7.png` |

Direct inspection:

- `m35-v7-2.png` vs `m35-before-2.png`: the dense ridge forest now has visible gaps and
  separate crowns instead of a continuous green mass.
- `m35-v7-3.png` vs `m35-before-3.png`: the dense island canopy is broken into individual
  crowns with terrain/water visible between them.
- `m35-v7-4.png` vs `m35-before-4.png`: the pine visible near the snow/rock summit in v5 is
  gone in v7; the summit is clean rock and snow.
- `m35-v7-5.png` and `m35-v7-6.png`: normal gameplay and the clearing stay lush but show
  trunks, ground and distinct trees; no grid or checkerboard pattern is visible.
- `m35-v7-7.png`: the winding river, banks and riverside forest remain readable.

The camera at `17.5,86.3,24.2` is inside terrain in this build, so that ground-level shot is
not usable; the normal-gameplay and clearing captures provide the ground-level evidence.

## Checks

| Check | Result |
|---|---|
| Unit | `M17_TESTS_PASS 2847 assertions` |
| Integration | `M17_INTEGRATION_PASS 463 assertions` |
| Regression | `M17_REGRESSION_PASS assertions=52` |
| Smoke ×2 | `world_hash=5132669793853529491`, `faces_hash=4681965802156541697`, `faces=338156`, `edits=604` |

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

New `test_m35_world_creation.gd` covers: v6/v7 version pins, determinism, v4 terrain
equality, v5 > v6 > v7 forest openness, dense-grove reduction, unchanged open-woodland
placement, crown overlap reduction, root treeline, full-height canopy ceiling (including
emergent crowns), river rules, chunk-boundary load order, and v7 save version.

`test_m32_landscape.gd`, `test_m33_vegetation.gd` and `test_m34_canopy_composition.gd`
now assert `CURRENT_VERSION == 7`; their historical v3/v4/v5 samples and pins are
unchanged. `test_streaming_lifecycle.gd` now streams generator versions 3, 4, 5 and 7.

## Performance

Three `run_perf.gd` look-phase runs per camera per build.

| Camera | v5 FPS / p99 / draw | v7 FPS / p99 / draw |
|---|---|---|
| Normal `-7.3,101.5,-29` | 516.5 / 3.013 ms / 433.3 | **527.6 / 2.841 ms / 416.0** |
| River `80,92,180` | 441.9 / 3.396 ms / 651.4 | **447.5 / 3.227 ms / 643.6** |

v7 is slightly faster and draws fewer calls; settle generation is unchanged
(806→814 ms normal, 1183→1183 ms river) and mesh cost falls (7038→6968 ms normal,
10170→10125 ms river). No performance regression.

## Limitations

- v7 is intentionally open: global forest tree coverage is 3.58% (v5 5.55%). Dense groves
  still exist but are thinner; this is the requested change.
- The `17.5,86.3,24.2` ground camera is inside terrain in this build; ground-level evidence
  uses the normal-gameplay and clearing captures.
- Terrain, river, snow caps, biome boundaries and renderer are unchanged from M32/M33.
- Performance numbers are local RTX 3080/Windows measurements.

## Files and commits

- Generator: `prototypes/m17/godot/scripts/core/world_gen.gd` (v6/v7 edits preserved and
  completed)
- Tests: `prototypes/m17/godot/scripts/tests/test_m35_world_creation.gd`,
  `test_m34_canopy_composition.gd`, `test_m33_vegetation.gd`, `test_m32_landscape.gd`,
  `test_streaming_lifecycle.gd`, `run_tests.gd`
- Probes: `m34_canopy_probe.gd`, `m33_vegetation_probe.gd`, `wilderness_probe.gd`
- Evidence: `m35-before-*.png`, `m35-v7-*.png`, `m35-v7-*.json`,
  `m35-diagnosis.txt`, `m35-verification.txt`, this report

Commits: this report is committed with the v6/v7 completion and evidence on
`codex/m34-canopy-composition`.
