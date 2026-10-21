extends RefCounted

## M32 playable-landscape generation and artifact guards.
##
## Pins every historical generator version (0=M29, 1=M30, 2=M31) and checks the
## things M31 left unverified: a continuous inland river reach, mixed riverbank
## materials, a dense-but-readable canopy, and the near-camera target marker that
## produced the thin dark vertical lines in the M31 captures.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
## The river cross-section measured by `m32_river_probe.gd`: z=152 cuts a narrow
## channel whose surface is at sea level.
const RIVER_Z := 152
const RIVER_X0 := 66
const RIVER_X1 := 92


func name() -> String:
	return "m32 playable landscape"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func run(h: TestHarness) -> void:
	h.section("M32 generator versions")
	h.eq(WorldGen.M32_VERSION, 3, "the M32 landscape generator is version 3")
	h.eq(WorldGen.CURRENT_VERSION, 3, "new worlds use the M32 generator")
	for version in [0, 1, 2, 3]:
		h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
	h.check(not WorldGen.is_supported_version(4), "a future version is rejected")
	h.check(not WorldGen.is_supported_version(-1), "a negative version is rejected")

	h.eq(_region_hash(0), PINNED_LEGACY_HASH,
		"version 0 terrain is byte-identical to the pinned M29 output")
	h.eq(_region_hash(1), PINNED_M30_HASH,
		"version 1 terrain is byte-identical to the pinned M30 output")
	h.eq(_region_hash(2), PINNED_M31_HASH,
		"version 2 terrain is byte-identical to the pinned M31 output")
	h.check(_region_hash(3) != PINNED_M31_HASH, "version 3 is a distinct landscape")

	# M31's three-block terraces stay intact on its highlands and on the v3
	# mountain belt.  v3 hills drop the quantisation so they read as natural
	# one-block voxel slopes instead of repeated two-block stair bands.
	var v2 := WorldGen.new(17017, 2)
	var v3 := WorldGen.new(17017, 3)
	var v2_terraced := 0
	var v2_highland := 0
	var v3_mountain_terraced := 0
	var v3_mountains := 0
	var v3_hills := 0
	var v3_even_hills := 0
	for x in range(-160, 161, 4):
		for z in range(-160, 161, 4):
			var h2 := v2.height_at(x, z)
			if h2 >= WorldGen.SEA_LEVEL + 8 and v2._river_distance(x, z) >= WorldGen.RIVER_BANK_LIMIT * 1.6:
				v2_highland += 1
				if posmod(h2, WorldGen.HIGHLAND_TERRACE_SIZE) == 0:
					v2_terraced += 1
			var h3 := v3.height_at(x, z)
			if h3 >= WorldGen.M32_MOUNTAIN_FLOOR:
				v3_mountains += 1
				if posmod(h3, WorldGen.M32_MOUNTAIN_TERRACE_SIZE) == 0:
					v3_mountain_terraced += 1
			elif h3 >= WorldGen.SEA_LEVEL + 8:
				v3_hills += 1
				if posmod(h3, 2) == 0:
					v3_even_hills += 1
	h.greater(float(v2_highland), 100.0, "the v2 probe contains highlands")
	h.greater(float(v2_terraced), float(v2_highland) * 0.93,
		"version 2 keeps its historical three-block terraces")
	h.greater(float(v3_mountains), 50.0, "the v3 probe contains a mountain belt")
	h.greater(float(v3_mountain_terraced), float(v3_mountains) * 0.93,
		"version 3 keeps the M31 stepped mountain shelves")
	h.greater(float(v3_hills), 100.0, "the v3 probe contains highland hills")
	h.check(float(v3_even_hills) / maxf(1.0, float(v3_hills)) < 0.85,
		"version 3 hills are not quantised into two-block stair bands")

	h.section("M32 river reach")
	var world := VoxelWorld.new(17017, 3)
	for chunk_x in range((RIVER_X0 - 1) / ChunkData.SIZE, RIVER_X1 / ChunkData.SIZE + 1):
		for chunk_z in range(RIVER_Z / ChunkData.SIZE, RIVER_Z / ChunkData.SIZE + 1):
			for chunk_y in [3, 4]:
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var water_run := 0
	var longest_run := 0
	var wet_columns: Array[int] = []
	var top_blocks := {}
	for x in range(RIVER_X0, RIVER_X1 + 1):
		var height := world.surface_height(x, RIVER_Z)
		var top := world.get_block(Vector3i(x, height, RIVER_Z))
		top_blocks[top] = int(top_blocks.get(top, 0)) + 1
		var wet := height < WorldGen.SEA_LEVEL \
			and world.get_block(Vector3i(x, WorldGen.SEA_LEVEL, RIVER_Z)) == BlockDB.WATER
		if wet:
			wet_columns.append(x)
			water_run += 1
			longest_run = maxi(longest_run, water_run)
		else:
			water_run = 0
	h.greater(float(wet_columns.size()), 4.0,
		"the river reach has a real water surface at sea level")
	h.greater(float(longest_run), 4.0,
		"the river water surface is continuous across the sampled reach")
	h.eq(world.get_block(Vector3i(int(wet_columns[0]), WorldGen.SEA_LEVEL + 1, RIVER_Z)),
		BlockDB.AIR, "the river surface is exposed to the air, not buried")
	h.check(top_blocks.has(BlockDB.SAND), "the waterline has a sand edge")
	h.check(top_blocks.has(BlockDB.GRASS), "the outer bank returns to grass")
	h.check(top_blocks.has(BlockDB.DIRT) or top_blocks.has(BlockDB.GRAVEL),
		"the bank has a soil or gravel transition")
	h.greater(float(top_blocks.size()), 2.0,
		"riverbank materials are layered instead of one material")
	var sand_columns := int(top_blocks.get(BlockDB.SAND, 0))
	h.less(float(sand_columns), float(RIVER_X1 - RIVER_X0 + 1) * 0.65,
		"the bank is not a broad all-sand apron")

	h.section("M32 canopy")
	var forest := WorldGen.new(17017, 3)
	var forest_columns := 0
	var tree_columns := 0
	var oak_columns: Array[Vector2i] = []
	for z in range(280, 304):
		for x in range(200, 248):
			if forest.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
			if int(forest.tree_at(x, z)["type"]) != WorldGen.TreeType.NONE:
				tree_columns += 1
				if int(forest.tree_at(x, z)["type"]) == WorldGen.TreeType.OAK:
					oak_columns.append(Vector2i(x, z))
	var coverage := float(tree_columns) / maxf(1.0, float(forest_columns))
	h.greater(float(forest_columns), 100.0, "the canopy probe samples a real forest")
	h.greater(coverage, 0.05, "the v3 canopy stays dense (coverage %.3f)" % coverage)
	h.less(coverage, 0.30, "the v3 canopy is not an overlapping tree carpet (coverage %.3f)" % coverage)
	h.eq(WorldGen.M32_TREE_PAD, 8, "the M32 tree pad covers the wider stepped crown")
	h.greater(float(oak_columns.size()), 5.0, "the probe finds broadleaf trees")
	if not oak_columns.is_empty():
		var tree := oak_columns[0]
		var tree_data := forest.tree_at(tree.x, tree.y)
		h.greater(float(int(tree_data["canopy"])), 2.0,
			"M32 oaks use a full-width crown rather than a small top-knot")
		var tree_world := VoxelWorld.new(17017, 3)
		for cy in range(3, 6):
			for cz in range(tree.y / ChunkData.SIZE - 1, tree.y / ChunkData.SIZE + 2):
				for cx in range(tree.x / ChunkData.SIZE - 1, tree.x / ChunkData.SIZE + 2):
					tree_world.ensure_chunk(Vector3i(cx, cy, cz))
		var leaves := 0
		var min_x := 999
		var max_x := -999
		var min_z := 999
		var max_z := -999
		var min_y := 999
		var max_y := -999
		for block_y in range(int(tree_data["base"]), int(tree_data["base"]) + 18):
			for block_z in range(tree.y - 8, tree.y + 9):
				for block_x in range(tree.x - 8, tree.x + 9):
					var block := tree_world.get_block(Vector3i(block_x, block_y, block_z))
					if block != BlockDB.OAK_LEAVES:
						continue
					leaves += 1
					min_x = mini(min_x, block_x)
					max_x = maxi(max_x, block_x)
					min_z = mini(min_z, block_z)
					max_z = maxi(max_z, block_z)
					min_y = mini(min_y, block_y)
					max_y = maxi(max_y, block_y)
		h.greater(float(leaves), 30.0, "the sampled oak carries a substantial cubic crown")
		h.greater(float(max_x - min_x + 1), 5.0, "the crown is wide enough to read at distance")
		h.greater(float(max_z - min_z + 1), 5.0, "the crown is deep enough to read at distance")
		h.greater(float(max_y - min_y + 1), 5.0, "the crown is layered vertically")

	h.section("M32 target marker artifact")
	h.check(not VoxelPlayer.target_marker_visible({"hit": true, "distance": 0.0}, true),
		"a target at the camera does not draw the full-screen marker box")
	h.check(not VoxelPlayer.target_marker_visible({"hit": true, "distance": 0.5}, true),
		"a target closer than the minimum distance is not outlined")
	h.check(VoxelPlayer.target_marker_visible({"hit": true, "distance": 0.75}, true),
		"a normal nearby target is still outlined")
	h.check(VoxelPlayer.target_marker_visible({"hit": true, "distance": 3.0}, true),
		"a normal reach target is still outlined")
	h.check(not VoxelPlayer.target_marker_visible({"hit": false, "distance": 0.0}, true),
		"no hit never draws a marker")
	h.check(not VoxelPlayer.target_marker_visible({"hit": true, "distance": 3.0}, false),
		"the marker can still be disabled explicitly")

	h.section("M32 spawn ground")
	h.check(VoxelPlayer.is_spawn_foliage(BlockDB.OAK_LEAVES), "oak leaves are not spawn ground")
	h.check(VoxelPlayer.is_spawn_foliage(BlockDB.PINE_LOG), "a trunk is not spawn ground")
	h.check(not VoxelPlayer.is_spawn_foliage(BlockDB.GRASS), "grass is spawn ground")
	h.check(not VoxelPlayer.is_spawn_foliage(BlockDB.PLANKS), "a player-built plank surface is spawn ground")
	var spawn_world := VoxelWorld.new(17017, 3)
	spawn_world.ensure_chunk(Vector3i(0, 3, 0))
	spawn_world.ensure_chunk(Vector3i(0, 4, 0))
	spawn_world.set_block(Vector3i(2, 63, 2), BlockDB.GRASS)
	for leaf_y in range(64, 71):
		spawn_world.set_block(Vector3i(2, leaf_y, 2), BlockDB.OAK_LEAVES)
	h.eq(VoxelPlayer.spawn_ground_height(spawn_world, 2, 2, 72), 63,
		"the player spawns on the ground below a tree canopy, not on the leaves")
	h.finish()
