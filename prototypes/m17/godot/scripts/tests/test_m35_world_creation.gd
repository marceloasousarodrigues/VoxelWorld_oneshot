extends RefCounted

## M35/M36 world creation: v6/v7 forest spacing, v7 treeline and canopy ceiling.
## v5 remains the M34 canopy baseline; v6/v7 only change tree placement/height.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const PINNED_M34_HASH := 5133898688464144157
const PINNED_M35_HASH := 9184026728463986701
const PINNED_M36_HASH := 5732396842800747576
const SEA := WorldGen.SEA_LEVEL
const SAMPLE_RADIUS := 192
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)


func name() -> String:
	return "M35 world creation and treeline"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func _is_tree(type: int) -> bool:
	return type != WorldGen.TreeType.NONE


func _is_broadleaf(type: int) -> bool:
	return type == WorldGen.TreeType.OAK or type == WorldGen.TreeType.BIRCH \
		or type == WorldGen.TreeType.BLOSSOM


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


func run(h: TestHarness) -> void:
	h.section("M35/M36 generator versions")
	h.eq(WorldGen.M34_VERSION, 5, "the M34 canopy generator remains version 5")
	h.eq(WorldGen.M35_VERSION, 6, "the forest-spacing pass is version 6")
	h.eq(WorldGen.M36_VERSION, 7, "the treeline/canopy pass is version 7")
	h.eq(WorldGen.CURRENT_VERSION, 7, "new worlds use the M36 generator")
	for version in range(0, WorldGen.CURRENT_VERSION + 1):
		h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
	h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1),
		"a future version is rejected")

	h.eq(_region_hash(0), PINNED_LEGACY_HASH, "version 0 remains pinned")
	h.eq(_region_hash(1), PINNED_M30_HASH, "version 1 remains pinned")
	h.eq(_region_hash(2), PINNED_M31_HASH, "version 2 remains pinned")
	h.eq(_region_hash(3), PINNED_M32_HASH, "version 3 remains pinned")
	h.eq(_region_hash(4), PINNED_M33_HASH, "version 4 remains pinned")
	h.eq(_region_hash(5), PINNED_M34_HASH, "version 5 remains pinned")
	var v6_a := _region_hash(6)
	var v6_b := _region_hash(6)
	var v7_a := _region_hash(7)
	var v7_b := _region_hash(7)
	h.eq(v6_a, v6_b, "version 6 generation is deterministic")
	h.eq(v7_a, v7_b, "version 7 generation is deterministic")
	h.eq(v6_a, PINNED_M35_HASH, "version 6 output is pinned")
	h.eq(v7_a, PINNED_M36_HASH, "version 7 output is pinned")
	h.check(v6_a != PINNED_M34_HASH, "version 6 vegetation differs from version 5")
	h.check(v7_a != v6_a, "version 7 vegetation differs from version 6")

	var v4 := WorldGen.new(17017, 4)
	var v5 := WorldGen.new(17017, 5)
	var v6 := WorldGen.new(17017, 6)
	var v7 := WorldGen.new(17017, 7)
	var height_mismatch := 0
	var biome_mismatch := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
			if v4.height_at(x, z) != v7.height_at(x, z):
				height_mismatch += 1
			if v4.biome_at(x, z) != v7.biome_at(x, z):
				biome_mismatch += 1
	h.eq(height_mismatch, 0, "v7 heights equal v4")
	h.eq(biome_mismatch, 0, "v7 biomes equal v4")

	h.section("M35/M36 forest spacing")
	var v5_coverage := _forest_coverage(v5, LOWLAND_BOX)
	var v6_coverage := _forest_coverage(v6, LOWLAND_BOX)
	var v7_coverage := _forest_coverage(v7, LOWLAND_BOX)
	h.check(v5_coverage >= v6_coverage, "v6 is no denser than v5 in the lowland sample")
	h.greater(v6_coverage, v7_coverage, "v7 is more open than v6")
	var v5_global := 0
	var v6_global := 0
	var v7_global := 0
	var forest_columns := 0
	var dense_columns := 0
	var dense_v5 := 0
	var dense_v6 := 0
	var dense_v7 := 0
	var open_low_v6 := 0
	var open_low_v7 := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			if v7.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
			var t5 := _is_tree(int(v5.tree_at(x, z)["type"]))
			var t6 := _is_tree(int(v6.tree_at(x, z)["type"]))
			var t7 := _is_tree(int(v7.tree_at(x, z)["type"]))
			v5_global += 1 if t5 else 0
			v6_global += 1 if t6 else 0
			v7_global += 1 if t7 else 0
			var patch := v7._forest_patches.get_noise_2d(x, z)
			if patch > WorldGen.M34_GROVE_PATCH:
				dense_columns += 1
				dense_v5 += 1 if t5 else 0
				dense_v6 += 1 if t6 else 0
				dense_v7 += 1 if t7 else 0
			elif v7.height_at(x, z) <= SEA + 8:
				open_low_v6 += 1 if t6 else 0
				open_low_v7 += 1 if t7 else 0
	h.greater(float(forest_columns), 10000.0, "the global forest sample is large")
	h.greater(float(v5_global), float(v6_global), "v6 opens the global forest")
	h.greater(float(v6_global), float(v7_global), "v7 opens the global forest further")
	h.greater(float(dense_columns), 1000.0, "the dense-grove sample is large")
	h.greater(float(dense_v5), float(dense_v6), "v6 thins dense groves")
	h.greater(float(dense_v6), float(dense_v7), "v7 thins dense groves further")
	h.eq(open_low_v6, open_low_v7, "v6 and v7 keep the same open-woodland placement")

	var v5_stats := _crown_stats(v5, LOWLAND_CANOPY_BOX)
	var v7_stats := _crown_stats(v7, LOWLAND_CANOPY_BOX)
	h.greater(v7_stats["open"], v5_stats["open"], "v7 has more crown-free forest columns")
	h.less(v7_stats["multi"], v5_stats["multi"], "v7 reduces 2+ crown overlap")
	h.less(v7_stats["triple"], v5_stats["triple"], "v7 reduces 3+ crown overlap")
	h.greater(v7_stats["open"], 0.44, "v7 open woodland is at least 44%% crown-free")
	h.greater(v7_stats["spacing_p50"], 1.9, "v7 median trunk spacing is >=1.9")

	h.section("M35/M36 treeline")
	var max_root := -1
	var max_top := -1
	var above_root := 0
	var above_top := 0
	var trees_seen := 0
	var v5_above_root := 0
	var v6_above_root := 0
	var v6_above_top := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var v5_tree := v5.tree_at(x, z)
			if _is_tree(int(v5_tree["type"])) \
					and int(v5_tree["base"]) - 1 > WorldGen.M35_TREELINE_LIMIT:
				v5_above_root += 1
			var v6_tree := v6.tree_at(x, z)
			if _is_tree(int(v6_tree["type"])):
				if int(v6_tree["base"]) - 1 > WorldGen.M35_TREELINE_LIMIT:
					v6_above_root += 1
				if v6._tree_top_y(v6_tree) > WorldGen.M36_CANOPY_CEILING:
					v6_above_top += 1
			var tree := v7.tree_at(x, z)
			if not _is_tree(int(tree["type"])):
				continue
			trees_seen += 1
			var root := int(tree["base"]) - 1
			var top := v7._tree_top_y(tree)
			max_root = maxi(max_root, root)
			max_top = maxi(max_top, top)
			if root > WorldGen.M35_TREELINE_LIMIT:
				above_root += 1
			if top > WorldGen.M36_CANOPY_CEILING:
				above_top += 1
	h.greater(float(trees_seen), 100.0, "the v7 treeline sample contains trees")
	h.eq(WorldGen.M35_TREELINE_LIMIT, SEA + 24, "the v7 root treeline is SEA+24")
	h.eq(WorldGen.M36_CANOPY_CEILING, SEA + 30, "the v7 canopy ceiling is SEA+30")
	h.eq(above_root, 0, "no v7 tree root is above the treeline")
	h.eq(above_top, 0, "no v7 tree top is above the canopy ceiling")
	h.less(float(max_root), float(WorldGen.M35_TREELINE_LIMIT) + 1.0,
		"the highest v7 root is at or below the treeline")
	h.less(float(max_top), float(WorldGen.M36_CANOPY_CEILING) + 1.0,
		"the highest v7 full tree top is at or below the ceiling")
	h.greater(float(v5_above_root), 0.0,
		"v5 had trees rooted above the v7 treeline, so the treeline is a real change")
	h.eq(v6_above_root, 0, "v6 removes roots above the treeline")
	h.greater(float(v6_above_top), 0.0,
		"v6 still allowed crowns above the ceiling; v7 closes that gap")
	h.eq(above_top, 0, "v7 removes the crowns v6 still allowed above the ceiling")

	h.section("M35/M36 river and boundaries")
	var river_core := 0
	var river_core_trees := 0
	var river_outer := 0
	var river_outer_trees := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var distance := v7._river_distance(x, z)
			var tree := _is_tree(int(v7.tree_at(x, z)["type"]))
			if distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				river_core += 1
				river_core_trees += 1 if tree else 0
			elif distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER:
				river_outer += 1
				river_outer_trees += 1 if tree else 0
	h.greater(float(river_core), 100.0, "the river core sample is large")
	h.eq(river_core_trees, 0, "the v7 river core has no trees")
	h.greater(float(river_outer), 100.0, "the river outer sample is large")
	h.greater(float(river_outer_trees) / maxf(1.0, float(river_outer)), 0.005,
		"the v7 river outer band retains vegetation")

	var seam_generator := WorldGen.new(17017, 7)
	var found := false
	for z in range(-64, 1):
		for x in range(40, 57):
			var data := seam_generator.tree_at(x, z)
			if not _is_tree(int(data["type"])):
				continue
			var radius := _crown_radius(data)
			if x - radius <= 48 and x + radius >= 48:
				found = true
				break
		if found:
			break
	h.check(found, "a v7 crown crosses the x=48 border")
	var a := VoxelWorld.new(17017, 7)
	var b := VoxelWorld.new(17017, 7)
	var coords: Array[Vector3i] = []
	for cy in range(0, 7):
		for cz in range(2, 5):
			for cx in range(2, 5):
				coords.append(Vector3i(cx, cy, cz))
	for c: Vector3i in coords:
		a.ensure_chunk(c)
	for i in range(coords.size() - 1, -1, -1):
		b.ensure_chunk(coords[i])
	var mismatch := 0
	for c: Vector3i in coords:
		if (a.get_chunk(c) as ChunkData).blocks != (b.get_chunk(c) as ChunkData).blocks:
			mismatch += 1
	h.eq(mismatch, 0, "v7 chunks match across both load orders")

	h.section("M35/M36 save")
	var world := VoxelWorld.new(17017, 7)
	world.ensure_chunk(Vector3i(0, 4, 0))
	var save := SaveManager.new()
	var payload: Dictionary = save.to_dictionary(world, null, Inventory.new())
	h.eq(int(payload["terrain_generator_version"]), 7, "a v7 save records generator 7")
	h.finish()
