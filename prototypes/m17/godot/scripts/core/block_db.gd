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

const COUNT := 35

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
static var render_layers: PackedByteArray = PackedByteArray()
static var solid: PackedByteArray = PackedByteArray()
static var opaque: PackedByteArray = PackedByteArray()
static var cull_same: PackedByteArray = PackedByteArray()
static var liquid: PackedByteArray = PackedByteArray()
static var hardness: PackedFloat32Array = PackedFloat32Array()
static var face_keys: Array = []
static var drops: PackedInt32Array = PackedInt32Array()
static var light_emission: PackedByteArray = PackedByteArray()


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
		["Oak Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.OAK_LEAVES, ["oak_leaves", "oak_leaves", "oak_leaves"]],
		["Cobblestone", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.COBBLESTONE, ["cobble", "cobble", "cobble"]],
		["Planks", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.PLANKS, ["planks", "planks", "planks"]],
		["Glass", BlockDB.LAYER_BLEND, 1, 0, 1, 0, 0.3, BlockDB.NO_DROP, ["glass", "glass", "glass"]],
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
		["Pine Leaves", BlockDB.LAYER_CUTOUT, 1, 0, 1, 0, 0.2, BlockDB.PINE_LEAVES, ["pine_leaves", "pine_leaves", "pine_leaves"]],
		["Grass Tuft", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_1", "deco_grass_2", "deco_grass_3"]],
		["Tall Grass", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_4", "deco_grass_5", "deco_grass_3"]],
		["Jungle Grass", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_jungle_grass", "deco_jungle_grass", "deco_grass_2"]],
		["Fern", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_grass_5", "deco_grass_2", "deco_grass_1"]],
		["Dry Shrub", BlockDB.LAYER_DECO, 0, 0, 0, 0, 0.05, BlockDB.NO_DROP, ["deco_dry_grass", "deco_dry_grass", "deco_dry_grass"]],
		["Crafting Table", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 2.0, BlockDB.CRAFTING_TABLE, ["planks", "planks", "planks"]],
		["Furnace", BlockDB.LAYER_OPAQUE, 1, 1, 0, 0, 3.5, BlockDB.FURNACE, ["furnace_top", "furnace_side", "furnace_top"]],
	]
	if definitions.size() != COUNT:
		push_error("BlockDB: definition table has %d rows, expected %d" % [definitions.size(), COUNT])
	for definition: Array in definitions:
		names.append(str(definition[0]))
		render_layers.append(int(definition[1]))
		solid.append(int(definition[2]))
		opaque.append(int(definition[3]))
		cull_same.append(int(definition[4]))
		liquid.append(int(definition[5]))
		hardness.append(float(definition[6]))
		drops.append(int(definition[7]))
		face_keys.append(_expand_faces(definition[8]))


static func _expand_faces(triple: Array) -> PackedStringArray:
	var top := str(triple[0])
	var side := str(triple[1])
	var bottom := str(triple[2])
	return PackedStringArray([side, side, top, bottom, side, side])


static func is_air(block_id: int) -> bool:
	return block_id == AIR


static func is_solid(block_id: int) -> bool:
	return block_id >= 0 and block_id < solid.size() and solid[block_id] == 1


static func is_opaque(block_id: int) -> bool:
	return block_id >= 0 and block_id < opaque.size() and opaque[block_id] == 1


static func is_liquid(block_id: int) -> bool:
	return block_id >= 0 and block_id < liquid.size() and liquid[block_id] == 1


static func is_deco(block_id: int) -> bool:
	return block_id >= 0 and block_id < solid.size() and solid[block_id] == 0 and block_id != AIR and not is_liquid(block_id)


static func is_breakable(block_id: int) -> bool:
	return block_id != AIR and not is_liquid(block_id) and block_id >= 0 and block_id < hardness.size() and hardness[block_id] >= 0.0


## Faces hidden when the neighbour has the same id *and* the block culls equal
## neighbours (glass panes, and every opaque block).
static func hides_neighbour_face(block_id: int, neighbour_id: int) -> bool:
	if neighbour_id == AIR:
		return false
	if is_liquid(block_id):
		return is_liquid(neighbour_id)
	if is_opaque(neighbour_id):
		return true
	if neighbour_id == block_id and cull_same[block_id] == 1:
		return true
	return false


static func name_of(block_id: int) -> String:
	if block_id >= 0 and block_id < names.size():
		return names[block_id]
	return "Unknown"


static func drop_of(block_id: int) -> int:
	if block_id >= 0 and block_id < drops.size():
		return drops[block_id]
	return NO_DROP


## Block id used for the mesh layer index of the given id.
static func layer_of(block_id: int) -> int:
	if block_id >= 0 and block_id < render_layers.size():
		return render_layers[block_id]
	return LAYER_OPAQUE
