extends SceneTree

## M34 pre-implementation diagnostic. Read-only measurement of crown overlap,
## trunk spacing and canopy composition for the current generator version.
##
## Run: godot --headless --path prototypes/m17/godot \
##   --script res://scripts/tests/m34_canopy_probe.gd -- --version=4 --radius=192

const SEA := WorldGen.SEA_LEVEL
const LOWLAND_CANOPY_BOX := Rect2i(192, 256, 64, 64)
const LOWLAND_BOX := Rect2i(200, 280, 48, 24)

var _generator: WorldGen


func _initialize() -> void:
	var version := WorldGen.CURRENT_VERSION
	var radius := 192
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--version":
				version = value.to_int()
			"--radius":
				radius = value.to_int()
	_generator = WorldGen.new(17017, version)
	print("M34_CANOPY_PROBE version=%d radius=%d" % [version, radius])
	_report_global(radius)
	_report_box(LOWLAND_CANOPY_BOX)
	_report_voxel_top(LOWLAND_CANOPY_BOX)
	for dz in range(-2, 3):
		var row := ""
		for dx in range(-2, 3):
			row += "%d " % _generator._hash2(100 + dx, 140 + dz, 9001)
		print("PRIORITY_ROW %s" % row)
	_simulate_spacing(LOWLAND_CANOPY_BOX)
	for cell: int in [2, 3, 4]:
		for min_distance: int in [3, 4]:
			for cap: int in [3, 4]:
				_simulate_grid(LOWLAND_CANOPY_BOX, cell, min_distance, cap)
	for cell: int in [3, 4]:
		for cap: int in [2, 3, 4]:
			_simulate_jitter_grid(LOWLAND_CANOPY_BOX, cell, 0, cell - 1, cap)
			_simulate_jitter_grid(LOWLAND_CANOPY_BOX, cell, 1, cell - 1, cap)
			_simulate_jitter_grid(LOWLAND_CANOPY_BOX, cell, 1, cell - 2, cap)
	for cap: int in [2, 3]:
		_simulate_jitter_grid(LOWLAND_CANOPY_BOX, 3, 1, 2, cap, 2.5)
		_simulate_jitter_grid(LOWLAND_CANOPY_BOX, 3, 1, 2, cap, 3.0)
	for spacing_radius: float in [2.0, 2.5, 3.0, 3.5]:
		for cap: int in [2, 3]:
			_simulate_localmax(LOWLAND_CANOPY_BOX, spacing_radius, cap)
	_simulate_global(3, 2)
	_simulate_global(3, 3)
	_report_v4_cells()
	_report_actual_box(LOWLAND_CANOPY_BOX)
	_report_actual_box(LOWLAND_BOX)
	_report_treeline()
	_report_dense_groves()
	for keep: int in [4, 5]:
		_simulate_grove_thin(LOWLAND_CANOPY_BOX, keep, 9, 0.34, 2)
		_simulate_grove_thin(LOWLAND_BOX, keep, 9, 0.34, 2)
		_simulate_grove_thin(LOWLAND_CANOPY_BOX, keep, 9, 0.20, 2)
		_simulate_global(2, 2, keep, 9, 0.34)
	quit(0)


func _is_tree(type: int) -> bool:
	return type != WorldGen.TreeType.NONE


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


func _report_global(radius: int) -> void:
	var forest_columns := 0
	var forest_trees := 0
	var all_trees := 0
	var crown_cover := 0
	var crown_multi := 0
	var crown_triple := 0
	var trees: Array[Dictionary] = []
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var biome := _generator.biome_at(x, z)
			var tree := _generator.tree_at(x, z)
			var type := int(tree["type"])
			if biome == WorldGen.Biome.FOREST:
				forest_columns += 1
				if _is_tree(type):
					forest_trees += 1
			if _is_tree(type):
				all_trees += 1
				trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	var counts := {}
	for entry: Dictionary in trees:
		var r := int(entry["r"])
		if r <= 0:
			continue
		var tx := int(entry["x"])
		var tz := int(entry["z"])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var key := Vector2i(tx + dx, tz + dz)
				counts[key] = int(counts.get(key, 0)) + 1
	for key: Vector2i in counts:
		var count := int(counts[key])
		if count >= 1:
			crown_cover += 1
		if count >= 2:
			crown_multi += 1
		if count >= 3:
			crown_triple += 1
	var nearest: Array[float] = []
	for i in trees.size():
		var a: Dictionary = trees[i]
		if int(a["r"]) <= 0:
			continue
		var best := 999999.0
		for j in trees.size():
			if i == j:
				continue
			var b: Dictionary = trees[j]
			var dx := float(int(a["x"]) - int(b["x"]))
			var dz := float(int(a["z"]) - int(b["z"]))
			var distance := sqrt(dx * dx + dz * dz)
			if distance < best:
				best = distance
		if best < 999999.0:
			nearest.append(best)
	nearest.sort()
	print("GLOBAL all_trees=%d forest_columns=%d forest_trees=%d forest_coverage=%.4f" % [
		all_trees, forest_columns, forest_trees,
		float(forest_trees) / maxf(1.0, float(forest_columns))])
	print("GLOBAL_CROWNS covered=%d overlap2=%d overlap3=%d overlap2_ratio=%.3f overlap3_ratio=%.3f" % [
		crown_cover, crown_multi, crown_triple,
		float(crown_multi) / maxf(1.0, float(crown_cover)),
		float(crown_triple) / maxf(1.0, float(crown_cover))])
	print("GLOBAL_SPACING p10=%.2f p25=%.2f p50=%.2f p75=%.2f p90=%.2f" % [
		_percentile(nearest, 0.10), _percentile(nearest, 0.25), _percentile(nearest, 0.50),
		_percentile(nearest, 0.75), _percentile(nearest, 0.90)])


func _report_box(box: Rect2i) -> void:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			var tree := _generator.tree_at(x, z)
			var type := int(tree["type"])
			if not _is_tree(type):
				continue
			var r := _crown_radius(tree)
			if r <= 0:
				continue
			if x + r < box.position.x or x - r >= box.end.x \
					or z + r < box.position.y or z - r >= box.end.y:
				continue
			trees.append({"x": x, "z": z, "r": r, "tree": tree})
	var counts := {}
	var overlap_pairs := 0
	var overlapping_trees := 0
	var heavily_overlapping := 0
	for i in trees.size():
		var a: Dictionary = trees[i]
		var neighbours := 0
		for j in range(i + 1, trees.size()):
			var b: Dictionary = trees[j]
			var dx := float(int(a["x"]) - int(b["x"]))
			var dz := float(int(a["z"]) - int(b["z"]))
			var reach := float(int(a["r"]) + int(b["r"]))
			if dx * dx + dz * dz <= reach * reach:
				overlap_pairs += 1
				neighbours += 1
		if neighbours > 0:
			overlapping_trees += 1
		if neighbours >= 3:
			heavily_overlapping += 1
	for entry: Dictionary in trees:
		var r := int(entry["r"])
		var tx := int(entry["x"])
		var tz := int(entry["z"])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var key := Vector2i(tx + dx, tz + dz)
				counts[key] = int(counts.get(key, 0)) + 1
	var forest_columns := 0
	var open := 0
	var single := 0
	var multi := 0
	var triple := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
			var count := int(counts.get(Vector2i(x, z), 0))
			if count == 0:
				open += 1
			elif count == 1:
				single += 1
			else:
				multi += 1
			if count >= 3:
				triple += 1
	var tops: Array[float] = []
	var radii := {}
	for entry: Dictionary in trees:
		var tree: Dictionary = entry["tree"]
		var type := int(tree["type"])
		var top := float(int(tree["base"]) + int(tree["height"]))
		if _is_broadleaf(type):
			top += 3.0
		else:
			top += 2.0
		tops.append(top)
		var radius := int(entry["r"])
		radii[radius] = int(radii.get(radius, 0)) + 1
	tops.sort()
	print("BOX_RADII %s" % radii)
	print("BOX %s trees=%d overlap_pairs=%d overlapping_trees=%d heavy_overlap_trees=%d" % [
		box, trees.size(), overlap_pairs, overlapping_trees, heavily_overlapping])
	print("BOX_CANOPY forest_columns=%d open=%d single=%d multi=%d triple=%d open_ratio=%.3f multi_ratio=%.3f triple_ratio=%.3f" % [
		forest_columns, open, single, multi, triple,
		float(open) / maxf(1.0, float(forest_columns)),
		float(multi) / maxf(1.0, float(forest_columns)),
		float(triple) / maxf(1.0, float(forest_columns))])
	var box_nearest: Array[float] = []
	for i in trees.size():
		var best := 999999.0
		for j in trees.size():
			if i == j:
				continue
			var dx := float(int(trees[i]["x"]) - int(trees[j]["x"]))
			var dz := float(int(trees[i]["z"]) - int(trees[j]["z"]))
			best = minf(best, sqrt(dx * dx + dz * dz))
		if best < 999999.0:
			box_nearest.append(best)
	box_nearest.sort()
	print("BOX_SPACING p10=%.2f p25=%.2f p50=%.2f p75=%.2f p90=%.2f" % [
		_percentile(box_nearest, 0.10), _percentile(box_nearest, 0.25),
		_percentile(box_nearest, 0.50), _percentile(box_nearest, 0.75),
		_percentile(box_nearest, 0.90)])
	print("BOX_TOP_HEIGHT p10=%.1f p50=%.1f p90=%.1f min=%.1f max=%.1f" % [
		_percentile(tops, 0.10), _percentile(tops, 0.50), _percentile(tops, 0.90),
		tops[0] if not tops.is_empty() else 0.0,
		tops[tops.size() - 1] if not tops.is_empty() else 0.0])


func _simulate_grid(box: Rect2i, cell: int, min_distance: int, crown_cap: int) -> void:
	var trees: Array[Dictionary] = []
	var candidates := 0
	var wins := 0
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var height := _generator.height_at(x, z)
			var cell_x := floori(float(x) / cell)
			var cell_z := floori(float(z) / cell)
			var candidate_x := cell_x * cell + _generator._hash2(cell_x, cell_z, 4711) % cell
			var candidate_z := cell_z * cell + _generator._hash2(cell_x, cell_z, 4712) % cell
			if x != candidate_x or z != candidate_z:
				continue
			candidates += 1
			if not _spacing_wins(x, z, cell, min_distance):
				continue
			wins += 1
			var river_distance := _generator._river_distance(x, z)
			if river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				continue
			var river_outer := river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER
			var score := _generator._vegetation_score(x, z)
			if score < WorldGen.M33_CLEARING_SCORE:
				continue
			var patch := _generator._forest_patches.get_noise_2d(x, z)
			var slope := _generator._column_slope(x, z, height)
			var species_roll := _generator._hash2(x, z, 4714) % 100
			var broadleaf := float(species_roll) < _generator._v4_broadleaf_share(height, patch) * 100.0
			if broadleaf and (height > WorldGen.M33_BROADLEAF_LIMIT or slope >= 4):
				broadleaf = false
			var density := _generator._v4_tree_density(height, slope, broadleaf, score)
			if river_outer:
				if slope > 1:
					continue
				density *= 0.25
			if density <= 0.0:
				continue
			if _generator._hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
				continue
			var tree: Dictionary
			if broadleaf:
				var leaf_roll := _generator._hash2(x, z, 4715) % 100
				if leaf_roll < 75:
					tree = _generator._oak(x, z, height)
				elif leaf_roll < 95:
					tree = _generator._birch(x, z, height)
				else:
					tree = _generator._blossom(x, z, height)
				tree["canopy"] = mini(crown_cap, int(tree["canopy"]))
			else:
				tree = _generator._pine(x, z, height)
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	var counts := {}
	for entry: Dictionary in trees:
		var r := int(entry["r"])
		var tx := int(entry["x"])
		var tz := int(entry["z"])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var key := Vector2i(tx + dx, tz + dz)
				counts[key] = int(counts.get(key, 0)) + 1
	var forest_columns := 0
	var open := 0
	var multi := 0
	var triple := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
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
	print("SIMGRID cell=%d d=%d cap=%d candidates=%d wins=%d trees=%d coverage=%.3f open=%.3f multi=%.3f triple=%.3f spacing_p50=%.2f" % [
		cell, min_distance, crown_cap, candidates, wins, trees.size(),
		float(trees.size()) / maxf(1.0, float(forest_columns)),
		float(open) / maxf(1.0, float(forest_columns)),
		float(multi) / maxf(1.0, float(forest_columns)),
		float(triple) / maxf(1.0, float(forest_columns)),
		_percentile(nearest, 0.50)])


func _simulate_global(cell: int, crown_cap: int, keep: int = 0, out_of: int = 9,
		grove_patch: float = 0.34) -> void:
	var forest_columns := 0
	var all_columns := 0
	var trees := 0
	var cells := {}
	var species := {}
	for z in range(-192, 193):
		for x in range(-192, 193):
			var key := Vector2i(floori(float(x) / 32.0), floori(float(z) / 32.0))
			var entry: Dictionary = cells.get(key, {"all": 0, "forest": 0, "trees": 0})
			entry["all"] = int(entry["all"]) + 1
			all_columns += 1
			var is_forest := _generator.biome_at(x, z) == WorldGen.Biome.FOREST
			if is_forest:
				forest_columns += 1
				entry["forest"] = int(entry["forest"]) + 1
			cells[key] = entry
			if not is_forest:
				continue
			var cell_x := floori(float(x) / cell)
			var cell_z := floori(float(z) / cell)
			var candidate_x := cell_x * cell + _generator._hash2(cell_x, cell_z, 4711) % cell
			var candidate_z := cell_z * cell + _generator._hash2(cell_x, cell_z, 4712) % cell
			if x != candidate_x or z != candidate_z:
				continue
			var patch := _generator._forest_patches.get_noise_2d(x, z)
			if keep > 0 and patch <= grove_patch and _generator._hash2(cell_x, cell_z, 9101) % out_of >= keep:
				continue
			var height := _generator.height_at(x, z)
			var river_distance := _generator._river_distance(x, z)
			if river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				continue
			var river_outer := river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER
			var score := _generator._vegetation_score(x, z)
			if score < WorldGen.M33_CLEARING_SCORE:
				continue
			var slope := _generator._column_slope(x, z, height)
			var species_roll := _generator._hash2(x, z, 4714) % 100
			var broadleaf := float(species_roll) < _generator._v4_broadleaf_share(height, patch) * 100.0
			if broadleaf and (height > WorldGen.M33_BROADLEAF_LIMIT or slope >= 4):
				broadleaf = false
			var density := _generator._v4_tree_density(height, slope, broadleaf, score)
			if river_outer:
				if slope > 1:
					continue
				density *= 0.25
			if density <= 0.0:
				continue
			if _generator._hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
				continue
			trees += 1
			entry["trees"] = int(entry["trees"]) + 1
			cells[key] = entry
			var type: int
			if broadleaf:
				var leaf_roll := _generator._hash2(x, z, 4715) % 100
				type = WorldGen.TreeType.OAK if leaf_roll < 75 else (
					WorldGen.TreeType.BIRCH if leaf_roll < 95 else WorldGen.TreeType.BLOSSOM)
			else:
				type = WorldGen.TreeType.PINE
			species[type] = int(species.get(type, 0)) + 1
	var all_coverages: Array[float] = []
	var forest_coverages: Array[float] = []
	var full_all_coverages: Array[float] = []
	var full_forest_coverages: Array[float] = []
	var full_dense8 := 0
	var full_dense12 := 0
	var full_low1 := 0
	for key: Vector2i in cells:
		var entry: Dictionary = cells[key]
		var all_count := int(entry["all"])
		var forest_count := int(entry["forest"])
		var tree_count := int(entry["trees"])
		var all_coverage := float(tree_count) / maxf(1.0, float(all_count))
		all_coverages.append(all_coverage)
		if forest_count > 0:
			forest_coverages.append(float(tree_count) / float(forest_count))
		if all_count >= 512 and forest_count >= 256:
			var forest_coverage := float(tree_count) / float(forest_count)
			full_all_coverages.append(all_coverage)
			full_forest_coverages.append(forest_coverage)
			if forest_coverage >= 0.08:
				full_dense8 += 1
			if forest_coverage >= 0.12:
				full_dense12 += 1
			if forest_coverage <= 0.01:
				full_low1 += 1
	all_coverages.sort()
	forest_coverages.sort()
	full_all_coverages.sort()
	full_forest_coverages.sort()
	print("SIMGLOBAL cell=%d cap=%d all_columns=%d forest_columns=%d trees=%d coverage=%.4f species=%s" % [
		cell, crown_cap, all_columns, forest_columns, trees,
		float(trees) / maxf(1.0, float(forest_columns)), species])
	print("SIMGLOBAL_ALL p10=%.4f p50=%.4f p90=%.4f max=%.4f full_p50=%.4f full_p90=%.4f full_max=%.4f" % [
		_percentile(all_coverages, 0.10), _percentile(all_coverages, 0.50),
		_percentile(all_coverages, 0.90), all_coverages[all_coverages.size() - 1],
		_percentile(full_all_coverages, 0.50), _percentile(full_all_coverages, 0.90),
		full_all_coverages[full_all_coverages.size() - 1]])
	print("SIMGLOBAL_FOREST p10=%.4f p50=%.4f p90=%.4f max=%.4f full_n=%d full_p50=%.4f full_p90=%.4f full_max=%.4f full_dense8=%d full_dense12=%d full_low1=%d" % [
		_percentile(forest_coverages, 0.10), _percentile(forest_coverages, 0.50),
		_percentile(forest_coverages, 0.90), forest_coverages[forest_coverages.size() - 1],
		full_forest_coverages.size(),
		_percentile(full_forest_coverages, 0.50), _percentile(full_forest_coverages, 0.90),
		full_forest_coverages[full_forest_coverages.size() - 1],
		full_dense8, full_dense12, full_low1])


func _v5_canopy_radius(x: int, z: int, height: int, type: int, patch: float) -> int:
	var canopy := 2
	if type == WorldGen.TreeType.OAK:
		canopy = 2 + _generator._hash2(x, z, 555) % 2
	elif type == WorldGen.TreeType.BIRCH:
		canopy = 2 + (1 if _generator._hash2(x, z, 556) % 4 == 0 else 0)
	elif type == WorldGen.TreeType.BLOSSOM:
		canopy = 2 + (1 if _generator._hash2(x, z, 557) % 3 == 0 else 0)
	var understory := 25 if patch > 0.34 else 20
	if _generator._hash3(x, height, z, 9102) % 100 < understory:
		canopy = 2
	return canopy


func _report_dense_groves() -> void:
	for version: int in [5, 6, 7]:
		var generator := WorldGen.new(17017, version)
		var dense_columns := 0
		var dense_trees := 0
		var open_low_trees := 0
		for z in range(-192, 193):
			for x in range(-192, 193):
				if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
					continue
				var tree := _is_tree(int(generator.tree_at(x, z)["type"]))
				var patch := generator._forest_patches.get_noise_2d(x, z)
				if patch > WorldGen.M34_GROVE_PATCH:
					dense_columns += 1
					dense_trees += 1 if tree else 0
				elif generator.height_at(x, z) <= WorldGen.SEA_LEVEL + 8:
					open_low_trees += 1 if tree else 0
		print("DENSE_GROVES version=%d dense_columns=%d dense_trees=%d open_low_trees=%d" % [
			version, dense_columns, dense_trees, open_low_trees])


func _report_treeline() -> void:
	var trees := 0
	var max_root := -1
	var max_top := -1
	var above_root := 0
	var above_top := 0
	for z in range(-192, 193):
		for x in range(-192, 193):
			var tree := _generator.tree_at(x, z)
			if not _is_tree(int(tree["type"])):
				continue
			trees += 1
			var root := int(tree["base"]) - 1
			var top := _generator._tree_top_y(tree)
			max_root = maxi(max_root, root)
			max_top = maxi(max_top, top)
			if root > WorldGen.M35_TREELINE_LIMIT:
				above_root += 1
			if top > WorldGen.M36_CANOPY_CEILING:
				above_top += 1
	print("TREELINE version=%d trees=%d max_root=%d max_top=%d root_limit=%d top_limit=%d above_root=%d above_top=%d" % [
		_generator.terrain_version, trees, max_root, max_top,
		WorldGen.M35_TREELINE_LIMIT, WorldGen.M36_CANOPY_CEILING, above_root, above_top])


func _report_actual_box(box: Rect2i) -> void:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			var tree := _generator.tree_at(x, z)
			var type := int(tree["type"])
			if not _is_tree(type) or type == WorldGen.TreeType.CACTUS:
				continue
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	_report_tree_set("ACTUAL v%d box=%s" % [_generator.terrain_version, box], box, trees)


func _simulate_grove_thin(box: Rect2i, keep: int, out_of: int, grove_patch: float, crown_cap: int) -> void:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var cell_x := floori(float(x) / 2)
			var cell_z := floori(float(z) / 2)
			var candidate_x := cell_x * 2 + _generator._hash2(cell_x, cell_z, 4711) % 2
			var candidate_z := cell_z * 2 + _generator._hash2(cell_x, cell_z, 4712) % 2
			if x != candidate_x or z != candidate_z:
				continue
			var patch := _generator._forest_patches.get_noise_2d(x, z)
			if patch <= grove_patch and _generator._hash2(cell_x, cell_z, 9101) % out_of >= keep:
				continue
			var height := _generator.height_at(x, z)
			var river_distance := _generator._river_distance(x, z)
			if river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				continue
			var river_outer := river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER
			var score := _generator._vegetation_score(x, z)
			if score < WorldGen.M33_CLEARING_SCORE:
				continue
			var slope := _generator._column_slope(x, z, height)
			var species_roll := _generator._hash2(x, z, 4714) % 100
			var broadleaf := float(species_roll) < _generator._v4_broadleaf_share(height, patch) * 100.0
			if broadleaf and (height > WorldGen.M33_BROADLEAF_LIMIT or slope >= 4):
				broadleaf = false
			var density := _generator._v4_tree_density(height, slope, broadleaf, score)
			if river_outer:
				if slope > 1:
					continue
				density *= 0.25
			if density <= 0.0:
				continue
			if _generator._hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
				continue
			var tree: Dictionary
			if broadleaf:
				var leaf_roll := _generator._hash2(x, z, 4715) % 100
				if leaf_roll < 75:
					tree = _generator._oak(x, z, height)
				elif leaf_roll < 95:
					tree = _generator._birch(x, z, height)
				else:
					tree = _generator._blossom(x, z, height)
				tree["canopy"] = _v5_canopy_radius(x, z, height, int(tree["type"]), patch)
			else:
				tree = _generator._pine(x, z, height)
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	_report_tree_set("SIMGROVE v5radii box=%s keep=%d/%d grove=%.2f" % [box, keep, out_of, grove_patch], box, trees)


func _report_v4_cells() -> void:
	var v4 := WorldGen.new(17017, 4)
	var cells := {}
	var forest_columns := 0
	var all_columns := 0
	var trees := 0
	for z in range(-192, 193):
		for x in range(-192, 193):
			var key := Vector2i(floori(float(x) / 32.0), floori(float(z) / 32.0))
			var entry: Dictionary = cells.get(key, {"all": 0, "forest": 0, "trees": 0})
			entry["all"] = int(entry["all"]) + 1
			all_columns += 1
			var is_forest := v4.biome_at(x, z) == WorldGen.Biome.FOREST
			if is_forest:
				forest_columns += 1
				entry["forest"] = int(entry["forest"]) + 1
			if is_forest and int(v4.tree_at(x, z)["type"]) != WorldGen.TreeType.NONE:
				trees += 1
				entry["trees"] = int(entry["trees"]) + 1
			cells[key] = entry
	var all_coverages: Array[float] = []
	var forest_coverages: Array[float] = []
	var full_all: Array[float] = []
	var full_forest: Array[float] = []
	var full_dense8 := 0
	var full_dense12 := 0
	var full_low1 := 0
	for key: Vector2i in cells:
		var entry: Dictionary = cells[key]
		var all_count := int(entry["all"])
		var forest_count := int(entry["forest"])
		var tree_count := int(entry["trees"])
		var all_coverage := float(tree_count) / maxf(1.0, float(all_count))
		all_coverages.append(all_coverage)
		if forest_count > 0:
			forest_coverages.append(float(tree_count) / float(forest_count))
		if all_count >= 512 and forest_count >= 256:
			var forest_coverage := float(tree_count) / float(forest_count)
			full_all.append(all_coverage)
			full_forest.append(forest_coverage)
			if forest_coverage >= 0.08:
				full_dense8 += 1
			if forest_coverage >= 0.12:
				full_dense12 += 1
			if forest_coverage <= 0.01:
				full_low1 += 1
	all_coverages.sort()
	forest_coverages.sort()
	full_all.sort()
	full_forest.sort()
	print("V4GLOBAL all_columns=%d forest_columns=%d trees=%d coverage=%.4f" % [
		all_columns, forest_columns, trees, float(trees) / maxf(1.0, float(forest_columns))])
	print("V4GLOBAL_ALL p10=%.4f p50=%.4f p90=%.4f max=%.4f full_p50=%.4f full_p90=%.4f full_max=%.4f" % [
		_percentile(all_coverages, 0.10), _percentile(all_coverages, 0.50),
		_percentile(all_coverages, 0.90), all_coverages[all_coverages.size() - 1],
		_percentile(full_all, 0.50), _percentile(full_all, 0.90), full_all[full_all.size() - 1]])
	print("V4GLOBAL_FOREST p10=%.4f p50=%.4f p90=%.4f max=%.4f full_n=%d full_p50=%.4f full_p90=%.4f full_max=%.4f full_dense8=%d full_dense12=%d full_low1=%d" % [
		_percentile(forest_coverages, 0.10), _percentile(forest_coverages, 0.50),
		_percentile(forest_coverages, 0.90), forest_coverages[forest_coverages.size() - 1],
		full_forest.size(),
		_percentile(full_forest, 0.50), _percentile(full_forest, 0.90), full_forest[full_forest.size() - 1],
		full_dense8, full_dense12, full_low1])


func _simulate_localmax(box: Rect2i, radius: float, crown_cap: int) -> void:
	var trees: Array[Dictionary] = []
	var radius_squared := radius * radius
	var reach := ceili(radius)
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var priority := _generator._hash2(x, z, 9001)
			var wins := true
			for dz in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					if dx == 0 and dz == 0:
						continue
					if dx * dx + dz * dz > radius_squared:
						continue
					if _generator._hash2(x + dx, z + dz, 9001) > priority:
						wins = false
						break
				if not wins:
					break
			if not wins:
				continue
			var height := _generator.height_at(x, z)
			var river_distance := _generator._river_distance(x, z)
			if river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				continue
			var river_outer := river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER
			var score := _generator._vegetation_score(x, z)
			if score < WorldGen.M33_CLEARING_SCORE:
				continue
			var patch := _generator._forest_patches.get_noise_2d(x, z)
			var slope := _generator._column_slope(x, z, height)
			var species_roll := _generator._hash2(x, z, 4714) % 100
			var broadleaf := float(species_roll) < _generator._v4_broadleaf_share(height, patch) * 100.0
			if broadleaf and (height > WorldGen.M33_BROADLEAF_LIMIT or slope >= 4):
				broadleaf = false
			var density := _generator._v4_tree_density(height, slope, broadleaf, score)
			if river_outer:
				if slope > 1:
					continue
				density *= 0.25
			if density <= 0.0:
				continue
			if _generator._hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
				continue
			var tree: Dictionary
			if broadleaf:
				var leaf_roll := _generator._hash2(x, z, 4715) % 100
				if leaf_roll < 75:
					tree = _generator._oak(x, z, height)
				elif leaf_roll < 95:
					tree = _generator._birch(x, z, height)
				else:
					tree = _generator._blossom(x, z, height)
				tree["canopy"] = mini(crown_cap, int(tree["canopy"]))
			else:
				tree = _generator._pine(x, z, height)
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	_report_tree_set("SIMLOCALMAX r=%.1f cap=%d" % [radius, crown_cap], box, trees)


func _simulate_jitter_grid(box: Rect2i, cell: int, offset_min: int, offset_max: int, crown_cap: int,
		filter_distance: float = 0.0) -> void:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var height := _generator.height_at(x, z)
			var cell_x := floori(float(x) / cell)
			var cell_z := floori(float(z) / cell)
			var span := offset_max - offset_min + 1
			var candidate_x := cell_x * cell + offset_min + _generator._hash2(cell_x, cell_z, 4711) % span
			var candidate_z := cell_z * cell + offset_min + _generator._hash2(cell_x, cell_z, 4712) % span
			if x != candidate_x or z != candidate_z:
				continue
			if filter_distance > 0.0 and not _orthogonal_wins(x, z, cell, offset_min, offset_max, filter_distance):
				continue
			var river_distance := _generator._river_distance(x, z)
			if river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_CORE:
				continue
			var river_outer := river_distance < WorldGen.RIVER_BANK_LIMIT * WorldGen.M33_RIVER_OUTER
			var score := _generator._vegetation_score(x, z)
			if score < WorldGen.M33_CLEARING_SCORE:
				continue
			var patch := _generator._forest_patches.get_noise_2d(x, z)
			var slope := _generator._column_slope(x, z, height)
			var species_roll := _generator._hash2(x, z, 4714) % 100
			var broadleaf := float(species_roll) < _generator._v4_broadleaf_share(height, patch) * 100.0
			if broadleaf and (height > WorldGen.M33_BROADLEAF_LIMIT or slope >= 4):
				broadleaf = false
			var density := _generator._v4_tree_density(height, slope, broadleaf, score)
			if river_outer:
				if slope > 1:
					continue
				density *= 0.25
			if density <= 0.0:
				continue
			if _generator._hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
				continue
			var tree: Dictionary
			if broadleaf:
				var leaf_roll := _generator._hash2(x, z, 4715) % 100
				if leaf_roll < 75:
					tree = _generator._oak(x, z, height)
				elif leaf_roll < 95:
					tree = _generator._birch(x, z, height)
				else:
					tree = _generator._blossom(x, z, height)
				tree["canopy"] = mini(crown_cap, int(tree["canopy"]))
			else:
				tree = _generator._pine(x, z, height)
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	_report_tree_set("SIMJITTER cell=%d off=%d..%d cap=%d" % [cell, offset_min, offset_max, crown_cap], box, trees)


func _orthogonal_wins(x: int, z: int, cell: int, offset_min: int, offset_max: int, distance: float) -> bool:
	var cell_x := floori(float(x) / cell)
	var cell_z := floori(float(z) / cell)
	var span := offset_max - offset_min + 1
	var priority := _generator._hash2(cell_x, cell_z, 9001)
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ncx := cell_x + offset.x
		var ncz := cell_z + offset.y
		var nx := ncx * cell + offset_min + _generator._hash2(ncx, ncz, 4711) % span
		var nz := ncz * cell + offset_min + _generator._hash2(ncx, ncz, 4712) % span
		var dx := nx - x
		var dz := nz - z
		if dx * dx + dz * dz >= distance * distance:
			continue
		var other := _generator._hash2(ncx, ncz, 9001)
		if other > priority:
			return false
	return true


func _report_tree_set(label: String, box: Rect2i, trees: Array[Dictionary]) -> void:
	var counts := {}
	for entry: Dictionary in trees:
		var r := int(entry["r"])
		var tx := int(entry["x"])
		var tz := int(entry["z"])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var key := Vector2i(tx + dx, tz + dz)
				counts[key] = int(counts.get(key, 0)) + 1
	var forest_columns := 0
	var open := 0
	var multi := 0
	var triple := 0
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
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
	var covered := {}
	for key: Vector2i in counts:
		if counts[key] >= 1 and box.has_point(key):
			covered[key] = true
	var seen := {}
	var components: Array[int] = []
	for cell: Vector2i in covered:
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
				if covered.has(neighbour) and not seen.has(neighbour):
					seen[neighbour] = true
					stack.append(neighbour)
		components.append(count)
	components.sort()
	var large_components := 0
	for component: int in components:
		if component >= 20:
			large_components += 1
	var open_cells := {}
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			var cell := Vector2i(x, z)
			if int(counts.get(cell, 0)) == 0:
				open_cells[cell] = true
	var open_seen := {}
	var open_components: Array[int] = []
	for cell: Vector2i in open_cells:
		if open_seen.has(cell):
			continue
		var stack: Array[Vector2i] = [cell]
		open_seen[cell] = true
		var count := 0
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			count += 1
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbour: Vector2i = current + offset
				if open_cells.has(neighbour) and not open_seen.has(neighbour):
					open_seen[neighbour] = true
					stack.append(neighbour)
		open_components.append(count)
	open_components.sort()
	print("%s trees=%d coverage=%.3f open=%.3f multi=%.3f triple=%.3f spacing_p50=%.2f components=%d largest=%d large20=%d largest_open=%d" % [
		label, trees.size(), float(trees.size()) / maxf(1.0, float(forest_columns)),
		float(open) / maxf(1.0, float(forest_columns)),
		float(multi) / maxf(1.0, float(forest_columns)),
		float(triple) / maxf(1.0, float(forest_columns)),
		_percentile(nearest, 0.50), components.size(),
		components[components.size() - 1] if not components.is_empty() else 0, large_components,
		open_components[open_components.size() - 1] if not open_components.is_empty() else 0])


func _spacing_wins(x: int, z: int, cell: int, min_distance: int) -> bool:
	var cell_x := floori(float(x) / cell)
	var cell_z := floori(float(z) / cell)
	var priority := _generator._hash2(cell_x, cell_z, 9001)
	var reach := ceili(float(min_distance) / float(cell)) + 1
	for ncz in range(cell_z - reach, cell_z + reach + 1):
		for ncx in range(cell_x - reach, cell_x + reach + 1):
			if ncx == cell_x and ncz == cell_z:
				continue
			var nx := ncx * cell + _generator._hash2(ncx, ncz, 4711) % cell
			var nz := ncz * cell + _generator._hash2(ncx, ncz, 4712) % cell
			var dx := nx - x
			var dz := nz - z
			if dx * dx + dz * dz >= min_distance * min_distance:
				continue
			var other := _generator._hash2(ncx, ncz, 9001)
			if other > priority or (other == priority and (ncz < cell_z or (ncz == cell_z and ncx < cell_x))):
				return false
	return true


func _simulate_spacing(box: Rect2i) -> void:
	var trees: Array[Dictionary] = []
	for z in range(box.position.y - 10, box.end.y + 10):
		for x in range(box.position.x - 10, box.end.x + 10):
			var tree := _generator.tree_at(x, z)
			var type := int(tree["type"])
			if not _is_tree(type) or type == WorldGen.TreeType.CACTUS:
				continue
			trees.append({"x": x, "z": z, "tree": tree, "r": _crown_radius(tree)})
	trees.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := _generator._hash2(int(a["x"]) / 2, int(a["z"]) / 2, 9001)
		var pb := _generator._hash2(int(b["x"]) / 2, int(b["z"]) / 2, 9001)
		return pa > pb)
	for distance: int in [3, 4, 5]:
		for crown_cap: int in [3, 4]:
			var accepted: Array[Dictionary] = []
			for entry: Dictionary in trees:
				var x := int(entry["x"])
				var z := int(entry["z"])
				var ok := true
				for other: Dictionary in accepted:
					var dx := x - int(other["x"])
					var dz := z - int(other["z"])
					if dx * dx + dz * dz < distance * distance:
						ok = false
						break
				if ok:
					var r := int(entry["r"])
					if _is_broadleaf(int(entry["tree"]["type"])):
						r = mini(crown_cap, int(entry["tree"].get("canopy", 3))) + 2
					accepted.append({"x": x, "z": z, "r": r})
			var counts := {}
			for entry: Dictionary in accepted:
				var r := int(entry["r"])
				var tx := int(entry["x"])
				var tz := int(entry["z"])
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx * dx + dz * dz > r * r:
							continue
						var key := Vector2i(tx + dx, tz + dz)
						counts[key] = int(counts.get(key, 0)) + 1
			var forest_columns := 0
			var open := 0
			var multi := 0
			var triple := 0
			for z in range(box.position.y, box.end.y):
				for x in range(box.position.x, box.end.x):
					if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
						continue
					forest_columns += 1
					var count := int(counts.get(Vector2i(x, z), 0))
					if count == 0:
						open += 1
					if count >= 2:
						multi += 1
					if count >= 3:
						triple += 1
			var nearest: Array[float] = []
			for i in accepted.size():
				var best := 999999.0
				for j in accepted.size():
					if i == j:
						continue
					var dx := float(int(accepted[i]["x"]) - int(accepted[j]["x"]))
					var dz := float(int(accepted[i]["z"]) - int(accepted[j]["z"]))
					best = minf(best, sqrt(dx * dx + dz * dz))
				if best < 999999.0:
					nearest.append(best)
			nearest.sort()
			print("SIM d=%d cap=%d trees=%d open=%.3f multi=%.3f triple=%.3f spacing_p50=%.2f" % [
				distance, crown_cap, accepted.size(),
				float(open) / maxf(1.0, float(forest_columns)),
				float(multi) / maxf(1.0, float(forest_columns)),
				float(triple) / maxf(1.0, float(forest_columns)),
				_percentile(nearest, 0.50)])


func _report_voxel_top(box: Rect2i) -> void:
	var world := VoxelWorld.new(17017, _generator.terrain_version)
	var min_chunk := VoxelWorld.world_to_chunk(Vector3i(box.position.x, 0, box.position.y))
	var max_chunk := VoxelWorld.world_to_chunk(Vector3i(box.end.x - 1, 0, box.end.y - 1))
	for cz in range(min_chunk.z, max_chunk.z + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			for cy in range(WorldGen.CHUNKS_Y):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	var leaf_columns := 0
	var columns := 0
	var tops := {}
	var heights: Array[float] = []
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			columns += 1
			var top_y := -1
			var top_block := BlockDB.AIR
			for y in range(WorldGen.WORLD_HEIGHT - 1, -1, -1):
				var block := world.get_block(Vector3i(x, y, z))
				if block != BlockDB.AIR and block != BlockDB.WATER:
					top_y = y
					top_block = block
					break
			if top_y < 0:
				continue
			if top_block == BlockDB.OAK_LEAVES or top_block == BlockDB.BIRCH_LEAVES \
					or top_block == BlockDB.BLOSSOM_LEAVES or top_block == BlockDB.PINE_LEAVES:
				leaf_columns += 1
				tops[Vector2i(x, z)] = top_y
				heights.append(float(top_y))
	var maxima := 0
	for key: Vector2i in tops:
		var value := int(tops[key])
		var is_max := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var neighbour := Vector2i(key.x + dx, key.y + dz)
				if tops.has(neighbour) and int(tops[neighbour]) > value:
					is_max = false
					break
			if not is_max:
				break
		if is_max:
			maxima += 1
	heights.sort()
	print("BOX_VOXEL_TOP forest_columns=%d leaf_top=%d leaf_ratio=%.3f local_maxima=%d top_p10=%.1f top_p50=%.1f top_p90=%.1f" % [
		columns, leaf_columns, float(leaf_columns) / maxf(1.0, float(columns)), maxima,
		_percentile(heights, 0.10), _percentile(heights, 0.50), _percentile(heights, 0.90)])


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(values.size() - 1))), 0, values.size() - 1)
	return values[index]
