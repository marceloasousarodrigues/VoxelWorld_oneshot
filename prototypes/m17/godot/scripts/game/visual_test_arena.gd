class_name VisualTestArena
extends RefCounted

## M22 reproducible showcase: lush fantasy wilderness plus a small medieval
## settlement.
##
## Built at a fixed, deterministic forest site near spawn using the real voxel
## world, mesher, materials, fluid system and the same `StructureDB` definitions
## that normal world generation places.  It is only constructed when the game is
## started with `--visual-test`; normal worlds and saves are untouched.
##
## Layout (31x31 clearing centred on 72 / -88, ground at y=65):
##   - a winding packed path from the south gate to the cottage door,
##   - the `timber_cottage` (foundation, timber walls, windows, door, tiled roof,
##     table/furnace/chest/barrel/lantern inside),
##   - a `market_stall` with a crafting table and barrel, plus an outdoor furnace,
##     chest and work area,
##   - a pond and a south-running stream crossed by a plank bridge with rails,
##   - a fence line with a gate, lantern posts along the path,
##   - oak, pine, birch and blossom trees, flower beds, bushes, ferns and rocks.
##
## The surrounding forest is left intact so the clearing reads as a place inside
## the world rather than a floating diorama.

const CENTER := Vector3i(72, 65, -88)
const HALF := 15
const BASE_Y := 65
## Structures put their floor layer on the surface block, so a door threshold is
## flush with the surrounding ground instead of two blocks above it.
const FLOOR_Y := BASE_Y
const PLAZA := 5
const POND_MIN := Vector2i(5, -3)
const POND_MAX := Vector2i(8, 1)
const STREAM_X_MIN := 6
const STREAM_X_MAX := 8
const STREAM_Z_MIN := 2
const STREAM_Z_MAX := HALF - 1
const COTTAGE_ANCHOR := Vector2i(-6, -9)
const STALL_ANCHOR := Vector2i(6, 3)
const GATE_Z := 12


func build(world: VoxelWorld) -> Dictionary:
	var report := {
		"center": CENTER, "blocks": 0, "chunks": 0,
		"cottage": 0, "stall": 0, "path": 0, "bridge": 0,
		"lanterns": 0, "trees": 0, "decorations": 0,
	}

	_level_clearing(world, report)
	_build_path(world, report)
	_build_pond_and_stream(world, report)
	_build_cottage(world, report)
	_build_work_area(world, report)
	_build_fence_and_bridge(world, report)
	_build_lanterns(world, report)
	_plant_trees(world, report)
	_scatter_decorations(world, report)
	_place_rocks(world, report)

	# Per-block writes only mark chunks dirty; make sure every touched chunk is
	# rebuilt before the capture harness samples.
	var touched := {}
	for dz in range(-HALF - 2, HALF + 3):
		for dx in range(-HALF - 2, HALF + 3):
			var coord := VoxelWorld.world_to_chunk(Vector3i(CENTER.x + dx, BASE_Y, CENTER.z + dz))
			if not touched.has(coord) and world.has_chunk(coord):
				(world.get_chunk(coord) as ChunkData).mark_dirty()
				touched[coord] = true
	report["chunks"] = touched.size()
	print("M22_VISUAL_TEST built centre=%s blocks=%d chunks=%d cottage=%d stall=%d path=%d lanterns=%d" % [
		CENTER, int(report["blocks"]), touched.size(), int(report["cottage"]),
		int(report["stall"]), int(report["path"]), int(report["lanterns"])])
	return report


# --- terrain --------------------------------------------------------------

## Levels the clearing, strips anything that grew inside it, and leaves the
## valley edges layered rather than a flat green carpet.
func _level_clearing(world: VoxelWorld, report: Dictionary) -> void:
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			var x := CENTER.x + dx
			var z := CENTER.z + dz
			var edge := maxi(absi(dx), absi(dz))
			for y in range(BASE_Y - 3, BASE_Y + 1):
				var block_id := BlockDB.STONE if y < BASE_Y - 1 else (BlockDB.DIRT if y < BASE_Y else BlockDB.GRASS)
				# Exposed stone at the far corners gives the clearing a natural
				# rocky rim instead of a perfect grass square.
				if edge >= HALF - 1 and y == BASE_Y and (absi(dx) + absi(dz)) % 7 == 0:
					block_id = BlockDB.STONE
				report["blocks"] += _put(world, Vector3i(x, y, z), block_id)
			for y in range(BASE_Y + 1, BASE_Y + 30):
				report["blocks"] += _put(world, Vector3i(x, y, z), BlockDB.AIR)

	# A small raised, layered rock shelf on the north-west edge.
	for dz in range(-HALF, -HALF + 4):
		for dx in range(-HALF, -HALF + 6):
			var world_position := Vector3i(CENTER.x + dx, BASE_Y + 1, CENTER.z + dz)
			report["blocks"] += _put(world, world_position, BlockDB.DIRT)
			report["blocks"] += _put(world, world_position + Vector3i.UP, BlockDB.GRASS)
			report["blocks"] += _put(world, world_position + Vector3i.UP + Vector3i.LEFT, BlockDB.STONE)


## The path is a pure function of z: a gentle S-curve from the south gate to the
## cottage door.  Two blocks wide, with occasional darker stones and a stone
## apron at the door.
func _path_offset(relative_z: int) -> int:
	var t := float(GATE_Z + 2 - relative_z) / float(GATE_Z + 2 + 6)
	t = clampf(t, 0.0, 1.0)
	return roundi(-2.0 - 4.0 * t + sin(t * TAU) * 2.5)


func _build_path(world: VoxelWorld, report: Dictionary) -> void:
	for relative_z in range(HALF, -7, -1):
		var centre_offset := _path_offset(relative_z)
		for offset in range(0, 2):
			var x := CENTER.x + centre_offset + offset
			var z := CENTER.z + relative_z
			var block_id := BlockDB.PATH
			if (relative_z * 7 + offset) % 9 == 0:
				block_id = BlockDB.COBBLESTONE
			elif (relative_z * 3 + offset) % 11 == 0:
				block_id = BlockDB.GRAVEL
			report["blocks"] += _put(world, Vector3i(x, BASE_Y, z), block_id)
			report["path"] += 1
			# Clear any vegetation that would stand in the walkway.
			report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, z), BlockDB.AIR)
	# Stone apron in front of the door.
	var door := CENTER + Vector3i(COTTAGE_ANCHOR.x, 0, COTTAGE_ANCHOR.y + 3)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			report["blocks"] += _put(world, Vector3i(door.x + dx, BASE_Y, door.z + dz + 1), BlockDB.STONE_BRICK)


func _build_pond_and_stream(world: VoxelWorld, report: Dictionary) -> void:
	# Pond: a two-block-deep basin with a sand/gravel rim.  `set_block(WATER)`
	# creates a real source cell, so the normal fluid simulation and save rules
	# apply.
	for pz in range(POND_MIN.y - 1, POND_MAX.y + 2):
		for px in range(POND_MIN.x - 1, POND_MAX.x + 2):
			var x := CENTER.x + px
			var z := CENTER.z + pz
			var inside := px >= POND_MIN.x and px <= POND_MAX.x and pz >= POND_MIN.y and pz <= POND_MAX.y
			if inside:
				report["blocks"] += _put(world, Vector3i(x, BASE_Y - 2, z), BlockDB.SAND)
				report["blocks"] += _put(world, Vector3i(x, BASE_Y - 1, z), BlockDB.WATER)
				report["blocks"] += _put(world, Vector3i(x, BASE_Y, z), BlockDB.WATER)
			else:
				var rim := BlockDB.SAND if (px + pz) % 4 != 0 else BlockDB.GRAVEL
				report["blocks"] += _put(world, Vector3i(x, BASE_Y, z), rim)
				report["blocks"] += _put(world, Vector3i(x, BASE_Y - 1, z), BlockDB.SAND)

	# Stream: a narrow channel running south from the pond to the clearing edge.
	for pz in range(STREAM_Z_MIN, STREAM_Z_MAX + 1):
		for px in range(STREAM_X_MIN, STREAM_X_MAX + 1):
			var x := CENTER.x + px
			var z := CENTER.z + pz
			var bank := px == STREAM_X_MIN - 1 or px == STREAM_X_MAX + 1
			if bank:
				report["blocks"] += _put(world, Vector3i(x, BASE_Y, z),
					BlockDB.GRAVEL if (px + pz) % 3 == 0 else BlockDB.SAND)
			else:
				report["blocks"] += _put(world, Vector3i(x, BASE_Y - 2, z), BlockDB.SAND)
				report["blocks"] += _put(world, Vector3i(x, BASE_Y - 1, z), BlockDB.WATER)
				report["blocks"] += _put(world, Vector3i(x, BASE_Y, z), BlockDB.WATER)
			report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, z), BlockDB.AIR)


# --- architecture ---------------------------------------------------------

func _build_cottage(world: VoxelWorld, report: Dictionary) -> void:
	var anchor := CENTER + Vector3i(COTTAGE_ANCHOR.x, 0, COTTAGE_ANCHOR.y)
	report["cottage"] = StructureDB.stamp(world, "timber_cottage", Vector2i(anchor.x, anchor.z), FLOOR_Y)
	report["blocks"] += report["cottage"]
	# A warm lantern just outside the door, on a short log post.
	var door_x := anchor.x
	var door_z := anchor.z + 3
	report["blocks"] += _put(world, Vector3i(door_x + 2, BASE_Y + 1, door_z + 1), BlockDB.FENCE)
	report["blocks"] += _put(world, Vector3i(door_x + 2, BASE_Y + 2, door_z + 1), BlockDB.LANTERN)
	report["lanterns"] += 1
	# A small chopping block and log pile beside the cottage.
	for offset in 3:
		report["blocks"] += _put(world, Vector3i(anchor.x - 5, BASE_Y + 1, door_z - 1 + offset), BlockDB.OAK_LOG)
	report["blocks"] += _put(world, Vector3i(anchor.x - 6, BASE_Y + 1, door_z), BlockDB.OAK_LOG)


func _build_work_area(world: VoxelWorld, report: Dictionary) -> void:
	var anchor := CENTER + Vector3i(STALL_ANCHOR.x, 0, STALL_ANCHOR.y)
	report["stall"] = StructureDB.stamp(world, "market_stall", Vector2i(anchor.x, anchor.z), FLOOR_Y)
	report["blocks"] += report["stall"]
	# Outdoor furnace, chest and barrel next to the stall.
	report["blocks"] += _put(world, Vector3i(anchor.x - 4, BASE_Y + 1, anchor.z + 1), BlockDB.FURNACE)
	report["blocks"] += _put(world, Vector3i(anchor.x - 3, BASE_Y + 1, anchor.z + 1), BlockDB.CHEST)
	report["blocks"] += _put(world, Vector3i(anchor.x - 4, BASE_Y + 1, anchor.z - 1), BlockDB.BARREL)
	report["blocks"] += _put(world, Vector3i(anchor.x - 3, BASE_Y + 1, anchor.z - 1), BlockDB.BARREL)
	# A cobble work apron under the stations.
	for dz in range(-1, 2):
		for dx in range(-5, 0):
			report["blocks"] += _put(world, Vector3i(anchor.x + dx, BASE_Y, anchor.z + dz),
				BlockDB.COBBLESTONE if (dx + dz) % 3 != 0 else BlockDB.STONE_BRICK)


func _build_fence_and_bridge(world: VoxelWorld, report: Dictionary) -> void:
	# South garden fence with a gate where the path crosses it.
	var gate_x := CENTER.x + _path_offset(GATE_Z)
	for dx in range(-12, 13):
		var x := CENTER.x + dx
		if x >= gate_x - 1 and x <= gate_x + 1:
			continue
		report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, CENTER.z + GATE_Z), BlockDB.FENCE)
	# Gate posts and a lantern on each.
	for x in [gate_x - 2, gate_x + 2]:
		report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, CENTER.z + GATE_Z), BlockDB.FENCE)
		report["blocks"] += _put(world, Vector3i(x, BASE_Y + 2, CENTER.z + GATE_Z), BlockDB.LANTERN)
		report["lanterns"] += 1

	# Plank bridge over the stream: deck one block above the water, log supports,
	# and fence rails on both sides.  Every block is ordinary voxel data.
	var bridge_z := CENTER.z + 5
	for x in range(CENTER.x + 4, CENTER.x + 11):
		report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, bridge_z), BlockDB.PLANKS)
		report["bridge"] += 1
		if x == CENTER.x + 4 or x == CENTER.x + 10:
			for y in [BASE_Y - 1, BASE_Y]:
				report["blocks"] += _put(world, Vector3i(x, y, bridge_z), BlockDB.OAK_LOG)
	for x in range(CENTER.x + 5, CENTER.x + 10):
		_report_put(world, report, Vector3i(x, BASE_Y + 2, bridge_z - 1), BlockDB.FENCE)
		_report_put(world, report, Vector3i(x, BASE_Y + 2, bridge_z + 1), BlockDB.FENCE)
	# Steps at both ends so the crossing reads as a bridge, not a wall.
	for z in [bridge_z - 2, bridge_z + 2]:
		report["blocks"] += _put(world, Vector3i(CENTER.x + 4, BASE_Y + 1, z), BlockDB.PLANKS)
		report["blocks"] += _put(world, Vector3i(CENTER.x + 10, BASE_Y + 1, z), BlockDB.PLANKS)


func _build_lanterns(world: VoxelWorld, report: Dictionary) -> void:
	# Lantern posts on both sides of the path, spaced so the path is readable at
	# dusk without turning into a runway.
	for relative_z in [9, 4]:
		var path_x := CENTER.x + _path_offset(int(relative_z))
		for side in [-4, 4]:
			var x: int = path_x + int(side)
			var z: int = CENTER.z + int(relative_z)
			report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, z), BlockDB.FENCE)
			report["blocks"] += _put(world, Vector3i(x, BASE_Y + 2, z), BlockDB.LANTERN)
			report["lanterns"] += 1


# --- vegetation -----------------------------------------------------------

func _plant_trees(world: VoxelWorld, report: Dictionary) -> void:
	var trees := [
		[Vector2i(-12, 7), WorldGen.TreeType.BIRCH],
		[Vector2i(-13, -2), WorldGen.TreeType.OAK],
		[Vector2i(13, -8), WorldGen.TreeType.PINE],
		[Vector2i(8, -13), WorldGen.TreeType.BLOSSOM],
		[Vector2i(12, 8), WorldGen.TreeType.OAK],
	]
	for entry: Array in trees:
		var offset: Vector2i = entry[0]
		var x := CENTER.x + offset.x
		var z := CENTER.z + offset.y
		report["trees"] += world.generator.plant_tree(world, x, z, int(entry[1]), BASE_Y)


func _scatter_decorations(world: VoxelWorld, report: Dictionary) -> void:
	var flowers := [BlockDB.FLOWER_RED, BlockDB.FLOWER_YELLOW, BlockDB.FLOWER_BLUE]
	var ground_cover := [BlockDB.GRASS_TUFT, BlockDB.FERN, BlockDB.TALL_GRASS, BlockDB.BUSH]
	# Deterministic flower beds along the path and around the cottage garden.
	for relative_z in range(GATE_Z - 2, -6, -2):
		var path_x := CENTER.x + _path_offset(relative_z)
		for side in [-4, 4]:
			for index in 2:
				var x: int = path_x + int(side) + (index if side > 0 else -index)
				var z: int = CENTER.z + relative_z + int(index)
				if _can_plant(world, Vector3i(x, BASE_Y + 1, z)):
					report["blocks"] += _put(world, Vector3i(x, BASE_Y + 1, z),
						flowers[absi(x * 3 + z) % flowers.size()])
					report["decorations"] += 1
	# Ground cover at deterministic points around the clearing rim.
	for dz in range(-HALF + 2, HALF - 1, 3):
		for dx in range(-HALF + 2, HALF - 1, 3):
			var position := Vector3i(CENTER.x + dx, BASE_Y + 1, CENTER.z + dz)
			if not _can_plant(world, position):
				continue
			if (dx * 13 + dz * 7) % 5 != 0:
				continue
			var block_id: int = ground_cover[absi(dx * 31 + dz) % ground_cover.size()]
			report["blocks"] += _put(world, position, block_id)
			report["decorations"] += 1
	# A deliberate flower bed in front of the cottage: colour where the player
	# naturally looks on approach.
	var door := CENTER + Vector3i(COTTAGE_ANCHOR.x, 0, COTTAGE_ANCHOR.y + 5)
	for dx in range(-3, 4):
		for dz in range(0, 2):
			var position := Vector3i(door.x + dx, BASE_Y + 1, door.z + dz)
			if _can_plant(world, position) and (dx + dz) % 2 == 0:
				report["blocks"] += _put(world, position, flowers[absi(dx) % flowers.size()])
				report["decorations"] += 1


func _can_plant(world: VoxelWorld, position: Vector3i) -> bool:
	if world.get_block(position) != BlockDB.AIR:
		return false
	var below := world.get_block(position + Vector3i.DOWN)
	return below == BlockDB.GRASS or below == BlockDB.DIRT


func _place_rocks(world: VoxelWorld, report: Dictionary) -> void:
	_boulder(world, Vector3i(CENTER.x - 12, BASE_Y + 1, CENTER.z + 10), 3, BlockDB.COAL_ORE)
	_boulder(world, Vector3i(CENTER.x + 11, BASE_Y + 1, CENTER.z + 6), 2, BlockDB.IRON_ORE)
	_boulder(world, Vector3i(CENTER.x + 10, BASE_Y + 1, CENTER.z - 8), 2, BlockDB.GOLD_ORE)
	_boulder(world, Vector3i(CENTER.x - 13, BASE_Y + 1, CENTER.z - 6), 2, BlockDB.DIAMOND_ORE)
	report["blocks"] += 4 * 4

	# Worn earth and gravel patches around the working edges: they break the flat
	# green lawn without reading as a second path.
	var patches := [
		[Vector2i(-11, 4), BlockDB.PATH], [Vector2i(9, -2), BlockDB.GRAVEL],
		[Vector2i(-12, -10), BlockDB.PATH], [Vector2i(2, 7), BlockDB.PATH],
	]
	for patch: Array in patches:
		var offset: Vector2i = patch[0]
		var position := Vector3i(CENTER.x + offset.x, BASE_Y, CENTER.z + offset.y)
		report["blocks"] += _put(world, position, int(patch[1]))
		report["blocks"] += _put(world, position + Vector3i.RIGHT, int(patch[1]))
	# Fallen logs at the clearing edge.
	for position: Vector3i in [Vector3i(CENTER.x - 13, BASE_Y + 1, CENTER.z + 2),
			Vector3i(CENTER.x + 9, BASE_Y + 1, CENTER.z + 10)]:
		report["blocks"] += _put(world, position, BlockDB.OAK_LOG)
		report["blocks"] += _put(world, position + Vector3i.RIGHT, BlockDB.OAK_LOG)


# --- helpers --------------------------------------------------------------

func _put(world: VoxelWorld, position: Vector3i, block_id: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id:
		return 0
	return 1 if world.set_block(position, block_id, false) else 0


func _report_put(world: VoxelWorld, report: Dictionary, position: Vector3i, block_id: int) -> void:
	var changed := _put(world, position, block_id)
	report["blocks"] += changed


func _boulder(world: VoxelWorld, base: Vector3i, size: int, ore: int) -> void:
	var blocks := [BlockDB.STONE, BlockDB.COBBLESTONE, BlockDB.MOSSY_COBBLE, BlockDB.STONE]
	for z in size:
		for x in size:
			var height := 1 + ((x + z + size) % 2)
			for y in height:
				var block_id: int = blocks[(x * 3 + z + y) % blocks.size()]
				_put(world, base + Vector3i(x, y, z), block_id)
	# One ore face keeps each cluster readable as a resource-bearing rock.
	_put(world, base + Vector3i(size - 1, 0, size - 1), ore)
