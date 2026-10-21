extends RefCounted

## M34 canopy composition: v5 version plumbing, deterministic placement,
## crown variation, overlap reduction, dense-grove preservation and ecology.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const PINNED_M34_HASH := 5133898688464144157
const SEA := WorldGen.SEA_LEVEL
const SAMPLE_RADIUS := 192
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)
const TEST_DIRECTORY := "user://m34_canopy_test"


func _clean() -> void:
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))


func _spawn_player(world: VoxelWorld) -> VoxelPlayer:
	var player := VoxelPlayer.new()
	player.world = world
	player.set_process(false)
	player.set_physics_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	return player


func _release_player(player: VoxelPlayer) -> void:
	if player == null:
		return
	var parent := player.get_parent()
	if parent != null:
		parent.remove_child(player)
	player.free()


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
	var open_cells := {}
	var clearing_columns := 0
	var clearing_open := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var cell := Vector2i(x, z)
			if int(counts.get(cell, 0)) == 0:
				open_cells[cell] = true
			if generator._vegetation_score(x, z) < WorldGen.M33_CLEARING_SCORE:
				clearing_columns += 1
				if int(counts.get(cell, 0)) == 0:
					clearing_open += 1
	var seen := {}
	var largest_open := 0
	for cell: Vector2i in open_cells:
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
				if open_cells.has(neighbour) and not seen.has(neighbour):
					seen[neighbour] = true
					stack.append(neighbour)
		largest_open = maxi(largest_open, count)
	return {
		"columns": columns,
		"open": float(open) / maxf(1.0, float(columns)),
		"multi": float(multi) / maxf(1.0, float(columns)),
		"triple": float(triple) / maxf(1.0, float(columns)),
		"covered": float(columns - open) / maxf(1.0, float(columns)),
		"spacing_p50": _percentile(nearest, 0.5),
		"clearing_columns": clearing_columns,
		"clearing_open_ratio": float(clearing_open) / maxf(1.0, float(clearing_columns)),
		"largest_open": largest_open,
	}


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
	h.eq(v5_a, PINNED_M34_HASH, "version 5 output is pinned")
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
	var v5_second := WorldGen.new(17017, 5)
	var tree_mismatch := 0
	for z in range(-64, 65, 2):
		for x in range(-64, 65, 2):
			var a := v5.tree_at(x, z)
			var b := v5_second.tree_at(x, z)
			if int(a["type"]) != int(b["type"]) \
					or int(a.get("canopy", -1)) != int(b.get("canopy", -1)) \
					or int(a.get("height", -1)) != int(b.get("height", -1)) \
					or int(a.get("height_class", -1)) != int(b.get("height_class", -1)):
				tree_mismatch += 1
	h.eq(tree_mismatch, 0, "two v5 generators produce identical tree dictionaries")
	var other_seed := WorldGen.new(424242, 5)
	var seed_difference := 0
	for z in range(-32, 33, 4):
		for x in range(-32, 33, 4):
			if int(v5.tree_at(x, z)["type"]) != int(other_seed.tree_at(x, z)["type"]):
				seed_difference += 1
	h.greater(float(seed_difference), 0.0, "a different seed changes the v5 layout")

	h.section("M34 crown overlap reduction")
	var v4_stats := _crown_stats(v4, LOWLAND_CANOPY_BOX)
	var v5_stats := _crown_stats(v5, LOWLAND_CANOPY_BOX)
	h.less(v5_stats["multi"], v4_stats["multi"] - 0.08, "2+ crown overlap drops by >=0.08")
	h.less(v5_stats["multi"], 0.50, "2+ crown overlap is <=0.50")
	h.less(v5_stats["triple"], v4_stats["triple"] - 0.10, "3+ crown overlap drops by >=0.10")
	h.less(v5_stats["triple"], 0.40, "3+ crown overlap is <=0.40")
	h.greater(v5_stats["open"], v4_stats["open"] + 0.05, "open forest columns rise by >=0.05")
	h.greater(v5_stats["open"], 0.40, "open forest columns are >=0.40")
	h.greater(v5_stats["spacing_p50"], 1.9, "median trunk spacing is >=1.9")
	h.greater(v5_stats["spacing_p50"], v4_stats["spacing_p50"] + 0.4, "median spacing rises by >=0.4")
	h.greater(_crown_stats(v5, LOWLAND_BOX)["covered"], 0.55, "dense lowland crown union is >=55%%")
	h.greater(_crown_stats(v5, LOWLAND_CANOPY_BOX)["covered"], 0.45, "open woodland crown union is >=45%%")
	var open_stats := _crown_stats(v5, LOWLAND_CANOPY_BOX)
	h.greater(float(open_stats["clearing_columns"]), 100.0, "the canopy box has enough clearing columns")
	h.greater(float(open_stats["largest_open"]), 200.0, "a crown-free opening of >=200 columns exists")
	h.greater(open_stats["clearing_open_ratio"], 0.50, "at least half of clearing columns are crown-free")

	h.section("M34 crown profiles")
	var distinct_profiles := {}
	for profile in range(6):
		var layer_radii: Array = v5._v5_layer_radii(3, profile)
		h.eq(layer_radii.size(), 7, "a radius-3 v5 profile has seven layers")
		h.less(float(layer_radii[5]), 3.0, "the upper shoulder is narrower than the widest layer")
		h.less(float(layer_radii[6]), 2.0, "the top layer is at most one block wide")
		distinct_profiles[str(layer_radii)] = true
	h.eq(distinct_profiles.size(), 6, "six distinct radius-3 v5 profiles")

	h.section("M34 crown voxel shape")
	var v4_crown_world := VoxelWorld.new(17017, 4)
	var v5_crown_world := VoxelWorld.new(17017, 5)
	for cy in range(0, 7):
		for cz in range(17, 20):
			for cx in range(12, 15):
				v4_crown_world.ensure_chunk(Vector3i(cx, cy, cz))
				v5_crown_world.ensure_chunk(Vector3i(cx, cy, cz))
	var sample_box := Rect2i(200, 280, 32, 24)
	var v4_leaves := _leaf_blocks(v4_crown_world, sample_box, 60, 110)
	var v5_leaves := _leaf_blocks(v5_crown_world, sample_box, 60, 110)
	h.greater(float(v4_leaves), 100.0, "the v4 leaf sample is non-empty")
	h.greater(float(v5_leaves), 100.0, "the v5 leaf sample is non-empty")
	h.less(float(v5_leaves), float(v4_leaves), "v5 crowns use fewer leaf blocks in the sample")

	h.section("M34 chunk boundary")
	var seam_generator := WorldGen.new(17017, 5)
	var seam_tree := Vector2i.ZERO
	var found := false
	for z in range(-64, 1):
		for x in range(40, 57):
			var data := seam_generator.tree_at(x, z)
			var type := int(data["type"])
			if not _is_tree(type):
				continue
			var radius := _crown_radius(data)
			if x - radius <= 48 and x + radius >= 48:
				seam_tree = Vector2i(x, z)
				found = true
				break
		if found:
			break
	h.check(found, "a v5 crown crosses the x=48 border")
	if found:
		var height := seam_generator.height_at(seam_tree.x, seam_tree.y)
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
		var seam_mismatch := 0
		for c: Vector3i in coords:
			if (a.get_chunk(c) as ChunkData).blocks != (b.get_chunk(c) as ChunkData).blocks:
				seam_mismatch += 1
		h.eq(seam_mismatch, 0, "v5 chunks across the border match in both load orders")

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

	h.section("M34 v5 save/edit round-trip")
	_clean()
	var saves := SaveManager.new(TEST_DIRECTORY)
	var edit_world := VoxelWorld.new(17017, 5)
	edit_world.ensure_chunk(Vector3i(0, 3, 0))
	var edited := Vector3i(8, 60, 8)
	h.check(edit_world.set_block(edited, BlockDB.PLANKS), "a v5 block edit is placed")
	var edit_player := _spawn_player(edit_world)
	var edit_payload: Dictionary = saves.to_dictionary(edit_world, edit_player, Inventory.new(),
		null, Health.new(), 1.0, 20.0)
	var restored_world := VoxelWorld.new(17017, 5)
	restored_world.ensure_chunk(Vector3i(0, 3, 0))
	var restored_player := _spawn_player(restored_world)
	var apply_result: Dictionary = saves.apply({"ok": true, "data": edit_payload},
		restored_world, restored_player, Inventory.new())
	h.check(bool(apply_result.get("ok", false)), "the v5 save applies")
	h.eq(restored_world.get_block(edited), BlockDB.PLANKS, "the v5 edit survives save/load")
	h.eq(restored_world.generator.terrain_version, 5, "the restored world uses generator 5")
	_release_player(edit_player)
	_release_player(restored_player)
	_clean()
	h.finish()
