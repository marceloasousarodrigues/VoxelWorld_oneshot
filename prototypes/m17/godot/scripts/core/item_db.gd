class_name ItemDB
extends RefCounted

## Central item definitions for the M17 Godot game.
##
## Item ids are a superset of block ids: `0 .. BlockDB.COUNT - 1` are the block
## items (so a block id is still an item id and every existing block lookup keeps
## working), and the ids above that are the non-block items -- materials, food and
## tools.  This keeps one flat namespace for the inventory, the hotbar, crafting
## and persistence while leaving `BlockDB` the single source of truth for blocks.
##
## Everything here is static, pure data: no scene tree, no world, no engine
## resources.  Minecraft-like conventions are used where they are legible
## (64-stack for materials, tool tiers, per-class mining speed), simplified where
## a rule would only add clicks.

const BLOCK_COUNT := BlockDB.COUNT

# --- non-block item ids ---------------------------------------------------

const STICK := 35
const COAL := 36
const IRON_LUMP := 37
const IRON_INGOT := 38
const GOLD_LUMP := 39
const DIAMOND := 40
const WHEAT := 41
const APPLE := 42
const BREAD := 43
const GOLDEN_APPLE := 44

const WOOD_PICKAXE := 45
const WOOD_AXE := 46
const WOOD_SHOVEL := 47
const WOOD_SWORD := 48
const STONE_PICKAXE := 49
const STONE_AXE := 50
const STONE_SHOVEL := 51
const STONE_SWORD := 52
const IRON_PICKAXE := 53
const IRON_AXE := 54
const IRON_SHOVEL := 55
const IRON_SWORD := 56
const DIAMOND_PICKAXE := 57
const DIAMOND_AXE := 58
const DIAMOND_SHOVEL := 59
const DIAMOND_SWORD := 60

# --- M21 animal, cooking and farming items --------------------------------
# Block ids 61..66 are the M21 world blocks (farmland, four wheat stages, chest),
# so the new non-block items continue after them.  The item namespace stays a
# superset of every existing id; only `is_valid`/`is_block` need to distinguish a
# definition from a block id.
const RAW_MEAT := 67
const COOKED_MEAT := 68
const HIDE := 69
const BONE := 70
const WHEAT_SEEDS := 71
const BONE_MEAL := 72

const COUNT := BlockDB.COUNT

## `BlockDB.AIR` as an item id: "no item".
const AIR := BlockDB.AIR
const NO_ITEM := -1

## Materials and blocks stack; tools and food do not (a stack of one).
const MAX_STACK := 64

enum Tool { NONE, PICKAXE, AXE, SHOVEL, SWORD }
enum Tier { HAND, WOOD, STONE, IRON, DIAMOND }

const TOOL_NAMES := ["", "Pickaxe", "Axe", "Shovel", "Sword"]
const TIER_NAMES := ["Hand", "Wooden", "Stone", "Iron", "Diamond"]

## Tool-tier numbers, mining speeds (multiplier over the bare hand), durability
## in blocks and raw attack damage.
const TIER_SPEED := {Tier.WOOD: 2.0, Tier.STONE: 4.0, Tier.IRON: 6.0, Tier.DIAMOND: 8.0}
const TIER_DURABILITY := {Tier.WOOD: 60, Tier.STONE: 132, Tier.IRON: 251, Tier.DIAMOND: 1562}
const SWORD_DAMAGE := {Tier.WOOD: 4.0, Tier.STONE: 5.0, Tier.IRON: 6.0, Tier.DIAMOND: 7.0}
const UTENSIL_DAMAGE := {Tier.WOOD: 2.0, Tier.STONE: 3.0, Tier.IRON: 4.0, Tier.DIAMOND: 5.0}

## Seconds per unit of block hardness with the bare hand.  Every tool speed is a
## multiplier on top of this, so the numbers stay small enough to mine by hand
## for the starting resources while still rewarding the right tool.
const HAND_SECONDS_PER_HARDNESS := 0.5
const MIN_BREAK_SECONDS := 0.05
## A sword is the wrong tool for everything, but faster than a bare hand.
const SWORD_BLOCK_FACTOR := 1.5

## Tool class that speeds a block up, by block id.  `Tool.NONE` means "hand
## speed, hand speed is already the best".
static var _effective_tool: Dictionary = {}
## Tool class and tier a block *requires* before it drops anything.
static var _required_tool: Dictionary = {}
static var _required_tier: Dictionary = {}

## item id -> definition dictionary for the non-block items.
static var _definitions: Dictionary = {}


static func _static_init() -> void:
	_definitions = {
		STICK: _def("Stick", "item_stick"),
		COAL: _def("Coal", "item_coal"),
		IRON_LUMP: _def("Iron Lump", "item_iron_lump"),
		IRON_INGOT: _def("Iron Ingot", "item_iron_ingot"),
		GOLD_LUMP: _def("Gold Lump", "item_gold_lump"),
		DIAMOND: _def("Diamond", "item_diamond"),
		WHEAT: _def("Wheat", "item_wheat"),
		APPLE: _def("Apple", "item_apple", 0.0, 4.0),
		BREAD: _def("Bread", "item_bread", 0.0, 6.0),
		GOLDEN_APPLE: _def("Golden Apple", "item_apple", 0.0, 10.0, 4.0, Color(1.0, 0.85, 0.25)),
		# M21 hunting, cooking and farming materials.  Raw meat is edible but a
		# poor meal; cooking it is the useful, deliberate step.
		RAW_MEAT: _def("Raw Meat", "item_raw_meat", 0.0, 2.0),
		COOKED_MEAT: _def("Cooked Meat", "item_cooked_meat", 0.0, 8.0, 1.0),
		HIDE: _def("Hide", "item_hide"),
		BONE: _def("Bone", "item_bone"),
		WHEAT_SEEDS: _def("Wheat Seeds", "item_wheat_seeds"),
		BONE_MEAL: _def("Bone Meal", "item_bone_meal"),
	}
	var tool_specs: Array = [
		[WOOD_PICKAXE, Tier.WOOD, Tool.PICKAXE], [WOOD_AXE, Tier.WOOD, Tool.AXE],
		[WOOD_SHOVEL, Tier.WOOD, Tool.SHOVEL], [WOOD_SWORD, Tier.WOOD, Tool.SWORD],
		[STONE_PICKAXE, Tier.STONE, Tool.PICKAXE], [STONE_AXE, Tier.STONE, Tool.AXE],
		[STONE_SHOVEL, Tier.STONE, Tool.SHOVEL], [STONE_SWORD, Tier.STONE, Tool.SWORD],
		[IRON_PICKAXE, Tier.IRON, Tool.PICKAXE], [IRON_AXE, Tier.IRON, Tool.AXE],
		[IRON_SHOVEL, Tier.IRON, Tool.SHOVEL], [IRON_SWORD, Tier.IRON, Tool.SWORD],
		[DIAMOND_PICKAXE, Tier.DIAMOND, Tool.PICKAXE], [DIAMOND_AXE, Tier.DIAMOND, Tool.AXE],
		[DIAMOND_SHOVEL, Tier.DIAMOND, Tool.SHOVEL], [DIAMOND_SWORD, Tier.DIAMOND, Tool.SWORD],
	]
	for spec: Array in tool_specs:
		var item_id := int(spec[0])
		var tier := int(spec[1])
		var tool := int(spec[2])
		var damage: float = float(SWORD_DAMAGE[tier] if tool == Tool.SWORD else UTENSIL_DAMAGE[tier])
		_definitions[item_id] = {
			"name": "%s %s" % [TIER_NAMES[tier], TOOL_NAMES[tool]],
			"icon": "item_tool_%s_%s" % [
				["", "wood", "stone", "iron", "diamond"][tier],
				["", "pick", "axe", "shovel", "sword"][tool],
			],
			"stack": 1,
			"tool": tool,
			"tier": tier,
			"speed": float(TIER_SPEED[tier]),
			"durability": int(TIER_DURABILITY[tier]),
			"damage": damage,
			"food": 0.0,
			"heal": 0.0,
			"tint": Color.WHITE,
		}

	# Which tool speeds a block up, and whether a block needs one to drop.
	for block_id in BlockDB.COUNT:
		_effective_tool[block_id] = Tool.NONE
		_required_tool[block_id] = Tool.NONE
		_required_tier[block_id] = Tier.HAND
	# Stone-family blocks and ores: a pickaxe speeds them up *and* is required for
	# the drop (the tier requirement below raises it further for the deep ores).
	for block_id: int in [BlockDB.STONE, BlockDB.COBBLESTONE, BlockDB.STONE_BRICK,
			BlockDB.MOSSY_COBBLE, BlockDB.BRICK, BlockDB.SANDSTONE, BlockDB.OBSIDIAN,
			BlockDB.COAL_ORE, BlockDB.IRON_ORE, BlockDB.GOLD_ORE, BlockDB.DIAMOND_ORE,
			BlockDB.FURNACE]:
		_effective_tool[block_id] = Tool.PICKAXE
		_required_tool[block_id] = Tool.PICKAXE
	# Glass is soft and drops nothing either way, so a pickaxe only speeds it up.
	_effective_tool[BlockDB.GLASS] = Tool.PICKAXE
	# Wood family: an axe speeds it up; the drop never needs the axe.
	for block_id: int in [BlockDB.OAK_LOG, BlockDB.PINE_LOG, BlockDB.BIRCH_LOG, BlockDB.PLANKS,
			BlockDB.CRAFTING_TABLE, BlockDB.CACTUS, BlockDB.TIMBER_FRAME, BlockDB.FENCE,
			BlockDB.BARREL, BlockDB.DOOR]:
		_effective_tool[block_id] = Tool.AXE
	# Soft ground: a shovel speeds it up, hand is always good enough.
	for block_id: int in [BlockDB.GRASS, BlockDB.DIRT, BlockDB.SAND, BlockDB.GRAVEL,
			BlockDB.SNOW, BlockDB.DRY_GRASS, BlockDB.CLAY, BlockDB.PATH]:
		_effective_tool[block_id] = Tool.SHOVEL
	# Fired roof tiles are masonry.
	for block_id: int in [BlockDB.ROOF_TILE, BlockDB.ROOF_RIDGE]:
		_effective_tool[block_id] = Tool.PICKAXE
	# Ores and obsidian need a better pick than the minimum.
	_required_tier[BlockDB.IRON_ORE] = Tier.STONE
	_required_tier[BlockDB.GOLD_ORE] = Tier.IRON
	_required_tier[BlockDB.DIAMOND_ORE] = Tier.IRON
	_required_tier[BlockDB.OBSIDIAN] = Tier.DIAMOND


static func _def(name: String, icon: String, durability: float = 0.0, food: float = 0.0,
		heal: float = 0.0, tint: Color = Color.WHITE) -> Dictionary:
	return {
		"name": name, "icon": icon, "stack": MAX_STACK, "tool": Tool.NONE,
		"tier": Tier.HAND, "speed": 1.0, "durability": int(durability),
		"damage": 1.0, "food": food, "heal": heal, "tint": tint,
	}


# --- identity -------------------------------------------------------------

static func is_valid(item_id: int) -> bool:
	# Definitions win over the block range: the M21 block ids (farmland, crops,
	# chest) live above the existing material ids, so a plain `id < BLOCK_COUNT`
	# test would misclassify every material and tool between 35 and 60 as a block.
	return _definitions.has(item_id) or BlockDB.is_defined(item_id)


## True when the id can be placed into the voxel world as a block.
static func is_block(item_id: int) -> bool:
	return not _definitions.has(item_id) and BlockDB.is_defined(item_id) \
		and item_id > BlockDB.AIR and item_id != BlockDB.WATER


## The block a placeable item produces, or `BlockDB.NO_DROP` when it is not
## placeable at all.
static func placeable_block(item_id: int) -> int:
	return item_id if is_block(item_id) else BlockDB.NO_DROP


static func name_of(item_id: int) -> String:
	if _definitions.has(item_id):
		return str(_definitions[item_id].get("name", "Unknown"))
	if BlockDB.is_defined(item_id):
		return BlockDB.name_of(item_id)
	return "Unknown"


## Texture-atlas key for the HUD icon of an item.
static func icon_key(item_id: int) -> String:
	if _definitions.has(item_id):
		return str(_definitions[item_id].get("icon", ""))
	if item_id == BlockDB.AIR or not BlockDB.is_defined(item_id):
		return ""
	# A few custom models read better as their side texture in the HUD than as
	# their top face.
	if item_id == BlockDB.LANTERN:
		return "lantern_side"
	if item_id == BlockDB.FENCE:
		return "fence"
	return (BlockDB.face_keys[item_id] as PackedStringArray)[BlockDB.FACE_PY]


## Optional icon tint (the golden apple reuses the apple texture).
static func icon_tint(item_id: int) -> Color:
	return _definition(item_id).get("tint", Color.WHITE)


static func max_stack(item_id: int) -> int:
	if _definitions.has(item_id):
		return int(_definitions[item_id].get("stack", MAX_STACK))
	return MAX_STACK if BlockDB.is_defined(item_id) else 1


static func max_durability(item_id: int) -> int:
	return int(_definition(item_id).get("durability", 0))


## True when the item is a tool (as opposed to a block, material or food).
## (Named `is_tool_item` because `Object.is_tool()` already exists.)
static func is_tool_item(item_id: int) -> bool:
	return int(_definition(item_id).get("tool", Tool.NONE)) != Tool.NONE


static func tool_class(item_id: int) -> int:
	return int(_definition(item_id).get("tool", Tool.NONE))


static func tier(item_id: int) -> int:
	return int(_definition(item_id).get("tier", Tier.HAND))


static func mining_speed(item_id: int) -> float:
	return float(_definition(item_id).get("speed", 1.0))


static func attack_damage(item_id: int) -> float:
	return float(_definition(item_id).get("damage", 1.0))


## Food points restored by eating the item (0 when it is not edible).
static func food_value(item_id: int) -> float:
	return float(_definition(item_id).get("food", 0.0))


## Extra health restored by eating the item.
static func heal_value(item_id: int) -> float:
	return float(_definition(item_id).get("heal", 0.0))


static func is_food(item_id: int) -> bool:
	return food_value(item_id) > 0.0


## Human-readable description of a tool's class and tier, e.g. "Stone Pickaxe".
static func describe(item_id: int) -> String:
	if not is_tool_item(item_id):
		return name_of(item_id)
	return "%s %s" % [tier_name(tier(item_id)), tool_name(tool_class(item_id))]


static func tool_name(tool: int) -> String:
	if tool >= 0 and tool < TOOL_NAMES.size():
		return TOOL_NAMES[tool]
	return "Tool"


static func tier_name(value: int) -> String:
	if value >= 0 and value < TIER_NAMES.size():
		return TIER_NAMES[value]
	return "Hand"


# --- mining rules ---------------------------------------------------------

## Tool class that mines the block fastest (never `NONE` for a hand-fast block).
static func effective_tool(block_id: int) -> int:
	return int(_effective_tool.get(block_id, Tool.NONE))


static func required_tool(block_id: int) -> int:
	return int(_required_tool.get(block_id, Tool.NONE))


static func required_tier(block_id: int) -> int:
	return int(_required_tier.get(block_id, Tier.HAND))


## True when the held item is good enough to mine the block *and* receive its
## normal drop.  A false result means the block may not be broken at all: the
## game refuses the break instead of consuming the block for no reward (the
## user-reported "coal with bare hands disappears" defect).
static func harvestable(block_id: int, item_id: int) -> bool:
	var required := required_tool(block_id)
	if required == Tool.NONE:
		return true
	return tool_class(item_id) == required and tier(item_id) >= required_tier(block_id)


## Human-readable requirement for the HUD, e.g. "Pickaxe" or "Stone Pickaxe",
## or "" when the block can be mined by hand.
static func requirement_label(block_id: int) -> String:
	var required := required_tool(block_id)
	if required == Tool.NONE:
		return ""
	var required_tier_value := required_tier(block_id)
	if required_tier_value <= Tier.HAND:
		return tool_name(required)
	return "%s %s" % [tier_name(required_tier_value), tool_name(required)]


## Seconds to break the block with the given held item (never zero, so the
## progress bar always advances visibly).
static func break_seconds(block_id: int, item_id: int) -> float:
	var hardness := 0.0
	if block_id >= 0 and block_id < BlockDB.hardness.size():
		hardness = float(BlockDB.hardness[block_id])
	if hardness <= 0.0:
		return MIN_BREAK_SECONDS
	var speed := 1.0
	if tool_class(item_id) == effective_tool(block_id) and effective_tool(block_id) != Tool.NONE:
		speed = mining_speed(item_id)
	elif tool_class(item_id) == Tool.SWORD:
		speed = SWORD_BLOCK_FACTOR
	return maxf(MIN_BREAK_SECONDS, hardness * HAND_SECONDS_PER_HARDNESS / speed)


## The item a broken block leaves behind (before the "wrong tool" recheck), or
## `NO_DROP` for nothing.
static func drop_for_block(block_id: int) -> int:
	match block_id:
		BlockDB.COAL_ORE:
			return COAL
		BlockDB.IRON_ORE:
			return IRON_LUMP
		BlockDB.GOLD_ORE:
			return GOLD_LUMP
		BlockDB.DIAMOND_ORE:
			return DIAMOND
	return BlockDB.drop_of(block_id)


## Deterministic chance drops for blocks whose block-level drop is "nothing":
## leaves sometimes carry an apple, and grass carries the seeds that start a
## wheat farm.  The roll is a pure function of the world position, so a replay
## mines the same world.
static func bonus_drop(block_id: int, x: int, y: int, z: int) -> int:
	var roll := _hash3(x, y, z, 9173) % 100
	match block_id:
		BlockDB.OAK_LEAVES, BlockDB.PINE_LEAVES, BlockDB.BIRCH_LEAVES, BlockDB.BLOSSOM_LEAVES:
			return APPLE if roll < 5 else BlockDB.NO_DROP
		BlockDB.TALL_GRASS, BlockDB.FERN, BlockDB.JUNGLE_GRASS, BlockDB.GRASS_TUFT:
			return WHEAT_SEEDS if roll < 18 else BlockDB.NO_DROP
	return BlockDB.NO_DROP


# --- internals ------------------------------------------------------------

static func _definition(item_id: int) -> Dictionary:
	return _definitions.get(item_id, {})


static func _hash3(x: int, y: int, z: int, salt: int) -> int:
	var h: int = x * 2654435761 + y * 40503 + z * 2246822519 + salt * 668265263
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	return absi(h ^ (h >> 16))
