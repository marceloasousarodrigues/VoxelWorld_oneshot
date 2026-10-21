extends SceneTree

## M33 pre-implementation diagnostic: measures the current v3 tree distribution
## by elevation, slope, biome, species and local forest density.  Read-only.
##
## Run: godot --headless --path prototypes/m17/godot \
##   --script res://scripts/tests/m33_vegetation_probe.gd -- --version=3 --radius=256 --step=2

const SEA := WorldGen.SEA_LEVEL


func _initialize() -> void:
	var version := WorldGen.CURRENT_VERSION
	var radius := 256
	var step := 2
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--version":
				version = value.to_int()
			"--radius":
				radius = value.to_int()
			"--step":
				step = maxi(1, value.to_int())
	var generator := WorldGen.new(17017, version)
	print("M33_VEG_PROBE version=%d radius=%d step=%d sea=%d" % [version, radius, step, SEA])
	var bands := {}
	var bands_total := {}
	var slopes := {}
	var slopes_total := {}
	var biomes := {}
	var biomes_total := {}
	var species := {}
	var cells := {}
	var total := 0
	var trees := 0
	var forest := 0
	var forest_trees := 0
	var broadleaf := 0
	var high_broadleaf := 0
	var high_any := 0
	var summit_any := 0
	var summit_broadleaf := 0
	var river_trees := 0
	var river_columns := 0
	var clearing_columns := 0
	var clearing_trees := 0
	for z in range(-radius, radius + 1, step):
		for x in range(-radius, radius + 1, step):
			var height := generator.height_at(x, z)
			var biome := generator.biome_at(x, z)
			var tree := generator.tree_at(x, z)
			var type := int(tree["type"])
			var is_tree := type != WorldGen.TreeType.NONE
			var slope := generator._column_slope(x, z, height)
			var band := _elevation_band(height)
			var slope_band := mini(3, slope)
			bands_total[band] = int(bands_total.get(band, 0)) + 1
			slopes_total[slope_band] = int(slopes_total.get(slope_band, 0)) + 1
			biomes_total[biome] = int(biomes_total.get(biome, 0)) + 1
			total += 1
			if is_tree:
				trees += 1
				bands[band] = int(bands.get(band, 0)) + 1
				slopes[slope_band] = int(slopes.get(slope_band, 0)) + 1
				biomes[biome] = int(biomes.get(biome, 0)) + 1
				species[type] = int(species.get(type, 0)) + 1
				if type != WorldGen.TreeType.PINE and type != WorldGen.TreeType.CACTUS:
					broadleaf += 1
					if height > SEA + 30:
						high_broadleaf += 1
					if height > SEA + 40:
						summit_broadleaf += 1
				if height > SEA + 30:
					high_any += 1
				if height > SEA + 40:
					summit_any += 1
			if biome == WorldGen.Biome.FOREST:
				forest += 1
				if is_tree:
					forest_trees += 1
			if generator._river_distance(x, z) < WorldGen.RIVER_BANK_LIMIT * 1.55:
				river_columns += 1
				if is_tree:
					river_trees += 1
			if biome == WorldGen.Biome.FOREST and generator._forest_patches.get_noise_2d(x, z) < -0.32:
				clearing_columns += 1
				if is_tree:
					clearing_trees += 1
			var cell := Vector2i(x / 32, z / 32)
			var entry: Dictionary = cells.get(cell, {"columns": 0, "trees": 0})
			entry["columns"] = int(entry["columns"]) + 1
			entry["trees"] = int(entry["trees"]) + (1 if is_tree else 0)
			cells[cell] = entry
	print("TOTAL columns=%d trees=%d coverage=%.4f" % [total, trees, float(trees) / maxf(1.0, total)])
	print("FOREST columns=%d trees=%d coverage=%.4f" % [forest, forest_trees, float(forest_trees) / maxf(1.0, forest)])
	print("SPECIES %s" % species)
	print("ELEVATION_BANDS %s" % _ratio_table(bands, bands_total))
	print("SLOPE_BANDS %s" % _ratio_table(slopes, slopes_total))
	print("BIOME_BANDS %s" % _ratio_table(biomes, biomes_total))
	print("HIGH broadleaf_above_sea+30=%d any_above_30=%d summit_broadleaf_above_sea+40=%d summit_any=%d" % [
		high_broadleaf, high_any, summit_broadleaf, summit_any])
	print("RIVER columns=%d trees=%d coverage=%.4f" % [river_columns, river_trees,
		float(river_trees) / maxf(1.0, river_columns)])
	print("CLEARING columns=%d trees=%d coverage=%.4f" % [clearing_columns, clearing_trees,
		float(clearing_trees) / maxf(1.0, clearing_columns)])
	var coverages: Array[float] = []
	var empty_cells := 0
	var full_cells := 0
	for cell: Vector2i in cells:
		var entry: Dictionary = cells[cell]
		var coverage := float(entry["trees"]) / maxf(1.0, float(entry["columns"]))
		coverages.append(coverage)
		if coverage <= 0.01:
			empty_cells += 1
		if coverage >= 0.60:
			full_cells += 1
	coverages.sort()
	var mean := 0.0
	for value: float in coverages:
		mean += value
	mean /= maxf(1.0, coverages.size())
	print("LOCAL_CELLS count=%d mean=%.4f p10=%.4f p50=%.4f p90=%.4f empty=%d full60=%d" % [
		coverages.size(), mean, _percentile(coverages, 0.10),
		_percentile(coverages, 0.50), _percentile(coverages, 0.90), empty_cells, full_cells])
	for center: Vector2i in [Vector2i(224, 288), Vector2i(40, 120), Vector2i(76, -40),
			Vector2i(80, 152), Vector2i(-7, -29)]:
		var window_columns := 0
		var window_trees := 0
		var window_broadleaf := 0
		var window_high := 0
		var window_steep := 0
		var window_steep_trees := 0
		var window_patch := 0.0
		for z in range(center.y - 32, center.y + 33, 2):
			for x in range(center.x - 32, center.x + 33, 2):
				var height := generator.height_at(x, z)
				var tree := generator.tree_at(x, z)
				var type := int(tree["type"])
				var is_tree := type != WorldGen.TreeType.NONE
				var slope := generator._column_slope(x, z, height)
				window_columns += 1
				window_patch += generator._forest_patches.get_noise_2d(x, z)
				if is_tree:
					window_trees += 1
					if type != WorldGen.TreeType.PINE and type != WorldGen.TreeType.CACTUS:
						window_broadleaf += 1
					if height > SEA + 30:
						window_high += 1
				if slope >= 2:
					window_steep += 1
					if is_tree:
						window_steep_trees += 1
		print("WINDOW center=%s columns=%d trees=%d coverage=%.3f broadleaf=%d high=%d steep_columns=%d steep_trees=%d steep_coverage=%.3f mean_patch=%.3f" % [
			center, window_columns, window_trees, float(window_trees) / maxf(1.0, window_columns),
			window_broadleaf, window_high, window_steep, window_steep_trees,
			float(window_steep_trees) / maxf(1.0, window_steep), window_patch / maxf(1.0, window_columns)])
	for point: Vector2i in [Vector2i(-7, -29), Vector2i(80, 152), Vector2i(224, 288),
			Vector2i(76, -40), Vector2i(40, 120), Vector2i(0, 0)]:
		var height := generator.height_at(point.x, point.y)
		var tree := generator.tree_at(point.x, point.y)
		print("POINT x=%d z=%d h=%d band=%s biome=%s slope=%d tree=%d patch=%.3f river=%.3f" % [
			point.x, point.y, height, _elevation_band(height),
			generator.biome_name(generator.biome_at(point.x, point.y)),
			generator._column_slope(point.x, point.y, height), int(tree["type"]),
			generator._forest_patches.get_noise_2d(point.x, point.y),
			generator._river_distance(point.x, point.y)])
	quit(0)


func _elevation_band(height: int) -> String:
	var delta := height - SEA
	if delta <= 0:
		return "<=sea"
	if delta <= 10:
		return "1-10"
	if delta <= 20:
		return "11-20"
	if delta <= 30:
		return "21-30"
	if delta <= 40:
		return "31-40"
	if delta <= 46:
		return "41-46"
	return ">46"


func _ratio_table(numerator: Dictionary, denominator: Dictionary) -> String:
	var out: Array[String] = []
	for key in denominator:
		var n := int(numerator.get(key, 0))
		var d := int(denominator[key])
		out.append("%s:%d/%d=%.3f" % [str(key), n, d, float(n) / maxf(1.0, float(d))])
	out.sort()
	return " ".join(out)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(values.size() - 1))), 0, values.size() - 1)
	return values[index]
