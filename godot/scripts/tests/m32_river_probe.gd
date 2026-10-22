extends SceneTree

## M32 river diagnostic.  Finds water columns that are not part of the open sea and
## reports connected components so a capture viewpoint can be chosen from evidence.
##
## Run: godot --headless --path godot \
##   --script res://scripts/tests/m32_river_probe.gd -- --version=2 --radius=256 --step=2

const SEA := WorldGen.SEA_LEVEL


func _initialize() -> void:
	var version := 2
	var radius := 256
	var step := 2
	var seed_value := 17017
	var map_box := ""
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--version":
				version = value.to_int()
			"--radius":
				radius = value.to_int()
			"--step":
				step = value.to_int()
			"--seed":
				seed_value = value.to_int()
			"--map":
				map_box = value
	var generator := WorldGen.new(seed_value, version)
	print("RIVERPROBE seed=%d version=%d radius=%d step=%d sea=%d" % [seed_value, version, radius, step, SEA])
	if not map_box.is_empty():
		_report_map(generator, map_box, step)
		quit(0)
	_report_columns(generator, radius, step)
	_report_centres(generator, radius)
	_report_world(seed_value, version)
	quit(0)


func _report_map(generator: WorldGen, box: String, step: int) -> void:
	var parts := box.split(",")
	if parts.size() != 4:
		print("MAP_BAD_BOX %s" % box)
		return
	var x0 := parts[0].to_int()
	var z0 := parts[1].to_int()
	var x1 := parts[2].to_int()
	var z1 := parts[3].to_int()
	print("MAP x=%d..%d z=%d..%d step=%d" % [x0, x1, z0, z1, step])
	var header := "      "
	for x in range(x0, x1 + 1, step):
		header += str(posmod(x / step, 10))
	print(header)
	for z in range(z0, z1 + 1, step):
		var line := "%5d " % z
		for x in range(x0, x1 + 1, step):
			var h := generator.height_at(x, z)
			var glyph := "."
			if h < SEA:
				glyph = str(clampi(SEA - h, 1, 9))
			elif h <= SEA + 4:
				glyph = "-"
			else:
				glyph = "g" if h < SEA + 20 else ("h" if h < SEA + 40 else "M")
			if h >= SEA and int(generator.tree_at(x, z)["type"]) != WorldGen.TreeType.NONE:
				glyph = "T"
			line += glyph
		print(line)


func _report_centres(generator: WorldGen, radius: int) -> void:
	var bands := {}
	var samples: Array = []
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var distance := generator._river_distance(x, z)
			if distance > 0.015:
				continue
			var h := generator.height_at(x, z)
			var band := int(floor(float(h) / 8.0)) * 8
			bands[band] = int(bands.get(band, 0)) + 1
			if h > SEA + 2 and samples.size() < 20 and x % 16 == 0 and z % 16 == 0:
				samples.append(Vector3i(x, h, z))
	print("CENTRE_BANDS %s" % [bands])
	var raw_mismatch := 0
	for sample: Vector3i in samples:
		var raw := generator._compute_height(sample.x, sample.z)
		if raw != sample.y:
			raw_mismatch += 1
		print("CENTRE x=%d z=%d h=%d raw=%d biome=%s river=%.5f" % [
			sample.x, sample.z, sample.y, raw,
			generator.biome_name(generator.biome_at(sample.x, sample.z)),
			generator._river_distance(sample.x, sample.z)])
	print("CENTRE_RAW_MISMATCH %d of %d" % [raw_mismatch, samples.size()])


func _report_columns(generator: WorldGen, radius: int, step: int) -> void:
	var span := int(radius * 2 / step) + 1
	var heights := PackedInt32Array()
	heights.resize(span * span)
	var wet := PackedByteArray()
	wet.resize(span * span)
	var total_wet := 0
	for iz in span:
		for ix in span:
			var x := -radius + ix * step
			var z := -radius + iz * step
			var h := generator.height_at(x, z)
			heights[iz * span + ix] = h
			if h < SEA:
				wet[iz * span + ix] = 1
				total_wet += 1
	# Mark every wet cell connected (4-neighbour) to the map border as ocean.
	var border := PackedByteArray()
	border.resize(span * span)
	var queue: Array[int] = []
	for iz in span:
		for ix in span:
			if ix == 0 or iz == 0 or ix == span - 1 or iz == span - 1:
				if wet[iz * span + ix] == 1:
					border[iz * span + ix] = 1
					queue.append(iz * span + ix)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var ix := index % span
		var iz := index / span
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := ix + offset.x
			var nz := iz + offset.y
			if nx < 0 or nz < 0 or nx >= span or nz >= span:
				continue
			var ni := nz * span + nx
			if wet[ni] == 0 or border[ni] == 1:
				continue
			border[ni] = 1
			queue.append(ni)
	var seen := PackedByteArray()
	seen.resize(span * span)
	var components: Array = []
	for index in span * span:
		if wet[index] == 0 or border[index] == 1 or seen[index] == 1:
			continue
		var component := {"area": 0, "min_x": 999999, "max_x": -999999,
			"min_z": 999999, "max_z": -999999, "min_h": 999, "max_h": -999}
		var cells: Array[int] = [index]
		seen[index] = 1
		var cursor := 0
		while cursor < cells.size():
			var cell := cells[cursor]
			cursor += 1
			var ix := cell % span
			var iz := cell / span
			var x := -radius + ix * step
			var z := -radius + iz * step
			var h := heights[cell]
			component["area"] = int(component["area"]) + 1
			component["min_x"] = mini(int(component["min_x"]), x)
			component["max_x"] = maxi(int(component["max_x"]), x)
			component["min_z"] = mini(int(component["min_z"]), z)
			component["max_z"] = maxi(int(component["max_z"]), z)
			component["min_h"] = mini(int(component["min_h"]), h)
			component["max_h"] = maxi(int(component["max_h"]), h)
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := ix + offset.x
				var nz := iz + offset.y
				if nx < 0 or nz < 0 or nx >= span or nz >= span:
					continue
				var ni := nz * span + nx
				if wet[ni] == 0 or border[ni] == 1 or seen[ni] == 1:
					continue
				seen[ni] = 1
				cells.append(ni)
		components.append(component)
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["area"]) > int(b["area"]))
	print("WET_COLUMNS total=%d inland_components=%d" % [total_wet, components.size()])
	for i in mini(12, components.size()):
		var c: Dictionary = components[i]
		var w := int(c["max_x"]) - int(c["min_x"]) + step
		var d := int(c["max_z"]) - int(c["min_z"]) + step
		print("COMPONENT %d area_cells=%d x=%d..%d z=%d..%d w=%d d=%d h=%d..%d" % [
			i, int(c["area"]), int(c["min_x"]), int(c["max_x"]), int(c["min_z"]), int(c["max_z"]),
			w, d, int(c["min_h"]), int(c["max_h"])])
	# Cross-section through the largest inland component's centre.
	if components.size() > 0:
		var c: Dictionary = components[0]
		var cx := (int(c["min_x"]) + int(c["max_x"])) / 2
		var cz := (int(c["min_z"]) + int(c["max_z"])) / 2
		print("CROSS_SECTION z=%d x=%d..%d" % [cz, cx - 24, cx + 24])
		for x in range(cx - 24, cx + 25):
			var h := generator.height_at(x, cz)
			var raw := generator._compute_height(x, cz)
			print("XS x=%d h=%d raw=%d biome=%s river=%.4f tree=%d" % [
				x, h, raw, generator.biome_name(generator.biome_at(x, cz)),
				generator._river_distance(x, cz), int(generator.tree_at(x, cz)["type"])])


func _report_world(seed_value: int, version: int) -> void:
	var world := VoxelWorld.new(seed_value, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(3, 5):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var water_columns := 0
	var water_blocks := 0
	var source_blocks := 0
	for coord: Vector3i in VoxelWorld.sorted_coords(world.chunks):
		var chunk: ChunkData = world.get_chunk(coord)
		for index in ChunkData.CELLS:
			if chunk.blocks[index] != BlockDB.WATER:
				continue
			water_blocks += 1
			if chunk.sources[index] == 1:
				source_blocks += 1
	var top := 0
	for x in range(-32, 32):
		for z in range(-32, 32):
			for y in range(SEA, 40, -1):
				if world.get_block(Vector3i(x, y, z)) == BlockDB.WATER:
					water_columns += 1
					top += y
					break
	print("WORLD water_blocks=%d source_blocks=%d columns_with_water=%d mean_top=%.2f" % [
		water_blocks, source_blocks, water_columns, float(top) / maxf(1.0, float(water_columns))])
