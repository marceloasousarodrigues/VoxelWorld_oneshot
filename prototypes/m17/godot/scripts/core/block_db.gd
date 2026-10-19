class_name BlockDB
extends RefCounted

## Central, extensible block definitions for the M17 Godot voxel game.
##
## The first five ids deliberately match the shared M17 contract palette
## (`prototypes/m17/shared/scenario.json`): AIR 0, GRASS 1, DIRT 2, STONE 3,
## WATER 4.  New blocks are appended so the shared fixture remains loadable.
##
## Every property is stored in a packed array indexed by block id so the mesher
## and world code can query definitions without dictionary lookups.

# --- shared palette (contract) ---------------------------------------------
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const WATER := 4

# --- appended blocks -------------------------------------------------------
const SAND := 5
const OAK_LOG := 6
const OAK_LEAVES := 7
const COBBLESTONE := 8
const PLANKS := 9
const GLASS := 10
const GRAVEL := 11
const SNOW := 12
const CACTUS := 13
const SANDSTONE := 14
const COAL_ORE := 15
const IRON_ORE := 16
const GOLD_ORE := 17
const DIAMOND_ORE := 18
const BEDROCK := 19
const CLAY := 20
const BRICK := 21
const STONE_BRICK := 22
const MOSSY_COBBLE := 23
const OBSIDIAN := 24
const DRY_GRASS := 25
const PINE_LOG := 26
const PINE_LEAVES := 27
const GRASS_TUFT := 28
const TALL_GRASS := 29
const JUNGLE_GRASS := 30
const FERN := 31
const DRY_SHRUB := 32
const CRAFTING_TABLE := 33
const FURNACE := 34

# --- M21 farming and storage blocks ---------------------------------------
# Ids 35..60 are the existing material/tool item definitions in `ItemDB`; they
# are therefore *undefined block slots* in this table.  Keeping the historical
# item ids stable is what lets existing saves load unchanged.  New world blocks
# continue after that range.
const FARMLAND := 61
const WHEAT_0 := 62
const WHEAT_1 := 63
const WHEAT_2 := 64
const WHEAT_3 := 65
const CHEST := 66

# --- M22 vegetation and medieval architecture ------------------------------
# Ids 67..72 are the M21 animal/farming item ids in `ItemDB`, so the new block
# ids start after the whole non-block item range.  Keeping that gap is what lets
# existing saves resolve every item unchanged.
const BIRCH_LOG := 73
const BIRCH_LEAVES := 74
const BLOSSOM_LEAVES := 75
const BUSH := 76
const FLOWER_RED := 77
const FLOWER_YELLOW := 78
const FLOWER_BLUE := 79
const TIMBER_FRAME := 80
const ROOF_TILE := 81
const ROOF_RIDGE := 82
const PATH := 83
const LANTERN := 84
const FENCE := 85
const BARREL := 86
const DOOR := 87

const COUNT := 88
## Number of ids in 0..COUNT-1 that are real blocks (the item-id ranges 35..60
## and 67..72 are deliberately undefined here).
const DEFINED_COUNT := 56

# --- render layers ---------------------------------------------------------
const LAYER_OPAQUE := 0
const LAYER_CUTOUT := 1
const LAYER_BLEND := 2
const LAYER_WATER := 3
const LAYER_DECO := 4
const LAYER_COUNT := 5

# --- face order (matches FACE_NORMALS in the mesher) -----------------------
const FACE_PX := 0
const FACE_NX := 1
const FACE_PY := 2
const FACE_NY := 3
const FACE_PZ := 4
const FACE_NZ := 5

const NO_DROP := -1

static var names: PackedStringArray = PackedStringArray()
## 1 for a real block id, 0 for the item-id range that shares the numeric space.
static var defined: PackedByteArray = PackedByteArray()
static var render_layers: PackedByteArray = PackedByteArray()
static var solid: PackedByteArray = PackedByteArray()
static var opaque: PackedByteArray = PackedByteArray()
## Blocks whose render model is intentionally not a full cube (the crafting
## table and furnace).  They remain solid and opaque for logic/collision, but
## they must not cull the faces of neighbouring blocks: the open space under the
## table would otherwise leave a hole in the ground below it.
static var open_model: PackedByteArray = PackedByteArray()
static var cull_same: PackedByteArray = PackedByteArray()
static var liquid: PackedByteArray = PackedByteArray()
## Blocks whose visible model is built by a custom one-cell emitter (stations,
## barrel, lantern, fence) rather than the cube / crossed-quad paths.
static var custom_model: PackedByteArray = PackedByteArray()
static var hardness: PackedFloat32Array = PackedFloat32Array()
static var face_keys: Array = []
static var drops: PackedInt32Array = PackedInt32Array()
static var light_emission: PackedByteArray = PackedByteArray()
## Fraction of the voxel height a decorative crossed-quad model occupies.  Crop
## stages grow from 0.35 to a full block; every other deco block stays at 1.0.
static var deco_height: PackedFloat32Array = PackedFloat32Array()


static func _static_init() -> void:
	var definitions: Array = [
		# name, layer, solid, opaque, cull_same, liquid, hardness, drop, faces(top, side, bottom)
		["Air", BlockDB.LAYER_OPAQUE, 0, 0, 0, 0, 0.0, BlockDB.NO_DROP, ["", "", ""]],
		["Grass", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.DIRT, ["grass_top", "grass_side", "dirt"]],
		["Dirt", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.5, BlockDB.DIRT, ["dirt", "dirt", "dirt"]],
		["Stone", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 1.5, BlockDB.COBBLESTONE, ["stone", "stone", "stone"]],
		["Water", BlockDB.LAYER_WATER, 0, 0, 0, 1, -1.0, BlockDB.NO_DROP, ["water", "water", "water"]],
		["Sand", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.5, BlockDB.SAND, ["sand", "sand", "sand"]],
		["Oak Log", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.OAK_LOG, ["oak_log_top", "oak_log_side", "oak_log_top"]],
		["Oak Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.OAK_LEAVES, ["oak_leaves_clean", "oak_leaves_clean", "oak_leaves_clean"]],
		["Cobblestone", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.COBBLESTONE, ["cobble", "cobble", "cobble"]],
		["Planks", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.PLANKS, ["planks", "planks", "planks"]],
		["Glass", BlockDB.LAYER_BLEND, 1, 0, 1, 0, 0.3, BlockDB.NO_DROP, ["glass_clean", "glass_clean", "glass_clean"]],
		["Gravel", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.GRAVEL, ["gravel", "gravel", "gravel"]],
		["Snow", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.4, BlockDB.SNOW, ["snow", "snow", "snow"]],
		["Cactus", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.4, BlockDB.CACTUS, ["cactus_top", "cactus_side", "cactus_top"]],
		["Sandstone", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.8, BlockDB.SANDSTONE, ["sandstone", "sandstone", "sandstone"]],
		["Coal Ore", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.0, BlockDB.COAL_ORE, ["coal_ore", "coal_ore", "coal_ore"]],
		["Iron Ore", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.0, BlockDB.IRON_ORE, ["iron_ore", "iron_ore", "iron_ore"]],
		["Gold Ore", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.0, BlockDB.GOLD_ORE, ["gold_ore", "gold_ore", "gold_ore"]],
		["Diamond Ore", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.5, BlockDB.DIAMOND_ORE, ["diamond_ore", "diamond_ore", "diamond_ore"]],
		["Bedrock", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, -1.0, BlockDB.NO_DROP, ["bedrock", "bedrock", "bedrock"]],
		["Clay", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.CLAY, ["clay", "clay", "clay"]],
		["Brick", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.BRICK, ["brick", "brick", "brick"]],
		["Stone Brick", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.STONE_BRICK, ["stone_brick", "stone_brick", "stone_brick"]],
		["Mossy Cobblestone", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.MOSSY_COBBLE, ["mossy_cobble", "mossy_cobble", "mossy_cobble"]],
		["Obsidian", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 5.0, BlockDB.OBSIDIAN, ["obsidian", "obsidian", "obsidian"]],
		["Dry Grass", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.DIRT, ["dry_grass_top", "dry_grass_side", "dirt"]],
		["Pine Log", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.PINE_LOG, ["pine_log_top", "pine_log_side", "pine_log_top"]],
		["Pine Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.PINE_LEAVES, ["pine_leaves_clean", "pine_leaves_clean", "pine_leaves_clean"]],
		["Grass Tuft", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_1", "deco_grass_2", "deco_grass_3"]],
		["Tall Grass", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_4", "deco_grass_5", "deco_grass_3"]],
		["Jungle Grass", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_jungle_grass", "deco_jungle_grass", "deco_grass_2"]],
		["Fern", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_5", "deco_grass_2", "deco_grass_1"]],
		["Dry Shrub", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_dry_grass", "deco_dry_grass", "deco_dry_grass"]],
		["Crafting Table", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.CRAFTING_TABLE, ["crafting_table_top", "crafting_table_side", "planks"]],
		["Furnace", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.5, BlockDB.FURNACE, ["furnace_top", "furnace_side", "furnace_top"]],
	]
	# Ids 35..60 are the existing material/tool item definitions.  They are not
	# blocks; placeholders keep the packed arrays indexable by the unchanged ids.
	while definitions.size() < FARMLAND:
		definitions.append(["", BlockDB.LAYER_OPAQUE, 0, 0, 0, 0, 0.0, BlockDB.NO_DROP, ["", "", ""]])
	definitions.append_array([
		# name, layer, solid, opaque, cull, liquid, hardness, drop, faces
		["Farmland", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.DIRT,
			["farmland_top", "farmland_side", "dirt"]],
		["Wheat Sprout", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP,
			["wheat_stage_0", "wheat_stage_0", "wheat_stage_0"]],
		["Wheat Crop", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP,
			["wheat_stage_1", "wheat_stage_1", "wheat_stage_1"]],
		["Wheat Crop", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP,
			["wheat_stage_2", "wheat_stage_2", "wheat_stage_2"]],
		["Ripe Wheat", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP,
			["wheat_stage_3", "wheat_stage_3", "wheat_stage_3"]],
		["Storage Chest", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.CHEST,
			["planks", "planks", "planks"]],
	])
	# Ids 67..72 are non-block item ids (raw meat, hide, seeds, ...).  Leave those
	# slots undefined in the block table, exactly like the 35..60 tool range.
	while definitions.size() < BIRCH_LOG:
		definitions.append(["", BlockDB.LAYER_OPAQUE, 0, 0, 0, 0, 0.0, BlockDB.NO_DROP, ["", "", ""]])
	definitions.append_array([
		# name, layer, solid, opaque, cull, liquid, hardness, drop, faces
		["Birch Log", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.BIRCH_LOG,
			["birch_log_top", "birch_log_side", "birch_log_top"]],
		["Birch Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.BIRCH_LEAVES,
			["birch_leaves_clean", "birch_leaves_clean", "birch_leaves_clean"]],
		["Blossom Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.BLOSSOM_LEAVES,
			["blossom_leaves_clean", "blossom_leaves_clean", "blossom_leaves_clean"]],
		["Bush", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.1, BlockDB.BUSH,
			["deco_bush", "deco_bush", "deco_bush"]],
		["Red Flower", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.FLOWER_RED,
			["deco_flower_red", "deco_flower_red", "deco_flower_red"]],
		["Yellow Flower", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.FLOWER_YELLOW,
			["deco_flower_yellow", "deco_flower_yellow", "deco_flower_yellow"]],
		["Blue Flower", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.FLOWER_BLUE,
			["deco_flower_blue", "deco_flower_blue", "deco_flower_blue"]],
		["Timber Frame", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.TIMBER_FRAME,
			["timber_frame", "timber_frame", "timber_frame"]],
		["Roof Tile", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.ROOF_TILE,
			["roof_tile", "roof_side", "roof_side"]],
		["Roof Ridge", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.ROOF_RIDGE,
			["roof_ridge", "roof_side", "roof_side"]],
		["Packed Path", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 0.6, BlockDB.PATH,
			["path_top", "path_side", "dirt"]],
		["Lantern", BlockDB.LAYER_OPAQUE, 0, 0, 0, 0, 0.3, BlockDB.LANTERN,
			["lantern_top", "lantern_side", "lantern_top"]],
		["Fence", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 1.4, BlockDB.FENCE,
			["fence", "fence", "fence"]],
		["Barrel", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 1.4, BlockDB.BARREL,
			["barrel_top", "barrel_side", "barrel_top"]],
		["Door", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 1.8, BlockDB.DOOR,
			["door", "door", "door"]],
	])
	if definitions.size() != COUNT:
		push_error("BlockDB: definition table has %d rows, expected %d" % [definitions.size(), COUNT])
	for definition: Array in definitions:
		var display_name := str(definition[0])
		names.append(display_name)
		defined.append(1 if not display_name.is_empty() else 0)
		render_layers.append(int(definition[1]))
		solid.append(int(definition[2]))
		opaque.append(int(definition[3]))
		cull_same.append(int(definition[4]))
		liquid.append(int(definition[5]))
		hardness.append(float(definition[6]))
		drops.append(int(definition[7]))
		face_keys.append(_expand_faces(definition[8]))
		open_model.append(0)
		custom_model.append(0)
		deco_height.append(1.0)
	open_model[CRAFTING_TABLE] = 1
	open_model[FURNACE] = 1
	open_model[CHEST] = 1
	for block_id: int in [CRAFTING_TABLE, FURNACE, CHEST, LANTERN, FENCE, BARREL]:
		custom_model[block_id] = 1
		# A one-cell detail model does not fill the cube: the block it sits on
		# must keep its top face.
		open_model[block_id] = 1
	# Crop stages visibly grow inside the voxel cell.
	deco_height[WHEAT_0] = 0.34
	deco_height[WHEAT_1] = 0.56
	deco_height[WHEAT_2] = 0.78
	deco_height[WHEAT_3] = 1.0
	deco_height[BUSH] = 0.92
	deco_height[FLOWER_RED] = 0.60
	deco_height[FLOWER_YELLOW] = 0.60
	deco_height[FLOWER_BLUE] = 0.60
	if defined.size() != COUNT or _defined_total() != DEFINED_COUNT:
		push_error("BlockDB: defined block count is %d, expected %d" % [_defined_total(), DEFINED_COUNT])


static func _expand_faces(triple: Array) -> PackedStringArray:
	var top := str(triple[0])
	var side := str(triple[1])
	var bottom := str(triple[2])
	return PackedStringArray([side, side, top, bottom, side, side])


static func is_air(block_id: int) -> bool:
	return block_id == AIR


## True when the id names a real block.  The numeric space also contains the
## material/tool item ids (35..60); those must never be treated as world blocks.
static func is_defined(block_id: int) -> bool:
	return block_id >= 0 and block_id < defined.size() and defined[block_id] == 1


static func is_solid(block_id: int) -> bool:
	return is_defined(block_id) and solid[block_id] == 1


static func is_opaque(block_id: int) -> bool:
	return is_defined(block_id) and opaque[block_id] == 1


## True for stations whose custom render model is not a full cube.  They still
## occlude for gameplay/collision, but their neighbours' faces stay visible.
static func is_open_model(block_id: int) -> bool:
	return is_defined(block_id) and open_model[block_id] == 1


## True for a block whose visible geometry is emitted by a custom one-cell model
## (stations, barrel, lantern, fence) instead of the cube/crossed-quad paths.
static func is_custom_model(block_id: int) -> bool:
	return is_defined(block_id) and custom_model[block_id] == 1


## Flowers keep their own colour; biome tint applies to green vegetation only.
static func is_flower(block_id: int) -> bool:
	return block_id == FLOWER_RED or block_id == FLOWER_YELLOW or block_id == FLOWER_BLUE


static func is_liquid(block_id: int) -> bool:
	return is_defined(block_id) and liquid[block_id] == 1


static func is_deco(block_id: int) -> bool:
	return is_defined(block_id) and solid[block_id] == 0 and block_id != AIR and not is_liquid(block_id)


static func is_breakable(block_id: int) -> bool:
	return is_defined(block_id) and block_id != AIR and not is_liquid(block_id) and hardness[block_id] >= 0.0


## Faces hidden when the neighbour has the same id *and* the block culls equal
## neighbours (glass panes, and every opaque block).
static func hides_neighbour_face(block_id: int, neighbour_id: int) -> bool:
	if neighbour_id == AIR:
		return false
	if is_liquid(block_id):
		return is_liquid(neighbour_id)
	# An open station model (table/furnace) does not fill its voxel cube, so it
	# must not hide the face of the block it sits on or beside.
	if is_open_model(neighbour_id):
		return false
	if is_opaque(neighbour_id):
		return true
	if neighbour_id == block_id and cull_same[block_id] == 1:
		return true
	return false


static func name_of(block_id: int) -> String:
	if is_defined(block_id):
		return names[block_id]
	return "Unknown"


static func drop_of(block_id: int) -> int:
	if is_defined(block_id):
		return drops[block_id]
	return NO_DROP


## Block id used for the mesh layer index of the given id.
static func layer_of(block_id: int) -> int:
	if is_defined(block_id):
		return render_layers[block_id]
	return LAYER_OPAQUE


static func _defined_total() -> int:
	var total := 0
	for value in defined:
		total += value
	return total
