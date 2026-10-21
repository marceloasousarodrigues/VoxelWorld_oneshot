# M34 — Canopy Shape and Forest Composition

## Status

**Implementation complete; independent review pending.** v5 replaces the v4 continuous
canopy with a grove-aware woodland: dense groves keep their v4 candidate rate, open
woodland keeps four of nine candidates, broadleaf crowns are smaller and more varied, and
v5 adds emergent/understory height classes and narrower crown profiles. Historical
generators 0–4 remain byte-identical; v5 is pinned.

## Preflight

- Original checkout: `C:/Users/Admin/Documents/Projects/VoxelWorld_oneshot`, `main` at
  `32a104d`, dirty with pre-existing user files; it was not modified.
- Base: M33 tip `c0b58c3` on `codex/m33-vegetation-ecology`.
- Work branch: `codex/m34-canopy-composition`; worktree
  `C:/Users/Admin/Documents/Projects/VoxelWorld_m34`.
- Godot 4.7.2 stable mono, Vulkan, NVIDIA GeForce RTX 3080. Ursina/Python untouched.
- Spec: `docs/superpowers/specs/2026-10-21-m34-canopy-composition-design.md` (independent
  spec review PASS after three revisions).
- Plan: `docs/superpowers/plans/2026-10-21-m34-canopy-composition.md` (independent plan
  review PASS).
- Diagnosis: `prototypes/m17/results/godot/m34-diagnosis.txt`.

## Root causes

The M33 report already recorded the remaining limitation: `m33-final-4.png` still reads as
one green surface. A read-only diagnostic measured the v4 lowland canopy box:

- median nearest-trunk distance **1.41 blocks** (p25 1.00, p75 2.00);
- 337 trees in/intersecting the box, 9.54% forest tree-column coverage;
- 66.0% crown-covered forest columns;
- 61.6% of forest columns under 2+ crowns and 57.6% under 3+ crowns;
- only 4.4% of forest columns under exactly one crown;
- broadleaf actual crown reach 5–6 blocks.

The 2×2 candidate grid with `hash % 2` jitter allows adjacent-cell trunks one block apart.
The v4 broadleaf crowns (canopy radius 3–4 plus lean/shelf) then overlap many neighbours.
The v4 crown profiles also repeat a radius-2 plate at two consecutive top layers, so the
upper surface is a stepped slab. Clearings are real (22.8% designated area, 564-column
crown-free component), but the remaining woodland is too tightly packed for them to read.

Rendering is not the cause; leaf blocks cull internal faces and one outer leaf surface is
the expected result of overlapping crowns. No mesher change was made.

## Implementation

### Generator version 5

`WorldGen.M34_VERSION = 5`, `CURRENT_VERSION = 5`. All M34 behaviour is gated on
`_is_m34()`. Terrain heights, biomes, river carving, bank materials, snow caps and surface
materials are unchanged.

### Grove-aware woodland thinning

The v4 2×2 candidate grid is kept. A v5 forest candidate is rejected when

```
forest_patch <= 0.34 and hash(cell_x, cell_z, 9101) % 9 >= 4
```

Dense groves (`forest_patch > 0.34`) keep every v4 candidate; open and transition woodland
keeps four of nine. The thinning is before the expensive score/slope/species work. This
preserves dense groves and increases spacing only where the canopy needs openings.

### Crown radii and height classes

v5 broadleaf crowns use canopy radius 2–3 (oak 2/3, birch and blossom 2/3); no v5
broadleaf crown exceeds 3. Three deterministic height classes add vertical layering:

| Class | Open woodland | Dense grove | Effect |
|---|---|---|---|
| Emergent | ~12% | ~20% | trunk +2 and one extra top leaf |
| Canopy | ~68% | ~55% | normal trunk |
| Understory | ~20% | ~25% | trunk −1, crown radius capped at 2 |

The class is exposed as `height_class` in the v5 tree dictionary for tests. Pines keep
their v4 tiers.

### Crown silhouettes

`_v5_layer_radii()` provides six radius-3 profiles and four radius-2 profiles. Every
profile tapers to a narrow top; there is no repeated radius-2 top plate. The outer ring is
trimmed harder for v5: one third of corner cells survive and one third of edge cells are
trimmed. The existing ±1 lean and per-layer shelf remain; the maximum horizontal reach is
radius 3 + lean 1 + shelf 1 = 5, inside `M32_TREE_PAD = 8`.

### Compatibility and rendering

- v0–v4 pins unchanged; v5 pin `5133898688464144157`.
- v5 height/biome functions equal v4 over the representative sample.
- v5 saves record generator 5; v4 saves keep 4. The M33 streaming fix passes for both v3
  and v5 in `test_streaming_lifecycle.gd`.
- Chunk-boundary test covers a v5 crown crossing x=48 in both load orders.
- No renderer, material, terrain, river, biome, structure or gameplay changes.

## Measured composition

Seed 17017, sample `[-192,192]` step 1 (148,225 columns; 43,603 forest columns).

| Metric | v4 | v5 |
|---|---|---|
| Global forest tree-column coverage | 9.54% | 5.55% |
| `LOWLAND_BOX` in-box trunk coverage | 11.03% | 4.78% |
| `LOWLAND_BOX` crown union | not measured | 63.2% |
| `LOWLAND_CANOPY_BOX` in-box trunk coverage | 9.49% | 3.58% |
| Canopy box open / 2+ / 3+ | 34.0% / 61.6% / 57.6% | 43.6% / 46.5% / 36.3% |
| Canopy box crown union | 66.0% | 56.4% |
| Median nearest-trunk distance | 1.41 | 2.00 |
| Full forest-cell p50 / p90 / max | 8.91% / 18.94% / 25.59% | 4.44% / 10.38% / 25.59% |
| Full cells >=8% / >=12% | 34 / 21 | 13 / 5 |
| Designated clearing columns | 7,703 | 9,938 |
| River core trees | 85 | 0 |
| Broadleaf above `SEA+30` | 417 | 0 |
| Trees above `SEA+40` | 90 | 2 |

The box trunk-coverage figures count trunks rooted inside the box. An earlier probe
version counted trees in the +10 margin and over-reported box coverage; the committed
diagnosis records both the v4 baseline and the corrected actual v5 values. Crown union is
the lushness guard: 63.2% in the dense lowland sample and 56.4% in the open woodland.

## Visual evidence

Before: v4 from the M33 worktree. After: v5 from the M34 worktree. Same seed 17017,
render radius 6, `--fly --hide-hud --settle=25`, 1280×720, time 0.28.

| View | Camera | Before / After |
|---|---|---|
| Close elevated canopy | `224,92,288`, yaw 75, pitch −24 | `m34-before-0.png` / `m34-after-0.png` |
| Oblique canopy | `224,110,288`, yaw 75, pitch −35 | `m34-before-1.png` / `m34-after-1.png` |
| Higher elevated canopy | `224,120,288`, yaw 75, pitch −30 | `m34-before-extra-0.png` / `m34-extra-0.png` |
| Normal gameplay | `-7.3,101.5,-29`, yaw 270, pitch −12 | `m34-before-2.png` / `m34-after-2.png` |
| Clearing / forest edge | `80,72,160`, yaw 90, pitch −8 | `m34-before-3.png` / `m34-after-3.png` |
| Mountain / summit | `76,140,-40`, yaw 180, pitch −14 | `m34-before-4.png` / `m34-after-4.png` |
| River / forest | `80,92,180`, yaw 0, pitch −25 | `m34-before-5.png` / `m34-after-5.png` |
| River ground | `80,72,160`, yaw 0, pitch −8 | `m34-before-6.png` / `m34-after-6.png` |
| Forest interior | `228,74,288`, yaw 90, pitch 0 | after only; v4 camera occupied by a trunk: `m34-extra-2.png` |

Direct inspection of the captures:

- `m34-extra-0.png` (higher elevated) shows separated crowns, visible gaps and a layered
  canopy; the v4 counterpart is a set of much larger, more continuous crowns.
- `m34-after-1.png` shows individual crowns and small groups along the hillside, with
  terrain and river visible through the openings.
- `m34-after-0.png` still has large foreground crowns at the close camera, but the middle
  distance now has distinct peaks and gaps rather than one uninterrupted green plane. This
  is the weakest elevated capture and is disclosed.
- `m34-after-2.png` (normal gameplay) shows readable trunks, undergrowth, terraces and
  forest depth; the v4 image is a more solid green mass.
- `m34-after-3.png` shows a clearing with individual trees, exposed ground and an irregular
  forest edge; no circular or grid-like boundary is visible.
- `m34-after-4.png` keeps the snow/rock summit free of broadleaf and trees.
- `m34-after-5.png` and `m34-after-6.png` keep the winding river, banks and riverside
  forest readable, with thinner but still present bank vegetation.
- No 2-block checkerboard or salt-and-pepper speckle is visible in the open woodland at
  the captured distances.

## Performance

Three `run_perf.gd` runs per camera per build, `look` phase, vsync and frame cap disabled.

### Normal gameplay `-7.3,101.5,-29`, yaw 270, pitch −12

| Metric | v4 before | v5 after |
|---|---|---|
| Look FPS median (range) | 518.6 (512.7–519.7) | 516.5 (515.5–522.8) |
| Look p95 / p99 ms | 2.521 / 2.964 | 2.530 / 3.013 |
| Look draw calls | 446.4 | 433.3 |
| Settle generation total | 1,043 ms | 806 ms |
| Settle mesh total | 8,683 ms | 7,038 ms |

### River `80,92,180`, yaw 0, pitch −25

| Metric | v4 before | v5 after |
|---|---|---|
| Look FPS median (range) | 442.8 (422.6–443.6) | 441.9 (441.8–445.9) |
| Look p95 / p99 ms | 2.932 / 3.475 | 2.854 / 3.396 |
| Look draw calls | 672.4 | 651.4 |
| Settle generation total | 1,182 ms | 1,183 ms |
| Settle mesh total | 10,505 ms | 10,170 ms |

Chunk counts: normal 678/678 loaded/wanted, max queued 216, in-flight 0 at settle; river
791/791, max queued 205, in-flight 0. No sustained FPS regression: normal median is within
0.4%, p99 +1.7%, draw calls −3%, generation −23%, mesh −19%; river p99 improves and draw
calls fall 3%. Worse sampled frames are run variance, not a sustained regression.

## Verification

| Suite | Result |
|---|---|
| Unit | `M17_TESTS_PASS 2770 assertions`, exit 0 |
| Integration | `M17_INTEGRATION_PASS 463 assertions`, exit 0 |
| Regression | `M17_REGRESSION_PASS assertions=52`, exit 0 |
| Smoke ×2 | `world_hash=1188233828819198944`, `faces_hash=3201666069178630801`, `faces=365154`, `edits=688` |

Generator pins:

| Version | Hash |
|---|---|
| 0 (M29) | `3214517825889907206` |
| 1 (M30) | `5947596836865492245` |
| 2 (M31) | `8397584315617538769` |
| 3 (M32) | `8802792587028581708` |
| 4 (M33) | `2164503133686526591` |
| 5 (M34) | `5133898688464144157` |

Focused M34 tests: version/pins, v5 determinism and seed variation, crown radius and height
class variation, overlap/spacing reduction against v4, lowland/canopy density and crown
union, full 32×32 forest-cell distribution, clearing area and crown-free component, dense
grove v4/v5 type/base equality, mountain/river rules, chunk-boundary crown, v5 save/edit
round-trip, and v5 threaded streaming.

## Independent review

Pending. The final report will record the Reviewer verdict and any resolved findings.

## Limitations

- **Dense groves**: they keep v4 candidate density by design, so the canopy can remain
  connected there. Smaller crowns, narrower profiles and height classes make individual
  crowns readable in the captures, but this is a composition improvement, not a guarantee
  of disconnected crowns in every dense grove.
- **Close elevated camera**: `m34-after-0.png` still has large foreground crowns. The
  higher/oblique captures are the stronger evidence for distinct crowns.
- **Forest interior before/after**: the v4 camera at `228,74,288` is occupied by a trunk, so
  the forest-interior image is after-only; the matched ground-level comparison is the
  normal-gameplay and clearing shots.
- **Terrain and mountains**: unchanged from M33; the stepped snow summit is inherited.
- **No far-field/LOD work**: out of scope and unchanged.
- **Performance**: local RTX 3080/Windows measurements; absolute FPS is not portable.

## Files and commits

- Spec: `docs/superpowers/specs/2026-10-21-m34-canopy-composition-design.md`
- Plan: `docs/superpowers/plans/2026-10-21-m34-canopy-composition.md`
- Generator: `prototypes/m17/godot/scripts/core/world_gen.gd`
- Tests: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd`,
  `test_streaming_lifecycle.gd`, `test_m33_vegetation.gd`, `test_m32_landscape.gd`,
  `run_tests.gd`
- Probes: `prototypes/m17/godot/scripts/tests/m34_canopy_probe.gd`,
  `m33_vegetation_probe.gd`, `wilderness_probe.gd`
- Evidence: `prototypes/m17/results/godot/m34-*.png`, `m34-*.json`,
  `m34-diagnosis.txt`, `m34-verification.txt`, this report.

Commits:

- `4d493c9` — M34 spec and diagnosis
- `a9074cd` — revised spec thresholds
- `d232391` — aligned crown model and dense-grove checks
- `7d4dd46` — final spec review notes
- `8d95334` — implementation plan
- `847d763` — plan test coverage
- `b446ea2` — plan review notes
- `b37383a` — v5 scaffolding and version tests
- `af7245d` — grove-aware v5 placement
- `ff9df0e` — v5 crown radii and height classes
- `2a505c5` — v5 crown silhouettes and pin
- `73b6ef0` — v5 ecology, persistence and regression verification
- evidence/report commit: latest on `codex/m34-canopy-composition`
