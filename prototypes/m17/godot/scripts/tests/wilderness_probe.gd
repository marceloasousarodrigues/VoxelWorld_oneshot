extends SceneTree

## Headless diagnostic: prints a coarse ASCII map of the generated landscape so a
## capture viewpoint can be chosen deliberately.  Not part of the unit suite.
##
## Run: godot --headless --path prototypes/m17/godot --script res://scripts/tests/wilderness_probe.gd -- --seed=17017 --version=1 --step=8 --radius=256

const LEGEND := "~ ocean  , beach  = river water  F forest  P plains  V savanna  D desert  S snow  M mountain  ^ peak  o tree-cover"


func _initialize() -> void:
	var seed_value := 17017
	var version := WorldGen.CURRENT_VERSION
	var step := 8
	var radius := 256
	var fingerprint_mode := false
	var density_mode := false
	var seam_mode := false
	var points_value := ""
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--seed":
				seed_value = value.to_int()
			"--version":
				version = value.to_int()
			"--step":
				step = maxi(1, value.to_int())
			"--radius":
				radius = maxi(step, value.to_int())
			"--fingerprint":
				fingerprint_mode = true
			"--points":
				points_value = value
			"--density":
				density_mode = true
			"--seam":
				seam_mode = true
	if density_mode:
		_print_density(seed_value)
		quit(0)
		return
	if seam_mode:
		_print_seam(seed_value)
		quit(0)
		return
	if fingerprint_mode:
		_print_fingerprints(seed_value)
		quit(0)
		return
	if not points_value.is_empty():
		_print_points(seed_value, version, points_value)
		quit(0)
		return
	var generator := WorldGen.new(seed_value, version)
	print("PROBE seed=%d version=%d step=%d radius=%d sea=%d" % [seed_value, version, step, radius, WorldGen.SEA_LEVEL])
	print(LEGEND)
	var counts := {}
	var rows: PackedStringArray = []
	var cells := 0
	for z in range(-radius, radius + 1, step):
		var line := ""
		for x in range(-radius, radius + 1, step):
			var height := generator.height_at(x, z)
			var biome := generator.biome_at(x, z)
			var glyph := "?"
			if height < WorldGen.SEA_LEVEL - 1:
				glyph = "~"
			elif height <= WorldGen.SEA_LEVEL + 1:
				glyph = ","
			elif height < WorldGen.SEA_LEVEL:
				glyph = "="
			else:
				match biome:
					WorldGen.Biome.FOREST:
						glyph = "F"
					WorldGen.Biome.PLAINS:
						glyph = "P"
					WorldGen.Biome.SAVANNA:
						glyph = "V"
					WorldGen.Biome.DESERT:
						glyph = "D"
					WorldGen.Biome.SNOW:
						glyph = "S"
					WorldGen.Biome.MOUNTAIN:
						glyph = "^" if height > WorldGen.SEA_LEVEL + 46 else "M"
					_:
						glyph = "?"
			if int(generator.tree_at(x, z)["type"]) != WorldGen.TreeType.NONE and glyph != "~" and glyph != "=":
				glyph = "o"
			var key := glyph
			counts[key] = int(counts.get(key, 0)) + 1
			cells += 1
			line += glyph
		rows.append("%5d %s" % [z, line])
	for row in rows:
		print(row)
	for key in counts.keys():
		print("COUNT %s %d %.1f%%" % [key, counts[key], 100.0 * counts[key] / cells])
	quit(0)


## Lists forest trees within 4 blocks of the x=16 chunk border, to pick a seam test.
func _print_seam(seed_value: int) -> void:
	var generator := WorldGen.new(seed_value, 2)
	var found := 0
	for z in range(-64, 64):
		for x in range(12, 21):
			var tree := generator.tree_at(x, z)
			if int(tree["type"]) == WorldGen.TreeType.NONE:
				continue
			print("SEAM x=%d z=%d type=%d base=%d" % [x, z, int(tree["type"]), int(tree["base"])])
			found += 1
			if found >= 12:
				return


## Full-resolution tree coverage of forest columns for versions 1 and 2, over a
## 256x256 window that contains forest, river corridors and clearings.
func _print_density(seed_value: int) -> void:
	for version in [1, WorldGen.CURRENT_VERSION]:
		var generator := WorldGen.new(seed_value, version)
		var forest := 0
		var trees := 0
		var river_trees := 0
		var river_columns := 0
		for z in range(-128, 128):
			for x in range(-128, 128):
				if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
					continue
				forest += 1
				var kind := int(generator.tree_at(x, z)["type"])
				if kind != WorldGen.TreeType.NONE:
					trees += 1
				if generator.height_at(x, z) > WorldGen.SEA_LEVEL and generator._river_distance(x, z) < WorldGen.RIVER_BANK_LIMIT * 1.25:
					river_columns += 1
					if kind != WorldGen.TreeType.NONE:
						river_trees += 1
		print("DENSITY version=%d forest_columns=%d tree_columns=%d coverage=%.3f river_columns=%d river_trees=%d" % [
			version, forest, trees, float(trees) / maxf(1.0, float(forest)), river_columns, river_trees])
		var channel := 0
		var inland := 0
		for z in range(-128, 128):
			for x in range(-128, 128):
				var h := generator.height_at(x, z)
				if h <= WorldGen.SEA_LEVEL or h > WorldGen.SEA_LEVEL + 34:
					continue
				inland += 1
				if generator._river_distance(x, z) < WorldGen.RIVER_BANK_LIMIT:
					channel += 1
		var centre_printed := 0
		for z in range(-128, 128, 2):
			for x in range(-128, 128, 2):
				if centre_printed >= 6:
					break
				var raw := absf(generator._river.get_noise_2d(x, z))
				if raw > 0.012:
					continue
				var mid := generator._compute_height(x, z)
				if mid > WorldGen.SEA_LEVEL + 40 or mid < 50:
					continue
				print("CENTRE x=%d z=%d raw=%.4f height=%d biome=%s" % [x, z, raw, mid, generator.biome_name(generator.biome_at(x, z))])
				centre_printed += 1
		var bed_min := 999
		var bed_max := -999
		var bed_count := 0
		for z in range(-128, 128):
			for x in range(-128, 128):
				if generator.biome_at(x, z) == WorldGen.Biome.OCEAN or generator.biome_at(x, z) == WorldGen.Biome.MOUNTAIN:
					continue
				if generator._river_distance(x, z) >= WorldGen.RIVER_BANK_LIMIT * 0.6:
					continue
				var bed := generator.height_at(x, z)
				bed_min = mini(bed_min, bed)
				bed_max = maxi(bed_max, bed)
				bed_count += 1
		print("BED version=%d count=%d min=%d max=%d sea=%d" % [version, bed_count, bed_min, bed_max, WorldGen.SEA_LEVEL])
		var wet := 0
		var printed := 0
		for z in range(-128, 128, 4):
			for x in range(-128, 128, 4):
				var h := generator.height_at(x, z)
				if h < WorldGen.SEA_LEVEL and h > WorldGen.SEA_LEVEL - 12 and generator.biome_at(x, z) != WorldGen.Biome.OCEAN and generator.biome_at(x, z) != WorldGen.Biome.BEACH and printed < 8:
					print("WET x=%d z=%d h=%d biome=%s" % [x, z, h, generator.biome_name(generator.biome_at(x, z))])
					printed += 1
		for z in range(-128, 128):
			for x in range(-128, 128):
				var h := generator.height_at(x, z)
				if h < WorldGen.SEA_LEVEL and h > WorldGen.SEA_LEVEL - 12 and generator.biome_at(x, z) != WorldGen.Biome.OCEAN and generator.biome_at(x, z) != WorldGen.Biome.BEACH:
					wet += 1
		print("RIVER version=%d inland_columns=%d river_channel_columns=%d share=%.3f wet_inland_below_sea=%d" % [
			version, inland, channel, float(channel) / maxf(1.0, float(inland)), wet])


## `--points=x,z;x,z;...`: surface height, biome and tree kind for chosen columns.
func _print_points(seed_value: int, version: int, points: String) -> void:
	var generator := WorldGen.new(seed_value, version)
	for pair: String in points.split(";", false):
		var xz := pair.split(",")
		if xz.size() != 2:
			continue
		var x := xz[0].to_int()
		var z := xz[1].to_int()
		print("POINT x=%d z=%d height=%d biome=%s tree=%d" % [x, z, generator.height_at(x, z),
			generator.biome_name(generator.biome_at(x, z)), int(generator.tree_at(x, z)["type"])])


## Fingerprints of a fixed chunk block for each generator version, so legacy and
## M30 output can be pinned by tests before and after generator changes.
func _print_fingerprints(seed_value: int) -> void:
	for version in [WorldGen.LEGACY_VERSION, 1, 2, WorldGen.CURRENT_VERSION]:
		var world := VoxelWorld.new(seed_value, version)
		for chunk_z in range(-2, 3):
			for chunk_x in range(-2, 3):
				for chunk_y in range(0, 6):
					world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
		print("FINGERPRINT seed=%d version=%d hash=%d" % [seed_value, version, world.fingerprint()])
