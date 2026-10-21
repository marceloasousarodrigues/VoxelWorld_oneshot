extends RefCounted

## M34 canopy composition: v5 version plumbing, deterministic placement,
## crown variation, overlap reduction, dense-grove preservation and ecology.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const SEA := WorldGen.SEA_LEVEL
const SAMPLE_RADIUS := 192
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)


func name() -> String:
	return "M34 canopy composition"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


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


func _full_cell_stats(generator: WorldGen) -> Dictionary:
	var cells := {}
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var key := Vector2i(floori(float(x) / 32.0), floori(float(z) / 32.0))
			var entry: Dictionary = cells.get(key, {"all": 0, "forest": 0, "trees": 0})
			entry["all"] = int(entry["all"]) + 1
			if generator.biome_at(x, z) == WorldGen.Biome.FOREST:
				entry["forest"] = int(entry["forest"]) + 1
				if _is_tree(int(generator.tree_at(x, z)["type"])):
					entry["trees"] = int(entry["trees"]) + 1
			cells[key] = entry
	var coverages: Array[float] = []
	var dense8 := 0
	var dense12 := 0
	for key: Vector2i in cells:
		var entry: Dictionary = cells[key]
		if int(entry["all"]) < 512 or int(entry["forest"]) < 256:
			continue
		var coverage := float(entry["trees"]) / float(entry["forest"])
		coverages.append(coverage)
		if coverage >= 0.08:
			dense8 += 1
		if coverage >= 0.12:
			dense12 += 1
	coverages.sort()
	return {
		"p50": _percentile(coverages, 0.50),
		"p90": _percentile(coverages, 0.90),
		"max": coverages[coverages.size() - 1] if not coverages.is_empty() else 0.0,
		"dense8": dense8,
		"dense12": dense12,
	}


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

	h.section("M34 forest composition")
	h.check(_region_hash(5) != PINNED_M33_HASH, "version 5 placement differs from version 4")
	h.eq(WorldGen.M34_GROVE_PATCH, 0.34, "dense-grove patch threshold matches M33")
	h.eq(WorldGen.M34_WOODLAND_KEEP, 4, "open woodland keeps four of nine candidates")
	var lowland_v4 := _forest_coverage(v4, LOWLAND_BOX)
	var lowland_v5 := _forest_coverage(v5, LOWLAND_BOX)
	var canopy_v4 := _forest_coverage(v4, LOWLAND_CANOPY_BOX)
	var canopy_v5 := _forest_coverage(v5, LOWLAND_CANOPY_BOX)
	h.greater(lowland_v5, 0.045, "dense lowland forest keeps >=4.5%% trunk coverage (%.3f)" % lowland_v5)
	h.less(lowland_v5, 0.13, "dense lowland forest is not a solid carpet (%.3f)" % lowland_v5)
	h.greater(canopy_v5, 0.03, "open woodland keeps >=3%% trunk coverage (%.3f)" % canopy_v5)
	h.less(canopy_v5, 0.085, "open woodland is not a tree carpet (%.3f)" % canopy_v5)
	h.less(canopy_v5, canopy_v4, "open woodland is thinner than v4 (%.3f vs %.3f)" % [canopy_v5, canopy_v4])
	h.greater(lowland_v5, 0.04, "dense lowland trunk coverage is not blanket-thinned")
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
	var cell_stats := _full_cell_stats(v5)
	h.less(cell_stats["p50"], 0.08, "full forest-cell p50 is <=8%%")
	h.greater(cell_stats["p90"], 0.09, "full forest-cell p90 is >=9%%")
	h.greater(cell_stats["max"], 0.18, "full forest-cell max is >=18%%")
	h.greater(float(cell_stats["dense8"]), 4.0, "at least five full cells are >=8%%")
	h.greater(float(cell_stats["dense12"]), 1.0, "at least two full cells are >=12%%")

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

	h.section("M34 clearings")
	var forest_columns := 0
	var clearing_columns := 0
	var clearing_trees := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			if v5.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
			if v5._vegetation_score(x, z) < WorldGen.M33_CLEARING_SCORE:
				clearing_columns += 1
				if _is_tree(int(v5.tree_at(x, z)["type"])):
					clearing_trees += 1
	h.eq(clearing_trees, 0, "designated clearings contain no trees")
	h.greater(float(clearing_columns), float(forest_columns) * 0.20,
		"at least 20%% of forest columns are clearings")
	h.finish()
