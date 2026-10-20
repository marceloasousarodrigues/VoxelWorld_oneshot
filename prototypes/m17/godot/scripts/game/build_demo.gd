class_name BuildDemo
extends RefCounted

const MedievalKit = preload("res://scripts/game/medieval_kit.gd")

## M25 player-authored construction demonstration.
##
## Builds a cottage and a distinct stone/timber tower from the game's crafted
## block palette on a normal generated world.  It is deliberately *not* a
## `StructureDB` stamp: every foundation, wall, window, door, stair, roof and
## prop cell is written individually through the same authoritative
## `world.set_block` / `set_block_state` path the player uses, so the result is
## ordinary mineable, collidable, persistent world data.
##
## The site is levelled by the "player" first, then the two buildings and a path
## are laid out around it.  Used by `--build-demo` for reproducible captures.

const CENTER := Vector3i(40, 0, 40)
const HALF := 15
const COTTAGE_OFFSET := Vector2i(-5, 0)
const TOWER_OFFSET := Vector2i(7, 0)


static func build(world: VoxelWorld) -> Dictionary:
	var report := {"base_y": 0, "blocks": 0, "cottage": 0, "tower": 0, "path": 0, "stairs": 0}
	var base_y := _level_site(world, report)
	report["base_y"] = base_y
	report["cottage"] = _build_cottage(world, base_y + Vector3i(COTTAGE_OFFSET.x, 0, COTTAGE_OFFSET.y))
	report["tower"] = _build_tower(world, base_y + Vector3i(TOWER_OFFSET.x, 0, TOWER_OFFSET.y))
	report["path"] = _build_path(world, base_y)
	report["stairs"] = _count_stairs(world, base_y)
	print("M25_BUILD_DEMO built base=%s cottage=%d tower=%d path=%d stairs=%d blocks=%d" % [
		base_y, int(report["cottage"]), int(report["tower"]), int(report["path"]),
		int(report["stairs"]), int(report["blocks"])])
	return report


# --- site -----------------------------------------------------------------

## Finds the highest ground in the footprint and levels a grass platform there,
## so the demo sits on a natural, player-chosen site instead of a floating slab.
static func _level_site(world: VoxelWorld, report: Dictionary) -> Vector3i:
	var highest := WorldGen.SEA_LEVEL + 1
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			highest = maxi(highest, world.generator.height_at(CENTER.x + dx, CENTER.z + dz))
	var base := Vector3i(CENTER.x, highest + 1, CENTER.z)
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			var x := base.x + dx
			var z := base.z + dz
			for y in range(base.y - 3, base.y + 1):
				var block_id := BlockDB.STONE if y < base.y - 1 else (BlockDB.DIRT if y < base.y else BlockDB.GRASS)
				report["blocks"] += _put(world, Vector3i(x, y, z), block_id)
			for y in range(base.y + 1, base.y + 16):
				report["blocks"] += _put(world, Vector3i(x, y, z), BlockDB.AIR)
	return base


# --- cottage --------------------------------------------------------------

static func _build_cottage(world: VoxelWorld, anchor: Vector3i) -> int:
	var placed := 0
	# Footprint x -4..4, z -3..3.  The floor is planks inside a stone plinth.
	for dz in range(-3, 4):
		for dx in range(-4, 5):
			var perimeter := absi(dx) == 4 or absi(dz) == 3
			placed += _put(world, anchor + Vector3i(dx, 0, dz),
				BlockDB.STONE_WALL if perimeter else BlockDB.PLANKS)
	# Ground-floor stone plinth and the dark door surround.
	for dz in range(-3, 4):
		for dx in range(-4, 5):
			var perimeter := absi(dx) == 4 or absi(dz) == 3
			if not perimeter:
				continue
			var block_id := BlockDB.STONE_WALL
			if dz == 3 and dx == 0:
				block_id = BlockDB.DOOR
			elif dz == 3 and absi(dx) == 1:
				block_id = BlockDB.DARK_TIMBER
			placed += _put(world, anchor + Vector3i(dx, 1, dz), block_id)
	# Plaster-and-timber upper walls with framed windows, shutters and braces.
	for dz in range(-3, 4):
		for dx in range(-4, 5):
			var perimeter := absi(dx) == 4 or absi(dz) == 3
			if not perimeter:
				continue
			var block_id := BlockDB.PLASTER
			var corner := absi(dx) == 4 and absi(dz) == 3
			if corner:
				block_id = BlockDB.DARK_TIMBER
			elif dz == 3:
				# South facade: central door, timber posts, braces, windows.
				if dx == 0:
					block_id = BlockDB.DOOR
				elif absi(dx) == 1:
					block_id = BlockDB.DARK_TIMBER
				elif absi(dx) == 2:
					block_id = BlockDB.TIMBER_BRACE
				elif absi(dx) == 3:
					block_id = BlockDB.WINDOW
			elif dz == -3:
				# North facade: a framed window between shuttered bays and braces.
				if dx == 0:
					block_id = BlockDB.WINDOW
				elif absi(dx) == 1:
					block_id = BlockDB.SHUTTER
				elif absi(dx) == 2:
					block_id = BlockDB.TIMBER_BRACE
			elif absi(dx) == 4:
				# Side facades: two windows, a central shutter and braced panels.
				if absi(dz) == 1:
					block_id = BlockDB.WINDOW
				elif dz == 0:
					block_id = BlockDB.SHUTTER
				elif absi(dz) == 2:
					block_id = BlockDB.TIMBER_BRACE
			placed += _put(world, anchor + Vector3i(dx, 2, dz), block_id)
	# A plaster upper band with dark framing posts and a lintel over the door.
	for dz in range(-3, 4):
		for dx in range(-4, 5):
			var perimeter := absi(dx) == 4 or absi(dz) == 3
			if not perimeter:
				continue
			var block_id := BlockDB.PLASTER
			if absi(dx) == 4 and absi(dz) == 3:
				block_id = BlockDB.DARK_TIMBER
			elif dz == 3:
				if absi(dx) % 2 == 0 or dx == 0:
					block_id = BlockDB.DARK_TIMBER
			elif dz == -3:
				if absi(dx) % 2 == 0 or dx == 0:
					block_id = BlockDB.DARK_TIMBER
			elif absi(dx) == 4:
				if absi(dz) % 2 == 1:
					block_id = BlockDB.DARK_TIMBER
			placed += _put(world, anchor + Vector3i(dx, 3, dz), block_id)
	# Roof: thin eave overhang, continuous slate ramp planes, triangular ridge,
	# gable infill, finials and a stone chimney above the ridge.
	var roof: Dictionary = MedievalKit.build_gable_roof(world, anchor, 4, 3, 4,
		{"finials": true, "chimney": {"x": 3, "z": -2, "top": 9}})
	placed += int(roof["pieces"])
	# Window boxes sit on the ground under the front windows.
	for dx in [-3, 3]:
		placed += _put(world, anchor + Vector3i(dx, 1, 4), BlockDB.FLOWER_BOX)
	# Interior: work stations, storage, a hanging lantern and a floor rug of path.
	placed += _put(world, anchor + Vector3i(-3, 1, -2), BlockDB.CRAFTING_TABLE)
	placed += _put(world, anchor + Vector3i(-2, 1, -2), BlockDB.FURNACE)
	placed += _put(world, anchor + Vector3i(2, 1, -2), BlockDB.CHEST)
	placed += _put(world, anchor + Vector3i(3, 1, -1), BlockDB.BARREL)
	placed += _put(world, anchor + Vector3i(0, 3, 0), BlockDB.LANTERN)
	for dz in range(-2, 1):
		placed += _put(world, anchor + Vector3i(0, 0, dz), BlockDB.PATH)
	# A lantern post beside the door.
	placed += _put(world, anchor + Vector3i(2, 1, 4), BlockDB.FENCE)
	placed += _put(world, anchor + Vector3i(2, 2, 4), BlockDB.LANTERN)
	return placed


# --- tower / castle section ----------------------------------------------

static func _build_tower(world: VoxelWorld, anchor: Vector3i) -> int:
	var placed := 0
	var s := BlockDB.STONE_BRICK
	var t := BlockDB.TIMBER_FRAME
	var p := BlockDB.PLANKS
	var g := BlockDB.GLASS
	# Stone base, hollow with a doorway; footprint x/z -2..2.
	for y in range(0, 4):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var perimeter := absi(dx) == 2 or absi(dz) == 2
				if y == 0 or perimeter:
					placed += _put(world, anchor + Vector3i(dx, y, dz), s)
	# Arched doorway on the south face.
	placed += _put(world, anchor + Vector3i(0, 1, 2), BlockDB.DOOR)
	placed += _put(world, anchor + Vector3i(0, 2, 2), BlockDB.DOOR)
	# Timber upper storey with glass slits.
	for y in [4, 5]:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var perimeter := absi(dx) == 2 or absi(dz) == 2
				if not perimeter:
					continue
				var corner := absi(dx) == 2 and absi(dz) == 2
				var block_id := t if corner or absi(dx) == 2 else p
				if y == 4 and ((absi(dx) == 2 and absi(dz) == 1) or (absi(dz) == 2 and dx == 0)):
					block_id = g
				placed += _put(world, anchor + Vector3i(dx, y, dz), block_id)
	# Corbelled stone battlements.
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var perimeter := absi(dx) == 2 or absi(dz) == 2
			if not perimeter:
				continue
			if posmod(dx + dz, 2) == 0:
				placed += _put(world, anchor + Vector3i(dx, 6, dz), s)
	# A lantern at the top.
	placed += _put(world, anchor + Vector3i(0, 6, 0), BlockDB.LANTERN)
	# A single stair step up to the door threshold on the south face.
	placed += _put_state(world, anchor + Vector3i(0, 0, 3), BlockDB.STAIR, 0)
	return placed


# --- path -----------------------------------------------------------------

static func _build_path(world: VoxelWorld, base: Vector3i) -> int:
	var placed := 0
	# A packed path from the cottage door, between the buildings, to the tower.
	for dz in range(0, 5):
		placed += _put(world, base + Vector3i(COTTAGE_OFFSET.x, 0, 4 + dz), BlockDB.PATH)
	for dx in range(COTTAGE_OFFSET.x + 1, TOWER_OFFSET.x - 1):
		placed += _put(world, base + Vector3i(dx, 0, 4), BlockDB.PATH)
	# A short path to the tower door.
	for dz in range(3, 5):
		placed += _put(world, base + Vector3i(TOWER_OFFSET.x, 0, dz), BlockDB.PATH)
	# Lane lanterns.
	for x in [-3, 3]:
		placed += _put(world, base + Vector3i(x, 1, 6), BlockDB.FENCE)
		placed += _put(world, base + Vector3i(x, 2, 6), BlockDB.LANTERN)
	return placed


# --- helpers --------------------------------------------------------------

## Counts the stair and roof-ramp blocks in the demo footprint (for the capture
## report).
static func _count_stairs(world: VoxelWorld, base: Vector3i) -> int:
	var count := 0
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			for y in range(base.y, base.y + 8):
				if world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.STAIR \
						or world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.SLATE_STAIR \
						or world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.SLATE_RAMP:
					count += 1
	return count


static func _put(world: VoxelWorld, position: Vector3i, block_id: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id:
		return 0
	# Record the write as a player edit so the built structure is saved and
	# replayed when its chunk reloads, exactly like a block placed in gameplay.
	return 1 if world.set_block(position, block_id, true) else 0


static func _put_state(world: VoxelWorld, position: Vector3i, block_id: int, orientation: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id and world.get_orientation(position) == orientation:
		return 0
	return 1 if world.set_block_state(position, block_id, orientation, true) else 0
