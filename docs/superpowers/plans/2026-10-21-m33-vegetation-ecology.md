# M33 Vegetation Ecology Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace v3's elevation- and slope-blind forest canopy with a deterministic v4 vegetation ecology: dense lowland forests, irregular openings, sparse elevation-graded upper slopes, no broadleaf on high summits, and version-safe streaming for old saves.

**Architecture:** Add generator version 4, gated behind `_is_m33()`. Terrain heights, surface materials and biomes remain v3; only tree placement, species, crown size and decor clearing rules change. One new low-frequency woodland noise combines with the existing forest-patch noise into a `vegetation_score`; elevation and slope multipliers filter candidate trees. The background chunk generator is corrected to use `world.generator.terrain_version` so old saves never stream current-version vegetation.

**Tech Stack:** Godot 4.7.2 GDScript, headless `run_tests.gd` / `run_integration.gd`, windowed `--capture --shots`, `run_perf.gd`.

**Spec:** `docs/superpowers/specs/2026-10-21-m33-vegetation-ecology-design.md`

## Global Constraints

- New worlds use generator version 4; v0/v1/v2/v3 output stays byte-identical.
- v3 pin: `8802792587028581708`; v0 `3214517825889907206`, v1 `5947596836865492245`, v2 `8397584315617538769`.
- No terrain height, surface material, block ID, water, structure or save-format changes.
- All placement is a pure function of seed, coordinates and generator version.
- No global searches or per-frame vegetation work.
- Tree crowns stay within `M32_TREE_PAD = 8`.
- Existing tests are not weakened; version-specific tests state their version explicitly.

## Review Focus

1. An old v3 save streams a new chunk with v3 vegetation, not v4.
2. Broadleaf is impossible above `SEA+30`, and summit columns above `SEA+44` have no trees.
3. Dense lowland forest remains convincing when viewed at gameplay height.
4. Clearings are real connected openings, not just trunk-free checkerboards.
5. Steep slopes are less vegetated than flat ground in the same elevation band.

---

### Task 1: v4 scaffolding, pins, and streaming version safety

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd`
- Modify: `prototypes/m17/godot/scripts/game/chunk_streamer.gd`
- Modify: `prototypes/m17/godot/scripts/tests/test_m31_wilderness.gd`
- Modify: `prototypes/m17/godot/scripts/tests/test_m32_landscape.gd`
- Modify: `prototypes/m17/godot/scripts/tests/run_tests.gd`
- Create: `prototypes/m17/godot/scripts/tests/test_m33_vegetation.gd`
- Test: `prototypes/m17/godot/scripts/tests/test_streaming_lifecycle.gd`

**Interfaces:**
- Produces: `WorldGen.M33_VERSION = 4`, `WorldGen.CURRENT_VERSION = 4`, `WorldGen.is_supported_version(0..4)`, `WorldGen._is_m33() -> bool`.

- [ ] **Step 1: Write failing version/pin tests**

In `test_m33_vegetation.gd`, add the module skeleton and:
```gdscript
const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
```
Assert `M33_VERSION == 4`, `CURRENT_VERSION == 4`, versions 0..4 supported, 5 rejected, v0..v3 equal the pins, v4 differs. Register the module in `run_tests.gd`.

- [ ] **Step 2: Run the unit suite and confirm failure**

Run: `Godot ... --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd`
Expected: FAIL because `M33_VERSION` and `CURRENT_VERSION == 4` do not exist yet.

- [ ] **Step 3: Implement v4 scaffolding**

In `world_gen.gd`, add `M33_VERSION := 4`, set `CURRENT_VERSION := 4`, add `_is_m33()`. Keep every existing v3 branch gated on `_is_m32()`.

- [ ] **Step 4: Fix streamed generator version and add its test**

In `chunk_streamer.gd:121`, change `WorldGen.new(world.world_seed)` to
`WorldGen.new(world.world_seed, world.generator.terrain_version)`.
In `test_streaming_lifecycle.gd`, create a v3 world, stream a chunk outside the initial area with threaded generation, and compare its `blocks`, `biomes` and tree cells with a synchronous v3 `ensure_chunk`.

- [ ] **Step 5: Update historical version assertions**

`test_m31_wilderness.gd`: support 4, reject 5, and keep “current >= 2”.
`test_m32_landscape.gd`: `M32_VERSION == 3`, `CURRENT_VERSION == 4`, support 0..4, reject 5, and add `_region_hash(3) == PINNED_M32_HASH`. Keep river/canopy tests on explicit version 3.

- [ ] **Step 6: Run unit tests and commit**

Run the unit suite. Expected: PASS. Commit only scaffolding, pins, streaming fix and version-test updates.

---

### Task 2: Vegetation score, elevation/slope factors, and candidate density

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd`
- Modify: `prototypes/m17/godot/scripts/tests/m33_vegetation_probe.gd`
- Test: `prototypes/m17/godot/scripts/tests/test_m33_vegetation.gd`

**Interfaces:**
- Produces: `_vegetation_score(x: int, z: int) -> float`, `_elevation_factor(height: int, broadleaf: bool) -> float`, `_slope_factor(slope: int, broadleaf: bool) -> float`, `_v4_tree_density(height: int, slope: int, broadleaf: bool, score: float) -> float`.

- [ ] **Step 1: Add failing distribution tests**

Use the global `[-192,192]` step-1 sample. Assert:
- no broadleaf `tree_at` above `SEA+30`;
- broadleaf columns / all columns in `SEA+27..30` <=2%, N>=100;
- all columns >`SEA+40`: tree coverage <2%, broadleaf 0;
- all columns >`SEA+44`: zero trees;
- slope >=3 forest coverage below `SEA+30` is <50% of slope <=1 coverage, N>=100 per class;
- 32×32 cells: p10 <=2%, p50 <=6%, p90 >=8%, at least five low cells and five dense cells;
- v4 `height_at` and `biome_at` equal v3 over the same sample.

- [ ] **Step 2: Run and confirm failure**

Expected: broadleaf/summit/steep assertions fail on the unmodified v4 candidate path.

- [ ] **Step 3: Implement noise and factor helpers**

Add v4-only `_woodland` (`TYPE_SIMPLEX_SMOOTH`, 0.007, 2 octaves, gain 0.55). Implement:
```gdscript
func _vegetation_score(x: int, z: int) -> float:
    return 0.68 * _forest_patches.get_noise_2d(x, z) + 0.32 * _woodland.get_noise_2d(x, z)
```
Use the spec's elevation and slope factor tables exactly. Broadleaf hard limit `SEA+30`; conifer limit `SEA+44`. `_v4_tree_density` applies `0.95 * smoothstep(-0.16, 0.22, score) * elevation_factor * slope_factor`.

- [ ] **Step 4: Add v4 mode to the probe**

`m33_vegetation_probe.gd` must report `vegetation_score`, elevation/slope classes, broadleaf counts, summit counts, lowland coverage, 32×32 cell percentiles, and crown-footprint openness for `LOWLAND_CANOPY_BOX` when version >=4.

- [ ] **Step 5: Run unit tests and probe, tune only within the spec**

Run unit suite and `m33_vegetation_probe.gd --version=4 --radius=192 --step=1`. Adjust thresholds only if measured values show a spec contradiction; record measured values before pinning.

- [ ] **Step 6: Commit**

---

### Task 3: Forest species, clearings, river rules, and crown size

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd`
- Test: `prototypes/m17/godot/scripts/tests/test_m33_vegetation.gd`
- Modify: `prototypes/m17/godot/scripts/tests/test_generation.gd`

**Interfaces:**
- Consumes: `_vegetation_score`, `_elevation_factor`, `_slope_factor`, `_v4_tree_density`.
- Produces: v4 `_forest_canopy_tree()` behavior and v4 `decoration_at()` clearing rule.

- [ ] **Step 1: Add failing clearing/river/species tests**

Assert:
- `vegetation_score < -0.16` forest columns have `tree_at == NONE`;
- clearing area >=20% of sampled forest columns;
- `LOWLAND_BOX` coverage >=6% and <=20%, with oak/birch/pine/blossom present;
- `LOWLAND_CANOPY_BOX` has >=100 clearing columns and a connected crown-free component of >=100 columns, with >=50% clearing columns crown-free;
- river core `<1.25*RIVER_BANK_LIMIT` coverage <1%, outer `1.25..1.55` >0.5% and <20%, N>=100;
- v4 chunks on both sides of the x=48 border match in both load orders, including a crown crossing the border;
- bulk tree columns have smaller crown radii above `SEA+18` than in lowland;
- upper slope `SEA+30..40` is pine-only; `LOWLAND_BOX` has at least three broadleaf/pine species;
- clearing columns have `tree_at == NONE` but adjacent crown leaves may overhang, and decor is decided normally;
- a v4 save records/restores generator 4.

- [ ] **Step 2: Run and confirm failure**

- [ ] **Step 3: Implement v4 forest path**

In `_forest_canopy_tree`, for v4:
- keep the 2×2 candidate grid and `M32_TREE_PAD`;
- apply river core/outer rules;
- reject `vegetation_score < -0.16`;
- choose broadleaf vs pine from the elevation-dependent share;
- multiply density by elevation/slope factors and river-outer factor;
- remove the slope height lift;
- cap broadleaf at `SEA+30`.

- [ ] **Step 4: Implement v4 species/crown rules**

Lowland broadleaf mix 62/16/17/5; pine dominates above `SEA+24`; upper slope pine only. `_oak`/`_birch`/`_blossom` reduce crown radius at `SEA+19..24` and use radius 2 at `SEA+25..30`.

- [ ] **Step 5: Implement v4 non-forest and decor rules**

Plains/savanna sparse clumps with elevation/slope filters; snow/mountain pine cap 0.06 candidate probability below their limits and slope <=2; cactus unchanged. `decoration_at` uses `vegetation_score < -0.16` for v4 clearings; v3 keeps `_forest_patches < -0.32`. Update `test_generation.gd` to branch by version.

- [ ] **Step 6: Run unit tests and probe; tune**

Expected: all new tests pass; probe reports dense lowland, openings, no broadleaf above `SEA+30`, and <2% summit coverage.

- [ ] **Step 7: Commit**

---

### Task 4: Runtime evidence and performance

**Files:**
- Test: windowed capture, `run_perf.gd`
- Create: `prototypes/m17/results/godot/m33-before-*.png` (already captured), `m33-after-*.png`, `m33-before-look.json`, `m33-after-look.json`, `m33-report.md`

- [ ] **Step 1: Capture matched v4 images**

Same seed 17017, render radius 6, `--fly`, `--hide-hud`, settle 25, time 0.28:
- `-7.3,101.5,-29`, yaw 270, pitch −12 (normal gameplay / summit);
- `224,92,288`, yaw 75 (lowland canopy/clearing);
- `80,72,160`, yaw 90 (forest/grass transition);
- `76,140,-40`, yaw 180 (mountain);
- `80,92,180`, yaw 0 and `80,72,160`, yaw 0 (river).

- [ ] **Step 2: Inspect images**

Use the spec's per-shot checklist: no broadleaf above `SEA+30`, no continuous summit canopy above `SEA+40`, visible lowland opening, readable river, no circular/straight cutoffs.

- [ ] **Step 3: Measure performance**

Run `run_perf.gd` at `-7.3,101.5,-29` yaw 270 and `80,92,180` yaw 0, three runs each, before (existing `m33-before-look.json`) and after. Report medians/ranges for FPS, p95/p99, 1% low, worst frame, draw calls, generation/mesh totals, loaded/wanted/queued/in-flight.

- [ ] **Step 4: If visual or performance target fails, fix and repeat**

---

### Task 5: Full verification, v4 pin, review, and report

**Files:**
- Modify: `prototypes/m17/godot/scripts/tests/run_tests.gd`, probes, M31/M32 version tests
- Create: `prototypes/m17/results/godot/m33-report.md`
- Update: `prototypes/m17/results/godot/m33-verification.txt`

- [ ] **Step 1: Run unit, integration, regression**

Unit expected: all assertions pass. Integration expected: 463+ assertions, exit 0. Regression: 52 assertions, exit 0.

- [ ] **Step 2: Run smoke twice**

`--headless --path ... -- --straight-to-game --seed=17017 --render-distance=6 --quit-after=30`
Compare `world_hash`, `faces_hash`, `faces`, `edits`.

- [ ] **Step 3: Pin the final v4 output and verify compatibility**

Measure the final v4 region hash with `wilderness_probe.gd --fingerprint`; add
`PINNED_M33_HASH` to `test_m33_vegetation.gd` and assert it. Verify v0/v1/v2/v3 pins
unchanged and v4 height/biome equal v3 over the representative sample.

- [ ] **Step 4: Independent review**

Reviewer inspects diff, tests, captures, performance, version safety, streaming fix. Fix blocking findings and re-review.

- [ ] **Step 5: Commit and report**

Separate commits for implementation, evidence/perf, and report. Report branch, worktree, exact commits, assertion counts, hashes, performance, limitations and reviewer verdict.
