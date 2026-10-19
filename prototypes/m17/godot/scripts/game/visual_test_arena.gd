class_name VisualTestArena
extends RefCounted

## M18 reproducible visual test area.
##
## Built at a fixed, deterministic forest site near spawn using the real voxel
## world, mesher, materials and fluid system.  It is only constructed when the
## game is started with `--visual-test`; normal worlds are untouched.
##
## Layout (19x19 clearing at y = 65, centre 72 / -88):
##   - a stone-brick plaza with a cobble border,
##   - eight 3x3 material pads (grass, dirt, sand, gravel, clay, snow, brick,
##     mossy cobble) around it,
##   - two grass/dirt/stone terraces at the north edge,
##   - a sand-rimmed pond on the east side,
##   - boulder clusters, each with a different ore,
##   - crafting table, furnace, plank/glass wall, brick pillar and a log pile,
##   - a planted oak and pine (via the production tree shape function) plus
##     grass tufts and ferns.
##
## The surrounding forest is left intact, so the area shows the production tree
## silhouette at the clearing edge as well as the planted trees inside it.

const CENTER := Vector3i(72, 65, -88)
const HALF := 9
const BASE_Y := 65
const PLAZA := 5
const POND_MIN := Vector2i(5, -3)
const POND_MAX := Vector2i(8, 1)


func build(world: VoxelWorld) -> Dictionary:
	var placed := 0

	# Level the clearing and remove whatever grew inside it.  The area is almost
	# flat in the generated world (65-67), so this is a clearing, not a quarry.
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			var x := CENTER.x + dx
			var z := CENTER.z + dz
			for y in range(BASE_Y - 2, BASE_Y + 1):
				var block_id := BlockDB.GRASS if y == BASE_Y else BlockDB.DIRT
				placed += _put(world, Vector3i(x, y, z), block_id)
			for y in range(BASE_Y + 1, BASE_Y + 12):
				placed += _put(world, Vector3i(x, y, z), BlockDB.AIR)

	# Stone-brick plaza with a cobble border.
	for dz in range(-PLAZA, PLAZA + 1):
		for dx in range(-PLAZA, PLAZA + 1):
			var border := absi(dx) == PLAZA or absi(dz) == PLAZA
			placed += _put(world, Vector3i(CENTER.x + dx, BASE_Y, CENTER.z + dz),
				BlockDB.COBBLESTONE if border else BlockDB.STONE_BRICK)

	# Material pads (3x3 each) around the plaza.
	var pads := [
		[Vector2i(-8, -4), BlockDB.GRASS],
		[Vector2i(-8, 0), BlockDB.DIRT],
		[Vector2i(-8, 4), BlockDB.SAND],
		[Vector2i(5, -8), BlockDB.GRAVEL],
		[Vector2i(5, 5), BlockDB.CLAY],
		[Vector2i(-4, 7), BlockDB.BRICK],
		[Vector2i(0, 7), BlockDB.SNOW],
		[Vector2i(4, 7), BlockDB.MOSSY_COBBLE],
	]
	for pad: Array in pads:
		var origin: Vector2i = pad[0]
		var block_id: int = pad[1]
		for pz in 3:
			for px in 3:
				var position := Vector3i(CENTER.x + origin.x + px, BASE_Y, CENTER.z + origin.y + pz)
				placed += _put(world, position, block_id)
				placed += _put(world, position + Vector3i.DOWN, _subsurface_for(block_id))

	# Terraces at the north edge: z = -97, -96, -95 are three, two and one block
	# high.  Grass tops over dirt and stone.
	var terrace_z := CENTER.z - HALF
	for dx in range(-PLAZA, PLAZA + 1):
		var x := CENTER.x + dx
		placed += _put(world, Vector3i(x, BASE_Y + 1, terrace_z + 2), BlockDB.GRASS)
		placed += _put(world, Vector3i(x, BASE_Y + 1, terrace_z + 1), BlockDB.DIRT)
		placed += _put(world, Vector3i(x, BASE_Y + 2, terrace_z + 1), BlockDB.GRASS)
		placed += _put(world, Vector3i(x, BASE_Y + 1, terrace_z), BlockDB.STONE)
		placed += _put(world, Vector3i(x, BASE_Y + 2, terrace_z), BlockDB.DIRT)
		placed += _put(world, Vector3i(x, BASE_Y + 3, terrace_z), BlockDB.GRASS)

	# Pond: a two-block-deep basin with a sand rim.  `set_block(WATER)` creates a
	# real source cell, so the normal fluid simulation and save rules apply.
	for pz in range(POND_MIN.y - 1, POND_MAX.y + 2):
		for px in range(POND_MIN.x - 1, POND_MAX.x + 2):
			var x := CENTER.x + px
			var z := CENTER.z + pz
			var inside := px >= POND_MIN.x and px <= POND_MAX.x and pz >= POND_MIN.y and pz <= POND_MAX.y
			if inside:
				placed += _put(world, Vector3i(x, BASE_Y - 2, z), BlockDB.SAND)
				placed += _put(world, Vector3i(x, BASE_Y - 1, z), BlockDB.WATER)
				placed += _put(world, Vector3i(x, BASE_Y, z), BlockDB.WATER)
			else:
				placed += _put(world, Vector3i(x, BASE_Y, z), BlockDB.SAND)
				placed += _put(world, Vector3i(x, BASE_Y - 1, z), BlockDB.SAND)

	# Boulder clusters: solid, natural-looking props.  Each one carries a
	# different ore so every resource-bearing block is visible in the area.
	_boulder(world, Vector3i(CENTER.x - 9, BASE_Y + 1, CENTER.z + 8), 3, BlockDB.COAL_ORE)
	_boulder(world, Vector3i(CENTER.x + 8, BASE_Y + 1, CENTER.z + 8), 2, BlockDB.IRON_ORE)
	_boulder(world, Vector3i(CENTER.x + 8, BASE_Y + 1, CENTER.z - 9), 2, BlockDB.GOLD_ORE)
	_boulder(world, Vector3i(CENTER.x - 9, BASE_Y + 1, CENTER.z - 3), 2, BlockDB.DIAMOND_ORE)

	# Stations and other placeables.
	placed += _put(world, Vector3i(CENTER.x - 2, BASE_Y + 1, CENTER.z), BlockDB.CRAFTING_TABLE)
	placed += _put(world, Vector3i(CENTER.x + 2, BASE_Y + 1, CENTER.z), BlockDB.FURNACE)
	# A small plank/glass wall behind the stations, with a brick pillar.
	for y in range(BASE_Y + 1, BASE_Y + 3):
		placed += _put(world, Vector3i(CENTER.x - 4, y, CENTER.z - 3), BlockDB.PLANKS)
		placed += _put(world, Vector3i(CENTER.x - 3, y, CENTER.z - 3), BlockDB.GLASS if y == BASE_Y + 2 else BlockDB.PLANKS)
		placed += _put(world, Vector3i(CENTER.x - 2, y, CENTER.z - 3), BlockDB.PLANKS)
	placed += _put(world, Vector3i(CENTER.x + 4, BASE_Y + 1, CENTER.z - 3), BlockDB.BRICK)
	placed += _put(world, Vector3i(CENTER.x + 4, BASE_Y + 2, CENTER.z - 3), BlockDB.BRICK)
	# A log pile and a cobble step.
	placed += _put(world, Vector3i(CENTER.x - 5, BASE_Y + 1, CENTER.z + 3), BlockDB.OAK_LOG)
	placed += _put(world, Vector3i(CENTER.x - 5, BASE_Y + 1, CENTER.z + 4), BlockDB.PINE_LOG)
	placed += _put(world, Vector3i(CENTER.x - 4, BASE_Y + 1, CENTER.z + 4), BlockDB.OAK_LOG)
	placed += _put(world, Vector3i(CENTER.x + 5, BASE_Y + 1, CENTER.z + 3), BlockDB.COBBLESTONE)

	# Two planted trees use the same shape functions as world generation, and
	# they frame the clearing from the north.
	world.generator.plant_tree(world, CENTER.x - 8, CENTER.z - 8, WorldGen.TreeType.OAK)
	world.generator.plant_tree(world, CENTER.x + 8, CENTER.z - 7, WorldGen.TreeType.PINE)

	# Vegetation on the grass edges (crossed-quad decoration blocks).
	var deco := [
		[Vector3i(CENTER.x - 7, BASE_Y + 1, CENTER.z - 5), BlockDB.GRASS_TUFT],
		[Vector3i(CENTER.x - 6, BASE_Y + 1, CENTER.z - 1), BlockDB.FERN],
		[Vector3i(CENTER.x - 8, BASE_Y + 1, CENTER.z + 5), BlockDB.TALL_GRASS],
		[Vector3i(CENTER.x + 7, BASE_Y + 1, CENTER.z + 6), BlockDB.GRASS_TUFT],
		[Vector3i(CENTER.x + 6, BASE_Y + 1, CENTER.z - 5), BlockDB.TALL_GRASS],
		[Vector3i(CENTER.x + 3, BASE_Y + 1, CENTER.z + 7), BlockDB.FERN],
		[Vector3i(CENTER.x - 3, BASE_Y + 1, CENTER.z - 6), BlockDB.GRASS_TUFT],
		[Vector3i(CENTER.x + 7, BASE_Y + 1, CENTER.z + 1), BlockDB.GRASS_TUFT],
		[Vector3i(CENTER.x - 6, BASE_Y + 1, CENTER.z + 7), BlockDB.FERN],
		[Vector3i(CENTER.x + 2, BASE_Y + 1, CENTER.z + 8), BlockDB.TALL_GRASS],
	]
	for entry: Array in deco:
		placed += _put(world, entry[0], int(entry[1]))

	# The per-block writes only mark chunks dirty; make sure every touched chunk
	# is rebuilt before the capture harness samples.
	var touched := {}
	for dz in range(-HALF - 1, HALF + 2):
		for dx in range(-HALF - 1, HALF + 2):
			var coord := VoxelWorld.world_to_chunk(Vector3i(CENTER.x + dx, BASE_Y, CENTER.z + dz))
			if not touched.has(coord) and world.has_chunk(coord):
				(world.get_chunk(coord) as ChunkData).mark_dirty()
				touched[coord] = true

	print("M18_VISUAL_TEST built centre=%s blocks=%d chunks=%d" % [CENTER, placed, touched.size()])
	return {"center": CENTER, "blocks": placed, "chunks": touched.size()}


func _put(world: VoxelWorld, position: Vector3i, block_id: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id:
		return 0
	return 1 if world.set_block(position, block_id, false) else 0


func _subsurface_for(surface: int) -> int:
	match surface:
		BlockDB.SAND, BlockDB.SANDSTONE:
			return BlockDB.SAND
		BlockDB.SNOW:
			return BlockDB.SNOW
		BlockDB.STONE, BlockDB.COBBLESTONE, BlockDB.MOSSY_COBBLE, BlockDB.STONE_BRICK:
			return BlockDB.STONE
		_:
			return BlockDB.DIRT


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
