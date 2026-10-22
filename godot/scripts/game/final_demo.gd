class_name FinalDemo
extends RefCounted

const BuildDemo = preload("res://scripts/game/build_demo.gd")
const MedievalKit = preload("res://scripts/game/medieval_kit.gd")

## M28 final player-authored showcase: a village and castle built cell-by-cell
## from the game's crafted palette on a normal generated world.
##
## Nothing here is a `StructureDB` stamp or a prefab: every wall, window, door,
## roof, battlement, path, fence and lantern is written through the same
## `world.set_block` / `set_block_state` path the player uses.  The M24 economy
## harness proves those materials are reachable through harvesting and crafting.
##
## The site is a levelled natural clearing near (40, 40); the spawn area at
## (8, 8) is left outside it, so the starting landscape stays natural.

const CENTER := Vector3i(40, 0, 40)
const HALF := 30
## Tallest authored block is base + 14 (keep roof/chimney).  Cap the levelled
## site so the showcase remains complete on the taller v3 highlands.
const BUILD_HEADROOM := 16
const COTTAGE_OFFSET := Vector2i(-24, 7)
const TOWER_OFFSET := Vector2i(16, 8)
const LONGHOUSE_OFFSET := Vector2i(-10, 2)
const MARKET_OFFSET := Vector2i(9, 17)
const CASTLE_OFFSET := Vector2i(0, -14)
const WELL_OFFSET := Vector2i(-16, 18)


static func build(world: VoxelWorld) -> Dictionary:
	var report := {"base_y": 0, "blocks": 0, "cottage": 0, "tower": 0, "longhouse": 0,
		"market": 0, "castle": 0, "path": 0, "stairs": 0, "lanterns": 0}
	var base := _level_site(world, report)
	report["base_y"] = base
	report["cottage"] = BuildDemo._build_cottage(world, base + Vector3i(COTTAGE_OFFSET.x, 0, COTTAGE_OFFSET.y))
	report["tower"] = BuildDemo._build_tower(world, base + Vector3i(TOWER_OFFSET.x, 0, TOWER_OFFSET.y))
	report["longhouse"] = _build_longhouse(world, base + Vector3i(LONGHOUSE_OFFSET.x, 0, LONGHOUSE_OFFSET.y))
	report["market"] = _build_market_row(world, base + Vector3i(MARKET_OFFSET.x, 0, MARKET_OFFSET.y))
	report["castle"] = _build_castle(world, base + Vector3i(CASTLE_OFFSET.x, 0, CASTLE_OFFSET.y), report)
	report["path"] = _build_street(world, base, report)
	_build_well(world, base + Vector3i(WELL_OFFSET.x, 0, WELL_OFFSET.y))
	_plant_frame_trees(world, base, report)
	report["stairs"] = _count_stairs(world, base)
	print("M28_FINAL_DEMO built base=%s cottage=%d tower=%d longhouse=%d market=%d castle=%d path=%d stairs=%d lanterns=%d blocks=%d" % [
		base, int(report["cottage"]), int(report["tower"]), int(report["longhouse"]),
		int(report["market"]), int(report["castle"]), int(report["path"]),
		int(report["stairs"]), int(report["lanterns"]), int(report["blocks"])])
	return report


static func _level_site(world: VoxelWorld, report: Dictionary) -> Vector3i:
	var highest := WorldGen.SEA_LEVEL + 1
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			highest = maxi(highest, world.generator.height_at(CENTER.x + dx, CENTER.z + dz))
	var base := Vector3i(CENTER.x, mini(highest + 1, WorldGen.WORLD_HEIGHT - BUILD_HEADROOM), CENTER.z)
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			var x := base.x + dx
			var z := base.z + dz
			for y in range(base.y - 3, base.y + 1):
				var block_id := BlockDB.STONE if y < base.y - 1 else (BlockDB.DIRT if y < base.y else BlockDB.GRASS)
				report["blocks"] += BuildDemo._put(world, Vector3i(x, y, z), block_id)
			for y in range(base.y + 1, base.y + 18):
				report["blocks"] += BuildDemo._put(world, Vector3i(x, y, z), BlockDB.AIR)
	return base


# --- longhouse ------------------------------------------------------------

## A larger timber hall: stone plinth, plaster-and-timber frame, framed windows
## and shutters, a slate gable roof, a stone chimney and interior props.
static func _build_longhouse(world: VoxelWorld, anchor: Vector3i) -> int:
	var placed := 0
	# Footprint x -7..7, z -4..4.  Floor planks inside a stone plinth.
	for dz in range(-4, 5):
		for dx in range(-7, 8):
			var perimeter := absi(dx) == 7 or absi(dz) == 4
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 0, dz),
				BlockDB.STONE_WALL if perimeter else BlockDB.PLANKS)
	# Stone ground floor with the double door opening on the street side.
	for dz in range(-4, 5):
		for dx in range(-7, 8):
			if absi(dx) != 7 and absi(dz) != 4:
				continue
			var block_id := BlockDB.STONE_WALL
			if dz == 4 and (dx == -1 or dx == 0):
				block_id = BlockDB.DOOR
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 1, dz), block_id)
	# Plaster-and-timber upper wall with glazing, shutters and braces.
	for dz in range(-4, 5):
		for dx in range(-7, 8):
			var perimeter := absi(dx) == 7 or absi(dz) == 4
			if not perimeter:
				continue
			var block_id := BlockDB.PLASTER
			if absi(dx) == 7 and absi(dz) == 4:
				block_id = BlockDB.DARK_TIMBER
			elif dz == 4:
				if dx == -1 or dx == 0:
					block_id = BlockDB.DOOR
				elif dx == -2 or dx == 1:
					block_id = BlockDB.DARK_TIMBER
				elif dx == -5 or dx == 4:
					block_id = BlockDB.SHUTTER
				elif dx == -4 or dx == 3:
					block_id = BlockDB.WINDOW
				elif dx == -6 or dx == 5:
					block_id = BlockDB.TIMBER_BRACE
				elif dx == -3 or dx == 2 or dx == 6:
					block_id = BlockDB.PLASTER
			elif dz == -4:
				if absi(dx) == 4 or dx == 0:
					block_id = BlockDB.WINDOW
				elif absi(dx) == 5 or absi(dx) == 3 or absi(dx) == 1:
					block_id = BlockDB.SHUTTER
				elif absi(dx) == 6:
					block_id = BlockDB.TIMBER_BRACE
			elif absi(dx) == 7:
				if absi(dz) == 2 or dz == 0:
					block_id = BlockDB.WINDOW
				elif absi(dz) == 3 or absi(dz) == 1:
					block_id = BlockDB.SHUTTER
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 2, dz), block_id)
	# A plaster upper band with dark framing posts; the roof eave sits above it.
	for dz in range(-4, 5):
		for dx in range(-7, 8):
			var perimeter := absi(dx) == 7 or absi(dz) == 4
			if not perimeter:
				continue
			var block_id := BlockDB.PLASTER
			if absi(dx) == 7 and absi(dz) == 4:
				block_id = BlockDB.DARK_TIMBER
			elif absi(dz) == 4:
				if absi(dx) % 3 == 0 or dx == 0:
					block_id = BlockDB.DARK_TIMBER
			elif absi(dx) == 7:
				if absi(dz) % 2 == 0:
					block_id = BlockDB.DARK_TIMBER
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 3, dz), block_id)
	# Long slate gable roof with eaves, ridge, gable infill, finials and chimney.
	var roof: Dictionary = MedievalKit.build_gable_roof(world, anchor, 7, 4, 4,
		{"finials": true, "chimney": {"x": 5, "z": -2, "top": 10}})
	placed += int(roof["pieces"])
	# Interior props and lanterns.
	placed += BuildDemo._put(world, anchor + Vector3i(-5, 1, -2), BlockDB.CRAFTING_TABLE)
	placed += BuildDemo._put(world, anchor + Vector3i(-4, 1, -2), BlockDB.FURNACE)
	placed += BuildDemo._put(world, anchor + Vector3i(4, 1, 2), BlockDB.CHEST)
	placed += BuildDemo._put(world, anchor + Vector3i(5, 1, 2), BlockDB.BARREL)
	placed += BuildDemo._put(world, anchor + Vector3i(-2, 3, 0), BlockDB.LANTERN)
	placed += BuildDemo._put(world, anchor + Vector3i(2, 3, 0), BlockDB.LANTERN)
	return placed


# --- market row -----------------------------------------------------------

## Two open market stalls with timber posts, slate gable roofs, counters and
## barrels.
static func _build_market_row(world: VoxelWorld, anchor: Vector3i) -> int:
	var placed := 0
	var t := BlockDB.TIMBER_FRAME
	var p := BlockDB.PLANKS
	for stall in 2:
		var origin := anchor + Vector3i(stall * 8, 0, 0)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				placed += BuildDemo._put(world, origin + Vector3i(dx, 0, dz), BlockDB.PATH)
		for dz in [-2, 2]:
			for dx in [-2, 2]:
				for y in [1, 2]:
					placed += BuildDemo._put(world, origin + Vector3i(dx, y, dz), t)
		# Counter and goods.
		for dx in range(-1, 2):
			placed += BuildDemo._put(world, origin + Vector3i(dx, 1, 1), p)
		placed += BuildDemo._put(world, origin + Vector3i(-1, 1, 0), BlockDB.BARREL)
		placed += BuildDemo._put(world, origin + Vector3i(1, 1, 0), BlockDB.CHEST)
		# Slate gable roof with thin eaves and a ridge (no closed gable: the
		# stall must stay open for its counter and goods).
		var roof: Dictionary = MedievalKit.build_gable_roof(world, origin, 2, 2, 3,
			{"gable": false, "finials": false})
		placed += int(roof["pieces"])
		placed += BuildDemo._put(world, origin + Vector3i(0, 3, 0), BlockDB.LANTERN)
	return placed


# --- castle ---------------------------------------------------------------

## A recognizable stone castle: curtain wall, four corner towers, crenellations,
## a gatehouse with a door, and a central keep with timber upper storey and a
## continuous slate gable roof.  Banners use roof-tile strips on the towers.
static func _build_castle(world: VoxelWorld, anchor: Vector3i, report: Dictionary) -> int:
	var placed := 0
	var s := BlockDB.STONE_BRICK
	var c := BlockDB.COBBLESTONE
	var t := BlockDB.TIMBER_FRAME
	var r := BlockDB.ROOF_TILE
	# Curtain wall, footprint x/z -8..8, four blocks high.
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var perimeter := absi(dx) == 8 or absi(dz) == 8
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 0, dz), c)
			if perimeter:
				for y in range(1, 5):
					var block_id := s if y < 4 else c
					placed += BuildDemo._put(world, anchor + Vector3i(dx, y, dz), block_id)
	# Corner towers, 3x3, rising two blocks above the wall.
	for corner: Vector2i in [Vector2i(-8, -8), Vector2i(8, -8), Vector2i(-8, 8), Vector2i(8, 8)]:
		var tower := anchor + Vector3i(corner.x, 0, corner.y)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for y in range(1, 8):
					var block_id := s
					if y == 5 and absi(dx) == 1 and absi(dz) == 1:
						block_id = BlockDB.GLASS
					placed += BuildDemo._put(world, tower + Vector3i(dx, y, dz), block_id)
		# Banner strip and a lantern on top.
		for y in range(6, 8):
			placed += BuildDemo._put(world, tower + Vector3i(0, y, 0), r if y % 2 == 0 else t)
		placed += BuildDemo._put(world, tower + Vector3i(0, 8, 0), BlockDB.LANTERN)
		report["lanterns"] += 1
	# Crenellations along the wall top (alternating).
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			if absi(dx) != 8 and absi(dz) != 8:
				continue
			if posmod(dx + dz, 2) == 0:
				placed += BuildDemo._put(world, anchor + Vector3i(dx, 5, dz), s)
	# Gatehouse on the south wall (z = +8): a 3-wide opening with a door.
	for dx in range(-1, 2):
		placed += BuildDemo._put(world, anchor + Vector3i(dx, 1, 8), BlockDB.AIR)
		placed += BuildDemo._put(world, anchor + Vector3i(dx, 2, 8), BlockDB.AIR)
	placed += BuildDemo._put(world, anchor + Vector3i(0, 1, 8), BlockDB.DOOR)
	placed += BuildDemo._put(world, anchor + Vector3i(0, 2, 8), BlockDB.DOOR)
	# Central keep, 9x9, stone base with a timber upper hall and a slate roof.
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var perimeter := absi(dx) == 4 or absi(dz) == 4
			placed += BuildDemo._put(world, anchor + Vector3i(dx, 0, dz), s)
			if not perimeter:
				continue
			for y in range(1, 5):
				var block_id := s if y < 4 else t
				if y == 4 and (absi(dx) == 4 and absi(dz) == 1):
					block_id = BlockDB.GLASS
				placed += BuildDemo._put(world, anchor + Vector3i(dx, y, dz), block_id)
	# Keep entrance and a framed upper window on the courtyard face.
	placed += BuildDemo._put(world, anchor + Vector3i(0, 1, 4), BlockDB.DOOR)
	placed += BuildDemo._put(world, anchor + Vector3i(0, 2, 4), BlockDB.DOOR)
	placed += BuildDemo._put(world, anchor + Vector3i(0, 4, 4), BlockDB.WINDOW)
	placed += BuildDemo._put(world, anchor + Vector3i(-1, 4, 4), BlockDB.SHUTTER)
	placed += BuildDemo._put(world, anchor + Vector3i(1, 4, 4), BlockDB.SHUTTER)
	# Keep roof: slate gable with a stone gable infill, finials and a chimney.
	# The roof is one wall row lower than the longhouse so its finial and
	# chimney stay inside the world height on the high final-demo plateau.
	var keep_roof: Dictionary = MedievalKit.build_gable_roof(world, anchor, 4, 4, 5,
		{"finials": true, "gable_infill": BlockDB.STONE_WALL,
		"gable_brace": BlockDB.STONE_WALL, "gable_post": BlockDB.DARK_TIMBER,
		"chimney": {"x": 2, "z": -2, "top": 10}})
	placed += int(keep_roof["pieces"])
	# A well and lanterns in the courtyard.
	placed += BuildDemo._put(world, anchor + Vector3i(-6, 1, -2), BlockDB.BARREL)
	placed += BuildDemo._put(world, anchor + Vector3i(6, 1, -2), BlockDB.CHEST)
	placed += BuildDemo._put(world, anchor + Vector3i(0, 3, 0), BlockDB.LANTERN)
	report["lanterns"] += 1
	return placed


# --- street, gardens and well ---------------------------------------------

static func _build_street(world: VoxelWorld, base: Vector3i, report: Dictionary) -> int:
	var placed := 0
	# Main east-west street through the village.
	for x in range(-24, 25):
		placed += BuildDemo._put(world, base + Vector3i(x, 0, 12), BlockDB.PATH)
		placed += BuildDemo._put(world, base + Vector3i(x, 0, 13), BlockDB.PATH if x % 4 != 0 else BlockDB.COBBLESTONE)
	# Branch north to the castle gate.
	for z in range(-6, 12):
		placed += BuildDemo._put(world, base + Vector3i(0, 0, z), BlockDB.PATH)
		placed += BuildDemo._put(world, base + Vector3i(1, 0, z), BlockDB.PATH)
	# Lantern posts along the street.
	for x in [-20, -10, 0, 20]:
		for z in [10, 15]:
			placed += BuildDemo._put(world, base + Vector3i(x, 1, z), BlockDB.FENCE)
			placed += BuildDemo._put(world, base + Vector3i(x, 2, z), BlockDB.LANTERN)
			report["lanterns"] += 1
	# Fenced garden plots on the south side of the street.
	for plot in 3:
		var gx := -24 + plot * 12
		for dz in range(16, 19):
			for dx in range(0, 5):
				placed += BuildDemo._put(world, base + Vector3i(gx + dx, 0, dz), BlockDB.DIRT)
		for dx in range(0, 5):
			placed += BuildDemo._put(world, base + Vector3i(gx + dx, 1, 16), BlockDB.FENCE)
		for dz in range(17, 19):
			for dx in range(0, 5, 2):
				placed += BuildDemo._put(world, base + Vector3i(gx + dx, 1, dz), BlockDB.WHEAT_3)
	return placed


## Plants a ring of trees around the settlement so it sits inside the natural
## landscape instead of on a bare plateau.  Uses the production tree shapes.
static func _plant_frame_trees(world: VoxelWorld, base: Vector3i, report: Dictionary) -> void:
	var types := [WorldGen.TreeType.OAK, WorldGen.TreeType.PINE, WorldGen.TreeType.BIRCH,
		WorldGen.TreeType.OAK, WorldGen.TreeType.PINE, WorldGen.TreeType.BIRCH,
		WorldGen.TreeType.OAK, WorldGen.TreeType.PINE, WorldGen.TreeType.OAK,
		WorldGen.TreeType.BIRCH, WorldGen.TreeType.PINE, WorldGen.TreeType.OAK]
	var spots := [Vector2i(-28, -22), Vector2i(-25, -28), Vector2i(-12, -28),
		Vector2i(8, -28), Vector2i(24, -27), Vector2i(28, -12), Vector2i(28, 8),
		Vector2i(26, 24), Vector2i(-28, 22), Vector2i(-27, 8)]
	var planted := 0
	for index in spots.size():
		var spot: Vector2i = spots[index]
		planted += world.generator.plant_tree(world, base.x + spot.x, base.z + spot.y,
			int(types[index % types.size()]), base.y)
	report["trees"] = planted
	report["blocks"] += planted


static func _build_well(world: VoxelWorld, anchor: Vector3i) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			BuildDemo._put(world, anchor + Vector3i(dx, 0, dz), BlockDB.COBBLESTONE)
	BuildDemo._put(world, anchor + Vector3i(0, 0, 0), BlockDB.WATER)
	for y in [1, 2]:
		for dz in [-1, 1]:
			for dx in [-1, 1]:
				BuildDemo._put(world, anchor + Vector3i(dx, y, dz), BlockDB.OAK_LOG)
	for dx in range(-1, 2):
		BuildDemo._put(world, anchor + Vector3i(dx, 3, -1), BlockDB.TIMBER_FRAME)
		BuildDemo._put(world, anchor + Vector3i(dx, 3, 1), BlockDB.TIMBER_FRAME)
	BuildDemo._put(world, anchor + Vector3i(0, 4, 0), BlockDB.LANTERN)


static func _count_stairs(world: VoxelWorld, base: Vector3i) -> int:
	var count := 0
	for dz in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			for y in range(base.y, base.y + 10):
				if world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.STAIR \
						or world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.SLATE_STAIR \
						or world.get_block(Vector3i(base.x + dx, y, base.z + dz)) == BlockDB.SLATE_RAMP:
					count += 1
	return count
