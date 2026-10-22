extends RefCounted

## M33 vegetation ecology: version pins, deterministic placement, elevation and
## slope limits, clearings, river rules and loaded-save compatibility.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const SAMPLE_RADIUS := 192
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)
const SEA := WorldGen.SEA_LEVEL

var _gen: WorldGen
var _heights := PackedInt32Array()
var _biomes := PackedByteArray()
var _types := PackedByteArray()
var _slopes := PackedByteArray()
var _scores := PackedFloat32Array()


func name() -> String:
	return "M33 vegetation ecology"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func _ensure_sample() -> void:
	if not _heights.is_empty():
		return
	_gen = WorldGen.new(17017, WorldGen.M33_VERSION)
	var span := SAMPLE_RADIUS * 2 + 1
	var total := span * span
	_heights.resize(total)
	_biomes.resize(total)
	_types.resize(total)
	_slopes.resize(total)
	_scores.resize(total)
	var index := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var height := _gen.height_at(x, z)
			_heights[index] = height
			_biomes[index] = _gen.biome_at(x, z)
			_types[index] = int(_gen.tree_at(x, z)["type"])
			_slopes[index] = mini(4, _gen._column_slope(x, z, height))
			_scores[index] = _gen._vegetation_score(x, z)
			index += 1


func _sample_x(index: int) -> int:
	var span := SAMPLE_RADIUS * 2 + 1
	return -SAMPLE_RADIUS + index % span


func _sample_z(index: int) -> int:
	var span := SAMPLE_RADIUS * 2 + 1
	return -SAMPLE_RADIUS + index / span


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


func run(h: TestHarness) -> void:
	_ensure_sample()
	h.section("M33 generator versions")
	h.eq(WorldGen.M33_VERSION, 4, "the M33 vegetation generator is version 4")
	h.eq(WorldGen.CURRENT_VERSION, 7, "new worlds use the current M36 generator")
	for version in range(0, WorldGen.CURRENT_VERSION + 1):
		h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
	h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1), "a future version is rejected")
	h.check(not WorldGen.is_supported_version(-1), "a negative version is rejected")

	h.eq(_region_hash(0), PINNED_LEGACY_HASH,
		"version 0 terrain is byte-identical to the pinned M29 output")
	h.eq(_region_hash(1), PINNED_M30_HASH,
		"version 1 terrain is byte-identical to the pinned M30 output")
	h.eq(_region_hash(2), PINNED_M31_HASH,
		"version 2 terrain is byte-identical to the pinned M31 output")
	h.eq(_region_hash(3), PINNED_M32_HASH,
		"version 3 generation is byte-identical to the pinned M32 output")
	var v4_a := _region_hash(4)
	var v4_b := _region_hash(4)
	h.eq(v4_a, v4_b, "version 4 generation is deterministic")
	h.eq(v4_a, PINNED_M33_HASH, "version 4 output is pinned")
	h.check(v4_a != PINNED_M32_HASH, "version 4 vegetation differs from version 3")

	_test_terrain_equality(h)
	_test_determinism(h)
	_test_broadleaf_limit(h)
	_test_summit(h)
	_test_lowland(h)
	_test_variation(h)
	_test_steep(h)
	_test_clearings(h)
	_test_river(h)
	_test_species(h)
	_test_chunk_boundary(h)
	_test_save(h)
	h.finish()


func _test_terrain_equality(h: TestHarness) -> void:
	h.section("M33 terrain compatibility")
	var v3 := WorldGen.new(17017, 3)
	var v4 := WorldGen.new(17017, 4)
	var height_mismatch := 0
	var biome_mismatch := 0
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1, 4):
			if v3.height_at(x, z) != v4.height_at(x, z):
				height_mismatch += 1
			if v3.biome_at(x, z) != v4.biome_at(x, z):
				biome_mismatch += 1
	h.eq(height_mismatch, 0, "v4 heights are identical to v3")
	h.eq(biome_mismatch, 0, "v4 biomes are identical to v3")


func _test_determinism(h: TestHarness) -> void:
	h.section("M33 deterministic trees")
	var a := WorldGen.new(17017, 4)
	var b := WorldGen.new(17017, 4)
	var different := 0
	for z in range(-64, 65, 2):
		for x in range(-64, 65, 2):
			if int(a.tree_at(x, z)["type"]) != int(b.tree_at(x, z)["type"]):
				different += 1
	h.eq(different, 0, "two v4 generators place identical trees")
	var flipped := WorldGen.new(424242, 4)
	var any := false
	for z in range(-32, 33, 4):
		for x in range(-32, 33, 4):
			if int(a.tree_at(x, z)["type"]) != int(flipped.tree_at(x, z)["type"]):
				any = true
	h.check(any, "a different seed produces a different vegetation layout")


func _test_broadleaf_limit(h: TestHarness) -> void:
	h.section("M33 broadleaf elevation limit")
	var above := 0
	var band_columns := 0
	var band_broadleaf := 0
	for index in _heights.size():
		var height := _heights[index]
		if _is_broadleaf(_types[index]) and height > SEA + 30:
			above += 1
		if height > SEA + 27 and height <= SEA + 30:
			band_columns += 1
			if _is_broadleaf(_types[index]):
				band_broadleaf += 1
	h.eq(above, 0, "no broadleaf tree exists above SEA+30")
	h.greater(float(band_columns), 100.0, "the broadleaf treeline band has a real sample")
	h.less(float(band_broadleaf) / maxf(1.0, float(band_columns)), 0.02,
		"broadleaf is <=2%% of columns in SEA+27..30 (%d/%d)" % [band_broadleaf, band_columns])


func _test_summit(h: TestHarness) -> void:
	h.section("M33 summit sparsity")
	var above40_columns := 0
	var above40_trees := 0
	var above40_broadleaf := 0
	var above44_trees := 0
	for index in _heights.size():
		var height := _heights[index]
		if height > SEA + 40:
			above40_columns += 1
			if _is_tree(_types[index]):
				above40_trees += 1
			if _is_broadleaf(_types[index]):
				above40_broadleaf += 1
		if height > SEA + 44 and _is_tree(_types[index]):
			above44_trees += 1
	h.greater(float(above40_columns), 100.0, "the summit sample has enough columns")
	h.less(float(above40_trees) / maxf(1.0, float(above40_columns)), 0.02,
		"above SEA+40 tree coverage is <2%% (%d/%d)" % [above40_trees, above40_columns])
	h.eq(above40_broadleaf, 0, "no broadleaf tree exists above SEA+40")
	h.eq(above44_trees, 0, "no tree exists above SEA+44")


func _test_lowland(h: TestHarness) -> void:
	h.section("M33 lowland forest")
	var columns := 0
	var trees := 0
	var species := {}
	for z in range(LOWLAND_BOX.position.y, LOWLAND_BOX.end.y):
		for x in range(LOWLAND_BOX.position.x, LOWLAND_BOX.end.x):
			if _gen.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			columns += 1
			var type := int(_gen.tree_at(x, z)["type"])
			if _is_tree(type):
				trees += 1
				species[type] = int(species.get(type, 0)) + 1
	var coverage := float(trees) / maxf(1.0, float(columns))
	h.greater(float(columns), 500.0, "the lowland box has a real forest sample")
	h.greater(coverage, 0.06, "lowland forest keeps >=6%% tree coverage (%.3f)" % coverage)
	h.less(coverage, 0.20, "lowland forest is not a solid tree carpet (%.3f)" % coverage)
	h.check(species.has(WorldGen.TreeType.OAK), "lowland forest contains oaks")
	h.check(species.has(WorldGen.TreeType.BIRCH), "lowland forest contains birches")
	h.check(species.has(WorldGen.TreeType.PINE), "lowland forest contains pines")
	h.check(species.has(WorldGen.TreeType.BLOSSOM), "lowland forest contains blossom trees")


func _test_variation(h: TestHarness) -> void:
	h.section("M33 spatial variation")
	var cells := {}
	for z in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
		for x in range(-SAMPLE_RADIUS, SAMPLE_RADIUS + 1):
			var cell := Vector2i(floori(float(x) / 32.0), floori(float(z) / 32.0))
			var entry: Dictionary = cells.get(cell, {"columns": 0, "trees": 0})
			entry["columns"] = int(entry["columns"]) + 1
			var type := int(_gen.tree_at(x, z)["type"])
			entry["trees"] = int(entry["trees"]) + (1 if _is_tree(type) else 0)
			cells[cell] = entry
	var values: Array[float] = []
	var low := 0
	var dense8 := 0
	var dense12 := 0
	for key: Vector2i in cells:
		var entry: Dictionary = cells[key]
		var coverage := float(entry["trees"]) / maxf(1.0, float(entry["columns"]))
		values.append(coverage)
		if coverage <= 0.01:
			low += 1
		if coverage >= 0.08:
			dense8 += 1
		if coverage >= 0.12:
			dense12 += 1
	values.sort()
	h.greater(float(values.size()), 10.0, "the variation sample has enough cells")
	h.less(_percentile(values, 0.10), 0.02, "p10 cell coverage is <=2%%")
	h.less(_percentile(values, 0.50), 0.06, "p50 cell coverage is <=6%%")
	h.greater(_percentile(values, 0.90), 0.08, "p90 cell coverage is >=8%%")
	h.greater(values[values.size() - 1], 0.12, "the densest cell is >=12%%")
	h.greater(float(low), 5.0, "at least five cells are effectively open")
	h.greater(float(dense8), 5.0, "at least five cells are dense forest")
	h.greater(float(dense12), 3.0, "at least three cells are very dense forest")


func _test_steep(h: TestHarness) -> void:
	h.section("M33 steep terrain")
	var flat := 0
	var flat_trees := 0
	var steep := 0
	var steep_trees := 0
	for index in _heights.size():
		if _biomes[index] != WorldGen.Biome.FOREST or _heights[index] > SEA + 30:
			continue
		if _slopes[index] <= 1:
			flat += 1
			if _is_tree(_types[index]):
				flat_trees += 1
		elif _slopes[index] >= 3:
			steep += 1
			if _is_tree(_types[index]):
				steep_trees += 1
	h.greater(float(flat), 100.0, "the flat forest class has enough samples")
	h.greater(float(steep), 100.0, "the steep forest class has enough samples")
	var flat_coverage := float(flat_trees) / maxf(1.0, float(flat))
	var steep_coverage := float(steep_trees) / maxf(1.0, float(steep))
	h.less(steep_coverage, flat_coverage * 0.5,
		"steep forest coverage is <50%% of flat coverage (%.3f vs %.3f)" % [steep_coverage, flat_coverage])


func _test_clearings(h: TestHarness) -> void:
	h.section("M33 clearings")
	var forest_columns := 0
	var clearing_columns := 0
	var clearing_trees := 0
	for index in _heights.size():
		if _biomes[index] != WorldGen.Biome.FOREST:
			continue
		forest_columns += 1
		if _scores[index] < WorldGen.M33_CLEARING_SCORE:
			clearing_columns += 1
			if _is_tree(_types[index]):
				clearing_trees += 1
	h.eq(clearing_trees, 0, "designated clearings contain no tree trunks")
	h.greater(float(clearing_columns), float(forest_columns) * 0.20,
		"at least 20%% of forest columns are clearings (%d/%d)" % [clearing_columns, forest_columns])
	var stats := _canopy_stats(_gen, LOWLAND_CANOPY_BOX)
	h.greater(float(stats["clearing_columns"]), 100.0, "the lowland canopy box has enough clearings")
	h.greater(float(stats["largest_open"]), 100.0,
		"a connected crown-free opening of >=100 columns exists")
	h.greater(float(stats["clearing_open_ratio"]), 0.50,
		"at least half of the clearing columns are outside crowns")
	var clearing_samples := 0
	var clearing_decor := 0
	var clearing_flowers := 0
	for z in range(LOWLAND_CANOPY_BOX.position.y, LOWLAND_CANOPY_BOX.end.y):
		for x in range(LOWLAND_CANOPY_BOX.position.x, LOWLAND_CANOPY_BOX.end.x):
			if _gen.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			if _gen._vegetation_score(x, z) >= WorldGen.M33_CLEARING_SCORE:
				continue
			clearing_samples += 1
			var height := _gen.height_at(x, z)
			var surface := _gen._surface_block(_gen.biome_at(x, z), height)
			if surface != BlockDB.GRASS and surface != BlockDB.DRY_GRASS:
				continue
			var deco := _gen.decoration_at(x, z, height, surface, _gen.biome_at(x, z))
			if deco != BlockDB.AIR:
				clearing_decor += 1
			if deco == BlockDB.FLOWER_RED or deco == BlockDB.FLOWER_YELLOW \
					or deco == BlockDB.FLOWER_BLUE or deco == BlockDB.TALL_GRASS:
				clearing_flowers += 1
	h.greater(float(clearing_samples), 100.0, "the clearing decor sample has enough columns")
	h.greater(float(clearing_decor), 0.0, "clearing columns receive ground decor")
	h.greater(float(clearing_flowers), 0.0, "clearing decor includes flowers or tall grass")


func _canopy_stats(generator: WorldGen, box: Rect2i) -> Dictionary:
	var covered := {}
	# Include crown lean/shelf and trees rooted just outside the box.
	for z in range(box.position.y - 9, box.end.y + 9):
		for x in range(box.position.x - 9, box.end.x + 9):
			var tree := generator.tree_at(x, z)
			var type := int(tree["type"])
			if not _is_tree(type):
				continue
			var radius := 5
			if _is_broadleaf(type):
				radius = int(tree.get("canopy", 3)) + 2
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if dx * dx + dz * dz > radius * radius:
						continue
					var probe := Vector2i(x + dx, z + dz)
					if box.has_point(probe):
						covered[probe] = true
	var open := {}
	var clearing := 0
	var clearing_open := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var cell := Vector2i(x, z)
			if not covered.has(cell):
				open[cell] = true
			if generator._vegetation_score(x, z) < WorldGen.M33_CLEARING_SCORE:
				clearing += 1
				if not covered.has(cell):
					clearing_open += 1
	var seen := {}
	var largest := 0
	for cell: Vector2i in open:
		if seen.has(cell):
			continue
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		var count := 0
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			count += 1
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbour: Vector2i = current + offset
				if open.has(neighbour) and not seen.has(neighbour):
					seen[neighbour] = true
					stack.append(neighbour)
		largest = maxi(largest, count)
	return {
		"clearing_columns": clearing,
		"clearing_open_ratio": float(clearing_open) / maxf(1.0, float(clearing)),
		"largest_open": largest,
	}


func _test_river(h: TestHarness) -> void:
	h.section("M33 river corridor")
	var core := 0
	var core_trees := 0
	var outer := 0
	var outer_trees := 0
	for index in _heights.size():
		var distance := _gen._river_distance(_sample_x(index), _sample_z(index))
		if distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
			core += 1
			if _is_tree(_types[index]):
				core_trees += 1
		elif distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER:
			outer += 1
			if _is_tree(_types[index]):
				outer_trees += 1
	h.greater(float(core), 100.0, "the river core sample has enough columns")
	h.greater(float(outer), 100.0, "the river outer sample has enough columns")
	h.eq(core_trees, 0, "the river core contains no trees in any biome")
	var outer_coverage := float(outer_trees) / maxf(1.0, float(outer))
	h.greater(outer_coverage, 0.005, "riverside vegetation is retained outside the core")
	h.less(outer_coverage, 0.20, "riverside vegetation stays below 20%%")


func _test_species(h: TestHarness) -> void:
	h.section("M33 species and upper slope")
	var upper := 0
	var upper_non_pine := 0
	for index in _heights.size():
		if _heights[index] <= SEA + 30 or _heights[index] > SEA + 40:
			continue
		if not _is_tree(_types[index]):
			continue
		upper += 1
		if _types[index] != WorldGen.TreeType.PINE:
			upper_non_pine += 1
	h.greater(float(upper), 10.0, "the upper-slope sample contains trees")
	h.eq(upper_non_pine, 0, "upper slopes contain pines only")
	var high_grass := 0
	var high_decor := 0
	var above40_decor := 0
	for index in _heights.size():
		if _heights[index] <= SEA + 30:
			continue
		var surface := _gen._surface_block(_biomes[index], _heights[index])
		if surface != BlockDB.GRASS and surface != BlockDB.DRY_GRASS:
			continue
		high_grass += 1
		var deco := _gen.decoration_at(_sample_x(index), _sample_z(index),
			_heights[index], surface, _biomes[index])
		if deco != BlockDB.AIR:
			high_decor += 1
			if _heights[index] > SEA + 40:
				above40_decor += 1
	h.greater(float(high_grass), 100.0, "the high-ground decor sample has enough columns")
	h.less(float(high_decor) / maxf(1.0, float(high_grass)), 0.20,
		"high ground keeps only sparse ground decor")
	h.eq(above40_decor, 0, "no ground decor exists above SEA+40")


func _test_chunk_boundary(h: TestHarness) -> void:
	h.section("M33 chunk boundary")
	var generator := WorldGen.new(17017, 4)
	var tree := Vector2i.ZERO
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
				tree = Vector2i(x, z)
				found = true
				break
		if found:
			break
	h.check(found, "a crown crosses the x=48 border for the seam fixture")
	if not found:
		return
	h.check(absi(tree.x - 48) <= 8, "the seam tree is within eight blocks of the border")
	var height := generator.height_at(tree.x, tree.y)
	var coord := VoxelWorld.world_to_chunk(Vector3i(tree.x, height, tree.y))
	var coords: Array[Vector3i] = []
	for cy in range(maxi(0, coord.y - 1), mini(WorldGen.CHUNKS_Y, coord.y + 2)):
		for cz in range(coord.z - 1, coord.z + 2):
			for cx in range(coord.x - 1, coord.x + 2):
				coords.append(Vector3i(cx, cy, cz))
	var a := VoxelWorld.new(17017, 4)
	var b := VoxelWorld.new(17017, 4)
	for c: Vector3i in coords:
		a.ensure_chunk(c)
	for i in range(coords.size() - 1, -1, -1):
		b.ensure_chunk(coords[i])
	var mismatch := 0
	for c: Vector3i in coords:
		if (a.get_chunk(c) as ChunkData).blocks != (b.get_chunk(c) as ChunkData).blocks:
			mismatch += 1
	h.eq(mismatch, 0, "chunks across the border match in both generation orders")


func _test_save(h: TestHarness) -> void:
	h.section("M33 save/version")
	var world := VoxelWorld.new(17017, 4)
	world.ensure_chunk(Vector3i(0, 4, 0))
	var save := SaveManager.new()
	var payload: Dictionary = save.to_dictionary(world, null, Inventory.new())
	h.eq(int(payload["terrain_generator_version"]), 4, "a v4 save records generator 4")
	var restored := VoxelWorld.new(17017, int(payload["terrain_generator_version"]))
	h.eq(restored.generator.terrain_version, 4, "a v4 save restores the v4 generator")
