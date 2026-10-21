# M34 Canopy Shape and Forest Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make v5 forests read as individual crowns and small groups inside lush, irregular woodland and clearings, while preserving M33's mountain/river ecology, determinism, historical saves and performance.

**Architecture:** Add generator version 5. Keep the v4 2×2 candidate grid and all v4 density/elevation/slope/river/clearing rules. Add a deterministic grove-aware woodland thinning (keep 4 of 9 candidates when `forest_patch <= 0.34`; keep all candidates in dense groves), reduce broadleaf crown radii to 2–3 with deterministic species and height-class variation, and replace the v4 broadleaf crown profiles with narrower, more varied v5 silhouettes. Terrain heights, biomes, river carving, surface materials and rendering are unchanged.

**Tech Stack:** Godot 4.7.2 stable mono, GDScript, headless `run_tests.gd` / `run_integration.gd` / `regression.gd`, windowed `--capture`/`--shots`, `run_perf.gd`.

**Spec:** `docs/superpowers/specs/2026-10-21-m34-canopy-composition-design.md`

**Diagnosis evidence:** `prototypes/m17/results/godot/m34-diagnosis.txt`

## Global Constraints

- New worlds use generator version 5; v0, v1, v2, v3 and v4 output stays byte-identical.
- v0 pin `3214517825889907206`; v1 `5947596836865492245`; v2 `8397584315617538769`; v3 `8802792587028581708`; v4 `2164503133686526591`.
- `M33_VERSION == 4`, `M34_VERSION == 5`, `CURRENT_VERSION == 5`.
- v5 dense groves (`forest_patch > 0.34`) keep the v4 candidate rate; open woodland keeps 4 of 9 candidates.
- v5 broadleaf canopy radius is 2–3; no v5 broadleaf crown exceeds 3.
- v5 maximum horizontal reach is `3 + 1 + 1 = 5`, inside `M32_TREE_PAD = 8`.
- No terrain height, biome, river, surface material, block ID, water, structure, gameplay or renderer change.
- No global searches or per-frame vegetation work. Placement is a pure hash of `(seed, x, z, generator_version)`.
- Existing tests are not weakened. M33 tests keep testing v4 explicitly.
- `height_class` on v5 broadleaf tree dictionaries: `0` canopy, `1` emergent, `2` understory.

## Review Focus

1. An old v4 save streams v4 vegetation, not v5, and a v5 save records 5.
2. Dense groves are not thinned: v4 and v5 `tree_at` `type`/`base` match on every `forest_patch > 0.34` sample column.
3. The open-woodland thinning does not create a 2-block checkerboard or salt-and-pepper speckle in the captures.
4. Crowns crossing chunk borders are complete in both load orders.
5. Mountain/river rules and clearings still hold on v5, not just on v4.

---

### Task 1: v5 scaffolding, version plumbing and existing-test updates

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd:17-25,141-153`
- Modify: `prototypes/m17/godot/scripts/tests/test_m33_vegetation.gd:86-108`
- Modify: `prototypes/m17/godot/scripts/tests/test_m32_landscape.gd:34-41`
- Modify: `prototypes/m17/godot/scripts/tests/m33_vegetation_probe.gd:26-28`
- Modify: `prototypes/m17/godot/scripts/tests/wilderness_probe.gd:121-123,211-213`
- Create: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd`
- Modify: `prototypes/m17/godot/scripts/tests/run_tests.gd:12-54`

**Interfaces:**
- Produces: `WorldGen.M34_VERSION = 5`, `WorldGen.CURRENT_VERSION = 5`, `WorldGen._is_m34() -> bool`.
- Produces: `test_m34_canopy_composition.gd` with `name() -> String` and `run(h: TestHarness) -> void`, registered in `run_tests.gd`.
- Consumes: existing `WorldGen`, `VoxelWorld`, `SaveManager`, `Inventory` and `TestHarness` APIs.

- [ ] **Step 1: Write the failing version/save tests**

In the new `test_m34_canopy_composition.gd`, add the module skeleton and:

```gdscript
const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const SEA := WorldGen.SEA_LEVEL

func name() -> String:
    return "M34 canopy composition"

func _region_hash(version: int) -> int:
    var world := VoxelWorld.new(17017, version)
    for chunk_z in range(-2, 3):
        for chunk_x in range(-2, 3):
            for chunk_y in range(0, 6):
                world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
    return world.fingerprint()

func run(h: TestHarness) -> void:
    h.section("M34 generator versions")
    h.eq(WorldGen.M34_VERSION, 5, "the M34 canopy generator is version 5")
    h.eq(WorldGen.CURRENT_VERSION, 5, "new worlds use the M34 generator")
    h.eq(WorldGen.M33_VERSION, 4, "the M33 generator remains version 4")
    for version in range(0, WorldGen.CURRENT_VERSION + 1):
        h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
    h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1), "a future version is rejected")
    h.eq(_region_hash(0), PINNED_LEGACY_HASH, "version 0 remains pinned")
    h.eq(_region_hash(1), PINNED_M30_HASH, "version 1 remains pinned")
    h.eq(_region_hash(2), PINNED_M31_HASH, "version 2 remains pinned")
    h.eq(_region_hash(3), PINNED_M32_HASH, "version 3 remains pinned")
    h.eq(_region_hash(4), PINNED_M33_HASH, "version 4 remains pinned")
    var v5_a := _region_hash(5)
    var v5_b := _region_hash(5)
    h.eq(v5_a, v5_b, "version 5 generation is deterministic")
    var v4 := WorldGen.new(17017, 4)
    var v5 := WorldGen.new(17017, 5)
    var height_mismatch := 0
    var biome_mismatch := 0
    for z in range(-192, 193, 4):
        for x in range(-192, 193, 4):
            if v4.height_at(x, z) != v5.height_at(x, z):
                height_mismatch += 1
            if v4.biome_at(x, z) != v5.biome_at(x, z):
                biome_mismatch += 1
    h.eq(height_mismatch, 0, "v5 heights equal v4")
    h.eq(biome_mismatch, 0, "v5 biomes equal v4")
    var world := VoxelWorld.new(17017, 5)
    world.ensure_chunk(Vector3i(0, 4, 0))
    var save := SaveManager.new()
    var payload: Dictionary = save.to_dictionary(world, null, Inventory.new())
    h.eq(int(payload["terrain_generator_version"]), 5, "a v5 save records generator 5")
    var v4_world := VoxelWorld.new(17017, 4)
    v4_world.ensure_chunk(Vector3i(0, 4, 0))
    var v4_payload: Dictionary = save.to_dictionary(v4_world, null, Inventory.new())
    h.eq(int(v4_payload["terrain_generator_version"]), 4, "a v4 save still records generator 4")
    h.finish()
```

- [ ] **Step 2: Run the unit suite and confirm failure**

Run:

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd
```

Expected: FAIL because `M34_VERSION` does not exist and `CURRENT_VERSION` is still 4.

- [ ] **Step 3: Implement v5 scaffolding**

In `world_gen.gd`, add `const M34_VERSION := 5`, set `CURRENT_VERSION := 5`, and add:

```gdscript
## True for generator version 5 and later (the M34 canopy composition pass).
func _is_m34() -> bool:
    return terrain_version >= M34_VERSION
```

Do not change any tree path yet. The v5 branch still falls through to v4 behaviour in this task; the distinct-output test will pass in Task 2.

- [ ] **Step 4: Update historical-version tests and probes**

`test_m33_vegetation.gd`: keep `M33_VERSION == 4` and `PINNED_M33_HASH`; change the current-version assertion to `CURRENT_VERSION == 5` and the wording to “new worlds use the current M34 generator”. Its sample must stay `WorldGen.new(17017, WorldGen.M33_VERSION)`.

`test_m32_landscape.gd`: change `CURRENT_VERSION == 4` to `== 5` and the wording to M34.

`m33_vegetation_probe.gd`: replace the `v4 := version >= WorldGen.M33_VERSION` gate with a `modern := version >= WorldGen.M33_VERSION` gate used for score/clearing/crown reporting, and print the version so a v5 run is not mislabeled v4.

`wilderness_probe.gd`: change the density loop to `for version in range(1, WorldGen.CURRENT_VERSION + 1)` and the fingerprint loop to `for version in range(0, WorldGen.CURRENT_VERSION + 1)`.

Register `"res://scripts/tests/test_m34_canopy_composition.gd"` after `test_m33_vegetation.gd` in `run_tests.gd`.

- [ ] **Step 5: Run the unit suite**

Expected: PASS. Task 2 adds the v5-distinct assertion once placement changes; do not change the historical pins.

- [ ] **Step 6: Commit**

```powershell
git add prototypes/m17/godot/scripts/core/world_gen.gd prototypes/m17/godot/scripts/tests/test_m33_vegetation.gd prototypes/m17/godot/scripts/tests/test_m32_landscape.gd prototypes/m17/godot/scripts/tests/m33_vegetation_probe.gd prototypes/m17/godot/scripts/tests/wilderness_probe.gd prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd prototypes/m17/godot/scripts/tests/run_tests.gd
git commit -m "M34: add v5 generator scaffolding and version tests"
```

---

### Task 2: v5 forest placement, grove-aware thinning and dense-grove preservation

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd:24-49,472-480,618-695`
- Modify: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd`

**Interfaces:**
- Consumes: `WorldGen._is_m34()`, `_vegetation_score()`, `_v4_tree_density()`, `_v4_broadleaf_share()`, `_river_distance()`, `_column_slope()`.
- Produces: `WorldGen.M34_GROVE_PATCH = 0.34`, `WorldGen.M34_WOODLAND_KEEP = 4`, `_forest_canopy_tree_v5(x: int, z: int, height: int) -> Dictionary`.
- Produces: v5 forest `tree_at()` placement; v5 still uses the v4 crown constructors until Task 3.

- [ ] **Step 1: Write the failing placement/density tests**

Add constants and helpers to `test_m34_canopy_composition.gd`:

```gdscript
const SAMPLE_RADIUS := 192
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)

func _is_tree(type: int) -> bool:
    return type != WorldGen.TreeType.NONE

func _percentile(values: Array[float], fraction: float) -> float:
    if values.is_empty():
        return 0.0
    var index := clampi(int(round(fraction * float(values.size() - 1))), 0, values.size() - 1)
    return values[index]

func _forest_coverage(generator: WorldGen, box: Rect2i) -> float:
    var columns := 0
    var trees := 0
    for z in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
                continue
            columns += 1
            if _is_tree(int(generator.tree_at(x, z)["type"])):
                trees += 1
    return float(trees) / maxf(1.0, float(columns))
```

Add these tests to `run()`:

```gdscript
h.section("M34 forest composition")
h.check(_region_hash(5) != PINNED_M33_HASH, "version 5 placement differs from version 4")
h.eq(WorldGen.M34_GROVE_PATCH, 0.34, "dense-grove patch threshold matches M33")
h.eq(WorldGen.M34_WOODLAND_KEEP, 4, "open woodland keeps four of nine candidates")
var v4 := WorldGen.new(17017, 4)
var v5 := WorldGen.new(17017, 5)
var lowland_v4 := _forest_coverage(v4, LOWLAND_BOX)
var lowland_v5 := _forest_coverage(v5, LOWLAND_BOX)
var canopy_v4 := _forest_coverage(v4, LOWLAND_CANOPY_BOX)
var canopy_v5 := _forest_coverage(v5, LOWLAND_CANOPY_BOX)
h.greater(lowland_v5, 0.08, "dense lowland forest keeps >=8%% coverage (%.3f)" % lowland_v5)
h.less(lowland_v5, 0.13, "dense lowland forest is not a solid carpet (%.3f)" % lowland_v5)
h.greater(canopy_v5, 0.045, "open woodland keeps >=4.5%% coverage (%.3f)" % canopy_v5)
h.less(canopy_v5, 0.085, "open woodland is not a tree carpet (%.3f)" % canopy_v5)
h.less(canopy_v5, canopy_v4, "open woodland is thinner than v4")
var global_columns := 0
var global_trees := 0
for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
    for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
        if v5.biome_at(x, z) != WorldGen.Biome.FOREST:
            continue
        global_columns += 1
        if _is_tree(int(v5.tree_at(x, z)["type"])):
            global_trees += 1
var global_coverage := float(global_trees) / maxf(1.0, float(global_columns))
h.greater(global_coverage, 0.05, "global forest coverage stays >=5%% (%.4f)" % global_coverage)
h.less(global_coverage, 0.08, "global forest coverage stays <=8%% (%.4f)" % global_coverage)
```

Add the dense-grove direct comparison:

```gdscript
h.section("M34 dense groves preserved")
var grove_columns := 0
var grove_trees := 0
var grove_species := {}
var mismatch := 0
for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
    for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
        if v4.biome_at(x, z) != WorldGen.Biome.FOREST:
            continue
        if v4._forest_patches.get_noise_2d(x, z) <= WorldGen.M34_GROVE_PATCH:
            continue
        grove_columns += 1
        var a := v4.tree_at(x, z)
        var b := v5.tree_at(x, z)
        if int(a["type"]) != int(b["type"]) or int(a.get("base", -1)) != int(b.get("base", -1)):
            mismatch += 1
        if _is_tree(int(b["type"])):
            grove_trees += 1
            grove_species[int(b["type"])] = true
h.greater(float(grove_columns), 100.0, "the dense-grove sample has enough columns")
h.eq(mismatch, 0, "dense-grove tree type/base is unchanged from v4")
h.greater(float(grove_trees), 10.0, "dense groves still contain trees")
h.greater(float(grove_species.size()), 2.0, "dense groves still mix species")
```

Add the clearing tests:

```gdscript
h.section("M34 clearings")
var clearing_columns := 0
var clearing_trees := 0
for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
    for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
        if v5.biome_at(x, z) != WorldGen.Biome.FOREST:
            continue
        if v5._vegetation_score(x, z) < WorldGen.M33_CLEARING_SCORE:
            clearing_columns += 1
            if _is_tree(int(v5.tree_at(x, z)["type"])):
                clearing_trees += 1
h.eq(clearing_trees, 0, "designated clearings contain no trees")
h.greater(float(clearing_columns), 100.0, "clearings remain a real sample")
```

- [ ] **Step 2: Run the unit suite and confirm failure**

Expected: FAIL because v5 still uses v4 placement; `M34_GROVE_PATCH`, `M34_WOODLAND_KEEP` and the density differences do not exist.

- [ ] **Step 3: Add the constants and the v5 forest path**

In `world_gen.gd`, add:

```gdscript
const M34_GROVE_PATCH := 0.34
const M34_WOODLAND_KEEP := 4
```

Add `_forest_canopy_tree_v5(x, z, height)` immediately after `_forest_canopy_tree_v4`. It is a copy of the v4 candidate/river/score/slope/species/density path with one extra step after the candidate check:

```gdscript
func _forest_canopy_tree_v5(x: int, z: int, height: int) -> Dictionary:
    var cell_x := floori(float(x) / CANOPY_CELL)
    var cell_z := floori(float(z) / CANOPY_CELL)
    var candidate_x := cell_x * CANOPY_CELL + _hash2(cell_x, cell_z, 4711) % CANOPY_CELL
    var candidate_z := cell_z * CANOPY_CELL + _hash2(cell_x, cell_z, 4712) % CANOPY_CELL
    if x != candidate_x or z != candidate_z:
        return {"type": TreeType.NONE}
    var patch := _forest_patches.get_noise_2d(x, z)
    if patch <= M34_GROVE_PATCH \
            and _hash2(cell_x, cell_z, 9101) % 9 >= M34_WOODLAND_KEEP:
        return {"type": TreeType.NONE}
    # The rest of this function is the v4 path from the river check through
    # density/species selection. Keep it byte-for-byte equivalent to v4 except
    # for the thinning above and the v5 tree constructors used in Task 3.
    var river_distance := _river_distance(x, z)
    if river_distance < RIVER_BANK_LIMIT * M33_RIVER_CORE:
        return {"type": TreeType.NONE}
    var river_outer := river_distance < RIVER_BANK_LIMIT * M33_RIVER_OUTER
    var score := _vegetation_score(x, z)
    if score < M33_CLEARING_SCORE:
        return {"type": TreeType.NONE}
    var slope := _column_slope(x, z, height)
    var species_roll := _hash2(x, z, 4714) % 100
    var broadleaf := float(species_roll) < _v4_broadleaf_share(height, patch) * 100.0
    if broadleaf and (height > M33_BROADLEAF_LIMIT or slope >= 4):
        broadleaf = false
    var density := _v4_tree_density(height, slope, broadleaf, score)
    if river_outer:
        if slope > 1:
            return {"type": TreeType.NONE}
        density *= 0.25
    if density <= 0.0:
        return {"type": TreeType.NONE}
    if _hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
        return {"type": TreeType.NONE}
    if broadleaf:
        var leaf_roll := _hash2(x, z, 4715) % 100
        if leaf_roll < 75:
            return _oak(x, z, height)
        if leaf_roll < 95:
            return _birch(x, z, height)
        return _blossom(x, z, height)
    return _pine(x, z, height)
```

In `_biome_tree_v4`, change the forest branch to:

```gdscript
if biome == Biome.FOREST:
    if _is_m34():
        return _forest_canopy_tree_v5(x, z, height)
    return _forest_canopy_tree_v4(x, z, height)
```

- [ ] **Step 4: Run the unit suite**

Expected: PASS for the new density/clearing/dense-grove tests. The v5 distinct test now passes. The v5 pin is still not asserted; it is added in Task 4.

- [ ] **Step 5: Commit**

```powershell
git add prototypes/m17/godot/scripts/core/world_gen.gd prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd
git commit -m "M34: add grove-aware v5 woodland placement"
```

---

### Task 3: v5 crown radii, height classes and overlap reduction

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd:776-818`
- Modify: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd`

**Interfaces:**
- Consumes: `_is_m34()`, `_hash2()`, `_hash3()`.
- Produces: `_v5_height_class(x: int, z: int, height: int, patch: float) -> int` returning `0` canopy, `1` emergent, `2` understory.
- Produces: v5 broadleaf tree dictionaries with `canopy` in `2..3` and a `height_class` key.

- [ ] **Step 1: Write the failing crown-variation and overlap tests**

Add helpers:

```gdscript
func _is_broadleaf(type: int) -> bool:
    return type == WorldGen.TreeType.OAK or type == WorldGen.TreeType.BIRCH \
        or type == WorldGen.TreeType.BLOSSOM

func _crown_radius(tree: Dictionary) -> int:
    var type := int(tree["type"])
    if not _is_tree(type) or type == WorldGen.TreeType.CACTUS:
        return 0
    if _is_broadleaf(type):
        return int(tree.get("canopy", 3)) + 2
    return 5

func _crown_stats(generator: WorldGen, box: Rect2i) -> Dictionary:
    var trees: Array[Dictionary] = []
    for z in range(box.position.y - 10, box.end.y + 10):
        for x in range(box.position.x - 10, box.end.x + 10):
            var tree := generator.tree_at(x, z)
            var type := int(tree["type"])
            if not _is_tree(type):
                continue
            var radius := _crown_radius(tree)
            if radius <= 0:
                continue
            if x + radius < box.position.x or x - radius >= box.end.x \
                    or z + radius < box.position.y or z - radius >= box.end.y:
                continue
            trees.append({"x": x, "z": z, "r": radius})
    var counts := {}
    for entry: Dictionary in trees:
        var r := int(entry["r"])
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dz * dz > r * r:
                    continue
                var key := Vector2i(int(entry["x"]) + dx, int(entry["z"]) + dz)
                counts[key] = int(counts.get(key, 0)) + 1
    var columns := 0
    var open := 0
    var multi := 0
    var triple := 0
    for z in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
                continue
            columns += 1
            var count := int(counts.get(Vector2i(x, z), 0))
            if count == 0:
                open += 1
            if count >= 2:
                multi += 1
            if count >= 3:
                triple += 1
    var nearest: Array[float] = []
    for i in trees.size():
        var best := 999999.0
        for j in trees.size():
            if i == j:
                continue
            var dx := float(int(trees[i]["x"]) - int(trees[j]["x"]))
            var dz := float(int(trees[i]["z"]) - int(trees[j]["z"]))
            best = minf(best, sqrt(dx * dx + dz * dz))
        if best < 999999.0:
            nearest.append(best)
    nearest.sort()
    return {
        "columns": columns,
        "open": float(open) / maxf(1.0, float(columns)),
        "multi": float(multi) / maxf(1.0, float(columns)),
        "triple": float(triple) / maxf(1.0, float(columns)),
        "covered": float(columns - open) / maxf(1.0, float(columns)),
        "spacing_p50": _percentile(nearest, 0.5),
    }
```

Add tests:

```gdscript
h.section("M34 crown variation")
var radii := {}
var classes := {}
var heights := {}
for z in range(LOWLAND_BOX.position.y, LOWLAND_BOX.end.y):
    for x in range(LOWLAND_BOX.position.x, LOWLAND_BOX.end.x):
        if v5.biome_at(x, z) != WorldGen.Biome.FOREST:
            continue
        var tree := v5.tree_at(x, z)
        var type := int(tree["type"])
        if not _is_broadleaf(type):
            continue
        radii[int(tree["canopy"])] = int(radii.get(int(tree["canopy"]), 0)) + 1
        classes[int(tree["height_class"])] = true
        heights[int(tree["height"])] = true
var broadleaf_total := 0
for value: int in radii:
    broadleaf_total += int(radii[value])
    h.check(value >= 2 and value <= 3, "broadleaf canopy radius %d is within 2..3" % value)
h.check(radii.has(2) and radii.has(3), "both radius 2 and radius 3 occur")
h.greater(float(radii.get(2, 0)) / maxf(1.0, float(broadleaf_total)), 0.05, "radius 2 is at least 5%%")
h.greater(float(radii.get(3, 0)) / maxf(1.0, float(broadleaf_total)), 0.05, "radius 3 is at least 5%%")
h.check(classes.has(0) and classes.has(1) and classes.has(2), "all three height classes occur")
h.greater(float(heights.size()), 3.0, "trunk heights have at least four values")

h.section("M34 crown overlap reduction")
var v4_stats := _crown_stats(v4, LOWLAND_CANOPY_BOX)
var v5_stats := _crown_stats(v5, LOWLAND_CANOPY_BOX)
h.less(v5_stats["multi"], v4_stats["multi"] - 0.08, "2+ crown overlap drops by >=0.08")
h.less(v5_stats["multi"], 0.51, "2+ crown overlap is <=0.50")
h.less(v5_stats["triple"], v4_stats["triple"] - 0.10, "3+ crown overlap drops by >=0.10")
h.less(v5_stats["triple"], 0.41, "3+ crown overlap is <=0.40")
h.greater(v5_stats["open"], v4_stats["open"] + 0.05, "open forest columns rise by >=0.05")
h.greater(v5_stats["open"], 0.39, "open forest columns are >=0.40")
h.greater(v5_stats["spacing_p50"], 1.9, "median trunk spacing is >=1.9")
h.greater(v5_stats["spacing_p50"], v4_stats["spacing_p50"] + 0.4, "median spacing rises by >=0.4")
h.greater(_crown_stats(v5, LOWLAND_BOX)["covered"], 0.54, "dense lowland crown union is >=55%%")
h.greater(_crown_stats(v5, LOWLAND_CANOPY_BOX)["covered"], 0.44, "open woodland crown union is >=45%%")
```

- [ ] **Step 2: Run the unit suite and confirm failure**

Expected: FAIL because v5 still uses v4 crown radii and has no `height_class`.

- [ ] **Step 3: Implement height classes and v5 radii**

Add before `_oak`:

```gdscript
## Deterministic v5 broadleaf height class: 0 canopy, 1 emergent, 2 understory.
func _v5_height_class(x: int, z: int, height: int, patch: float) -> int:
    var understory := 25 if patch > M34_GROVE_PATCH else 20
    var roll := _hash3(x, height, z, 9102) % 100
    if roll < understory:
        return 2
    var emergent := 20 if patch > M34_GROVE_PATCH else 12
    if roll < understory + emergent:
        return 1
    return 0
```

Modify `_oak`, `_birch`, `_blossom` with a v5 branch after the existing `_is_m32()`/`_is_m33()` logic. For `_oak`:

```gdscript
if _is_m34():
    var patch := _forest_patches.get_noise_2d(x, z)
    var height_class := _v5_height_class(x, z, ground, patch)
    var height_adjust := 2 if height_class == 1 else (-1 if height_class == 2 else 0)
    var canopy := 2 + _hash2(x, z, 555) % 2
    trunk = maxi(4, trunk + height_adjust)
    return {"type": TreeType.OAK, "base": ground + 1, "height": trunk,
        "canopy": canopy, "height_class": height_class}
```

For `_birch`, use `var canopy := 2 + (1 if _hash2(x, z, 556) % 4 == 0 else 0)`, `TreeType.BIRCH`, and the same trunk adjustment/`height_class`. For `_blossom`, use `var canopy := 2 + (1 if _hash2(x, z, 557) % 3 == 0 else 0)`, `TreeType.BLOSSOM`, and the same trunk adjustment/`height_class`. Do not add `height_class` to pine trees.

- [ ] **Step 4: Run the unit suite**

Expected: PASS. If the overlap thresholds are missed by less than 0.02, first verify the probe/implementation use the same `canopy + 2` radius and that the thinning is `4/9`; do not weaken the visual requirement without recording the measured value.

- [ ] **Step 5: Commit**

```powershell
git add prototypes/m17/godot/scripts/core/world_gen.gd prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd
git commit -m "M34: add v5 crown radii and height classes"
```

---

### Task 4: v5 crown profiles, block-level evidence and v5 pin

**Files:**
- Modify: `prototypes/m17/godot/scripts/core/world_gen.gd:1190-1315`
- Modify: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd`
- Modify: `prototypes/m17/results/godot/m34-diagnosis.txt`

**Interfaces:**
- Consumes: v5 tree dictionaries from Task 3.
- Produces: v5-only `_place_broadleaf()` profile branch, narrower top layers and a harder outer-ring trim.
- Produces: `PINNED_M34_HASH` in the M34 test.

- [ ] **Step 1: Write the failing block-level and boundary tests**

Add a helper that samples actual v5 leaf blocks around trees in a small region:

```gdscript
func _leaf_blocks(world: VoxelWorld, box: Rect2i, y_min: int, y_max: int) -> int:
    var count := 0
    for z in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            for y in range(y_min, y_max):
                var block := world.get_block(Vector3i(x, y, z))
                if block == BlockDB.OAK_LEAVES or block == BlockDB.BIRCH_LEAVES \
                        or block == BlockDB.BLOSSOM_LEAVES or block == BlockDB.PINE_LEAVES:
                    count += 1
    return count
```

Add tests:

```gdscript
h.section("M34 crown voxel shape")
var v4_world := VoxelWorld.new(17017, 4)
var v5_world := VoxelWorld.new(17017, 5)
for cy in range(0, 7):
    for cz in range(14, 20):
        for cx in range(12, 18):
            v4_world.ensure_chunk(Vector3i(cx, cy, cz))
            v5_world.ensure_chunk(Vector3i(cx, cy, cz))
var sample_box := Rect2i(192, 224, 32, 32)
var v4_leaves := _leaf_blocks(v4_world, sample_box, 60, 110)
var v5_leaves := _leaf_blocks(v5_world, sample_box, 60, 110)
h.greater(float(v4_leaves), 100.0, "the v4 leaf sample is non-empty")
h.greater(float(v5_leaves), 100.0, "the v5 leaf sample is non-empty")
h.less(float(v5_leaves), float(v4_leaves), "v5 crowns use fewer leaf blocks in the sample")
```

Add the chunk-boundary test:

```gdscript
h.section("M34 chunk boundary")
var generator := WorldGen.new(17017, 5)
var seam_tree := Vector2i.ZERO
var found := false
for z in range(-64, 1):
    for x in range(40, 57):
        var data := generator.tree_at(x, z)
        var type := int(data["type"])
        if not _is_tree(type):
            continue
        var radius := 3
        if _is_broadleaf(type):
            radius = int(data.get("canopy", 3))
        if x - radius <= 48 and x + radius >= 48:
            seam_tree = Vector2i(x, z)
            found = true
            break
    if found:
        break
h.check(found, "a v5 crown crosses the x=48 border")
if found:
    var height := generator.height_at(seam_tree.x, seam_tree.y)
    var coord := VoxelWorld.world_to_chunk(Vector3i(seam_tree.x, height, seam_tree.y))
    var coords: Array[Vector3i] = []
    for cy in range(maxi(0, coord.y - 1), mini(WorldGen.CHUNKS_Y, coord.y + 2)):
        for cz in range(coord.z - 1, coord.z + 2):
            for cx in range(coord.x - 1, coord.x + 2):
                coords.append(Vector3i(cx, cy, cz))
    var a := VoxelWorld.new(17017, 5)
    var b := VoxelWorld.new(17017, 5)
    for c: Vector3i in coords:
        a.ensure_chunk(c)
    for i in range(coords.size() - 1, -1, -1):
        b.ensure_chunk(coords[i])
    var mismatch := 0
    for c: Vector3i in coords:
        if (a.get_chunk(c) as ChunkData).blocks != (b.get_chunk(c) as ChunkData).blocks:
            mismatch += 1
    h.eq(mismatch, 0, "v5 chunks across the border match in both load orders")
```

- [ ] **Step 2: Run the unit suite and confirm failure**

Expected: FAIL because v5 still uses the M32 profile branch and there is no `PINNED_M34_HASH`.

- [ ] **Step 3: Add the v5 crown profile branch**

First change the profile count in `_place_broadleaf`:

```gdscript
var profile_count := 6 if _is_m34() else 4
var profile := _hash3(tree_world_x, top, tree_world_z, 73) % profile_count
```

Then, immediately after the `profile` assignment and before the existing `if terrain_version == LEGACY_VERSION` chain, add:

```gdscript
if _is_m34() and radius >= 3:
    match profile % 6:
        0: layer_radii = [0, 1, 2, 3, 3, 2, 1]
        1: layer_radii = [1, 1, 2, 3, 2, 2, 1]
        2: layer_radii = [0, 1, 2, 3, 2, 1, 1]
        3: layer_radii = [1, 2, 2, 3, 3, 1, 0]
        4: layer_radii = [1, 2, 3, 2, 3, 2, 1]
        _: layer_radii = [0, 1, 3, 2, 3, 2, 1]
elif _is_m34() and radius == 2:
    match profile % 4:
        0: layer_radii = [0, 1, 2, 2, 1, 0]
        1: layer_radii = [1, 1, 2, 2, 1, 1]
        2: layer_radii = [0, 1, 2, 1, 2, 1]
        _: layer_radii = [1, 2, 2, 1, 1, 0]
```

Keep the existing `_is_m32()` branches below for v4. Add the trim divisors next to the profile variables:

```gdscript
var corner_divisor := 3 if _is_m34() else (2 if _is_m32() else 3)
var edge_divisor := 3 if _is_m34() else (4 if _is_m32() else 5)
```

Use `corner_divisor` in the corner `_hash3(...) % ... != 0` check and `edge_divisor` in the edge `_hash3(...) % ... == 0` check, replacing the inline conditionals. For v5 this keeps one third of corner cells and trims one third of edge cells (two thirds survive).

Add the emergent cap for v5. `_place_broadleaf` already knows `tree_world_x`, `tree_world_z`, `base` and `top`; recompute the same class deterministically rather than changing the function signature or every call site:

```gdscript
var height_class := 0
if _is_m34():
    var crown_patch := _forest_patches.get_noise_2d(tree_world_x, tree_world_z)
    height_class = _v5_height_class(tree_world_x, tree_world_z, base - 1, crown_patch)
```

Place this near the other per-tree hash values. After the existing top leaf at `top + 2`, add

```gdscript
if _is_m34() and height_class == 1:
    _place_block(chunk, local_x, top + 3, local_z, leaf_block, base_y, true)
```

This recomputation uses the same `ground = base - 1` and patch as `_oak`/`_birch`/`_blossom`, so the voxel crown and the tree dictionary agree without touching `_place_oak`, `_place_birch`, `_place_blossom`, `_generate_trees` or `plant_tree` signatures.

- [ ] **Step 4: Run the unit suite and pin v5**

Run the unit suite. Then measure the v5 region hash with the new test helper or `wilderness_probe.gd --fingerprint`, add `const PINNED_M34_HASH := <measured>` and assert `h.eq(_region_hash(5), PINNED_M34_HASH, "version 5 output is pinned")`. Re-run the suite.

Expected: PASS, including the v5 pin and boundary test.

- [ ] **Step 5: Update the diagnosis file**

Run the v5 probe and append the actual v5 measurements to `m34-diagnosis.txt` with the command and date. Do not overwrite the v4 baseline. Record the v5 pin.

- [ ] **Step 6: Commit**

```powershell
git add prototypes/m17/godot/scripts/core/world_gen.gd prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd prototypes/m17/results/godot/m34-diagnosis.txt
git commit -m "M34: add v5 crown silhouettes and pin v5 generation"
```

---

### Task 5: Ecology, persistence and full regression verification

**Files:**
- Modify: `prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd` (if a v5-specific ecology assertion is missing)
- Verify: existing `test_m33_vegetation.gd`, `test_m32_landscape.gd`, `test_generation.gd`, `test_persistence.gd`, `test_streaming_lifecycle.gd`, `test_starter_house.gd`

**Interfaces:**
- Consumes: v5 generator from Tasks 1–4.
- Produces: full-suite evidence and any v5 ecology/save assertions required by the spec.

- [ ] **Step 1: Add the remaining v5 ecology/save tests**

In `test_m34_canopy_composition.gd`, add a sample loop over `[-192,192]` step 1 and assert:

```gdscript
h.section("M34 v5 mountain and river")
var above30_broadleaf := 0
var band27_30_columns := 0
var band27_30_broadleaf := 0
var above40_columns := 0
var above40_trees := 0
var above44_trees := 0
var upper_slope_trees := 0
var upper_slope_non_pine := 0
var river_core_columns := 0
var river_core_trees := 0
var river_outer_columns := 0
var river_outer_trees := 0
for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
    for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
        var height := v5.height_at(x, z)
        var biome := v5.biome_at(x, z)
        var type := int(v5.tree_at(x, z)["type"])
        var tree := _is_tree(type)
        if _is_broadleaf(type) and height > SEA + 30:
            above30_broadleaf += 1
        if height > SEA + 27 and height <= SEA + 30:
            band27_30_columns += 1
            if _is_broadleaf(type):
                band27_30_broadleaf += 1
        if height > SEA + 40:
            above40_columns += 1
            if tree:
                above40_trees += 1
        if height > SEA + 44 and tree:
            above44_trees += 1
        if tree and height > SEA + 30 and height <= SEA + 40:
            upper_slope_trees += 1
            if type != WorldGen.TreeType.PINE:
                upper_slope_non_pine += 1
        var distance := v5._river_distance(x, z)
        if distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
            river_core_columns += 1
            if tree:
                river_core_trees += 1
        elif distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER:
            river_outer_columns += 1
            if tree:
                river_outer_trees += 1
h.eq(above30_broadleaf, 0, "no broadleaf above SEA+30")
h.greater(float(band27_30_columns), 100.0, "the broadleaf treeline band has a sample")
h.less(float(band27_30_broadleaf) / maxf(1.0, float(band27_30_columns)), 0.02,
    "broadleaf is <=2%% in SEA+27..30")
h.greater(float(above40_columns), 100.0, "the summit sample has enough columns")
h.less(float(above40_trees) / maxf(1.0, float(above40_columns)), 0.02,
    "tree coverage above SEA+40 is <2%%")
h.eq(above44_trees, 0, "no tree above SEA+44")
h.greater(float(upper_slope_trees), 10.0, "the upper slope has trees")
h.eq(upper_slope_non_pine, 0, "upper slopes are pine only")
h.greater(float(river_core_columns), 100.0, "the river core has a sample")
h.eq(river_core_trees, 0, "the river core has no trees")
h.greater(float(river_outer_columns), 100.0, "the river outer band has a sample")
h.greater(float(river_outer_trees) / maxf(1.0, float(river_outer_columns)), 0.005,
    "river-outer vegetation is retained")
h.less(float(river_outer_trees) / maxf(1.0, float(river_outer_columns)), 0.20,
    "river-outer vegetation stays below 20%%")
```

For the save/edit round-trip, reuse the `SaveManager.to_dictionary` / `apply` pattern from `test_persistence.gd`: place a block in a v5 world, save, apply into a fresh v5 world, and assert the edited block and `terrain_generator_version == 5`. Also assert a v4 payload still records 4. Do not duplicate the full persistence fixture.

- [ ] **Step 2: Run the unit suite**

Run the unit command. Expected: `M17_TESTS_PASS`, exit 0. Record the assertion count.

- [ ] **Step 3: Run integration and regression**

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
& 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --headless --path prototypes/m17/godot --script res://scripts/regression.gd
```

Expected: `M17_INTEGRATION_PASS` and `M17_REGRESSION_PASS`, exit 0.

- [ ] **Step 4: Run the smoke test twice**

```powershell
& 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --headless --path prototypes/m17/godot -- --straight-to-game --seed=17017 --render-distance=6 --quit-after=30
```

Run twice; compare `world_hash`, `faces_hash`, `faces`, `edits`. They must match between runs.

- [ ] **Step 5: Fix failures and re-run**

If an existing test fails because of an intentional v5 change, update only the version-specific expectation; do not weaken the M33 v4 tests or the historical pins. Re-run the affected suite and then the full unit suite.

- [ ] **Step 6: Commit**

```powershell
git add prototypes/m17/godot/scripts/tests/test_m34_canopy_composition.gd
git commit -m "M34: verify v5 ecology, persistence and regressions"
```

---

### Task 6: Visual evidence, performance, report and independent review

**Files:**
- Create: `prototypes/m17/results/godot/m34-before-*.png`, `m34-after-*.png`, `m34-*.json`
- Create: `prototypes/m17/results/godot/m34-verification.txt`
- Create: `prototypes/m17/results/godot/m34-report.md`

**Interfaces:**
- Consumes: v5 game and v4 M33 worktree for matched before captures.
- Produces: visual/performance evidence and the final report.

- [ ] **Step 1: Capture matched before/after images**

From the M33 worktree (v4) and the M34 worktree (v5), use the same seed 17017, render radius 6, `--fly`, `--hide-hud`, `--settle=25`, 1280×720, time 0.28. Capture:

- `224,92,288`, yaw 75, pitch −24;
- `224,110,288`, yaw 75, pitch −35;
- `-7.3,101.5,-29`, yaw 270, pitch −12;
- `80,72,160`, yaw 90, pitch −8;
- `76,140,-40`, yaw 180, pitch −14;
- `80,92,180`, yaw 0, pitch −25;
- `80,72,160`, yaw 0, pitch −8;
- `224,74,288`, yaw 90, pitch 0.

Use `--shots` or one run per camera. Save as `m34-before-*.png` and `m34-after-*.png`.

- [ ] **Step 2: Inspect the images directly**

Check the spec's per-shot checklist. Do not declare success from density tests. If the elevated view still reads as a continuous slab, revise within the spec (crown radius, trim, woodland keep 4/9–5/9) and re-capture.

- [ ] **Step 3: Measure performance**

From M33 (v4) and M34 (v5), run `run_perf.gd` three times per camera at:

- normal `-7.3,101.5,-29`, yaw 270, pitch −12;
- river `80,92,180`, yaw 0, pitch −25.

Record medians/ranges for FPS, p95/p99, 1% low, worst frame, draw calls, generation/mesh totals, loaded/wanted/queued/in-flight. Investigate a >5% median FPS drop or >10% p99 increase.

- [ ] **Step 4: Write the verification summary and report**

`m34-verification.txt`: branch, worktree, base commit, commands, unit/integration/regression counts, smoke hashes, v0–v5 pins, v5 distribution metrics, performance medians, evidence paths.

`m34-report.md`: status, preflight, root causes, implementation, measured composition, visual evidence with cameras, performance, verification, independent review verdict, limitations, files/commits.

- [ ] **Step 5: Run independent code review**

Dispatch the read-only Reviewer with `ACTIVE MILESTONE: M34`, the spec, plan, diff, tests, captures, performance data and report. Resolve every blocking finding, re-run the affected verification, and repeat until the Reviewer returns PASS.

- [ ] **Step 6: Commit**

```powershell
git add prototypes/m17/results/godot/m34-* prototypes/m17/results/godot/m34-report.md
git commit -m "M34: add visual and performance evidence"
git add prototypes/m17/results/godot/m34-report.md
git commit -m "M34: record final review and report"
```

---

## Self-Review

- **Spec coverage:** D1 → Task 1; D2 → Task 2; D3/D4 → Tasks 3–4; D5 → Tasks 2–3; D6 → Task 5; D7 → Tasks 1, 4, 5; performance/visual → Task 6. Tests 1–24 map to Tasks 1–5.
- **Step scan:** Each task has a failing test, implementation, passing run and commit. The plan leaves function bodies to the implementer where the signature and tests determine them.
- **Type consistency:** `M34_VERSION`, `M34_GROVE_PATCH`, `M34_WOODLAND_KEEP`, `_is_m34`, `_forest_canopy_tree_v5`, `_v5_height_class`, `height_class` are used consistently.
- **Review Focus:** Dense-grove preservation, v4 streaming, chunk borders, speckle and mountain/river preservation each have a test or capture.
- **Proportion:** The plan is task-level, not a transcript of the implementation.
