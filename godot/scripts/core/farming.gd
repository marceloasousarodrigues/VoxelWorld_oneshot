class_name Farming
extends RefCounted

## Node-free wheat farming for the M21 Godot game.
##
## A crop is a real block in the world (`WHEAT_0..3`, rendered as growing crossed
## quads), so the block edits, meshing, collision and save/load path are the ones
## the game already uses.  This model owns the one thing a block id cannot carry:
## how long the current stage has been growing.  Progress is keyed by the crop
## cell and persisted, so a crop resumes exactly where it was left.
##
## The rules are deliberately small:
##   * planting tills the soil to `FARMLAND` and puts a `WHEAT_0` above it;
##   * a planted crop advances one stage every `STAGE_SECONDS` while its chunk is
##     loaded and the player is nearby;
##   * a ripe crop yields 2-3 Wheat and 0-2 Wheat Seeds; an unripe one yields one
##     seed back, so a mistake is cheap rather than punishing;
##   * a crop whose soil was removed or replaced is cleared, never floating.
##
## Nothing here touches the scene tree; the game layer renders and ticks it.

const STAGE_SECONDS := 24.0
const ACTIVE_RADIUS := 64.0
const CROP_BLOCKS := [BlockDB.WHEAT_0, BlockDB.WHEAT_1, BlockDB.WHEAT_2, BlockDB.WHEAT_3]
const RIPE_BLOCK := BlockDB.WHEAT_3
const PLANTABLE_SOIL := [BlockDB.GRASS, BlockDB.DIRT, BlockDB.DRY_GRASS, BlockDB.FARMLAND]

var seed_value: int
## Crop cell -> seconds grown in the current stage.
var progress: Dictionary = {}


func _init(seed: int = 17017) -> void:
	seed_value = seed


static func is_crop(block_id: int) -> bool:
	return CROP_BLOCKS.has(block_id)


static func stage_of(block_id: int) -> int:
	var index := CROP_BLOCKS.find(block_id)
	return index if index >= 0 else -1


static func block_for_stage(stage: int) -> int:
	var clamped := clampi(stage, 0, CROP_BLOCKS.size() - 1)
	return int(CROP_BLOCKS[clamped])


## Pure planting decision.  Returns `{"ok": bool, "reason": String, "position": Vector3i}`.
## The crop grows in the cell above `soil`, which must be plantable loaded ground
## with loaded air above it.
static func can_plant(world: VoxelWorld, soil: Vector3i) -> Dictionary:
	var crop := soil + Vector3i.UP
	if world == null or not world.is_loaded(soil) or not world.is_loaded(crop):
		return {"ok": false, "reason": "That soil is not loaded", "position": crop}
	if not PLANTABLE_SOIL.has(world.get_block(soil)):
		return {"ok": false, "reason": "Wheat needs grass, dirt or farmland", "position": crop}
	var above := world.get_block(crop)
	if above != BlockDB.AIR:
		return {"ok": false, "reason": "There is no room to plant there", "position": crop}
	return {"ok": true, "reason": "", "position": crop}


## Tills the soil and plants one wheat stage-0 crop.  Returns the `can_plant`
## dictionary, so a refused plant changes nothing.
func plant(world: VoxelWorld, soil: Vector3i) -> Dictionary:
	var decision := can_plant(world, soil)
	if not bool(decision["ok"]):
		return decision
	var crop: Vector3i = decision["position"]
	if world.get_block(soil) != BlockDB.FARMLAND:
		world.set_block(soil, BlockDB.FARMLAND)
	world.set_block(crop, BlockDB.WHEAT_0)
	progress[crop] = 0.0
	decision["planted"] = true
	return decision


## Advances growth for every tracked crop near the player.  Returns the list of
## crop cells whose stage changed, so the caller can report or refresh.
func step(delta: float, world: VoxelWorld, focus: Vector3, radius: float = ACTIVE_RADIUS) -> Array:
	var advanced: Array = []
	if delta <= 0.0 or world == null:
		return advanced
	var centre := Vector3(focus.x, 0.0, focus.z)
	for key: Variant in progress.keys():
		var cell: Vector3i = key
		var flat := Vector2(float(cell.x) + 0.5 - centre.x, float(cell.z) + 0.5 - centre.z)
		if flat.length() > radius or not world.is_loaded(cell) or not world.is_loaded(cell + Vector3i.DOWN):
			continue
		var block_id := world.get_block(cell)
		if not is_crop(block_id):
			progress.erase(cell)
			continue
		if not _supported(world, cell):
			world.set_block(cell, BlockDB.AIR)
			progress.erase(cell)
			continue
		if block_id == RIPE_BLOCK:
			progress.erase(cell)
			continue
		var grown := float(progress[cell]) + delta
		var stage := stage_of(block_id)
		while grown >= STAGE_SECONDS and stage < CROP_BLOCKS.size() - 1:
			grown -= STAGE_SECONDS
			stage += 1
			world.set_block(cell, block_for_stage(stage))
			advanced.append(cell)
		if stage >= CROP_BLOCKS.size() - 1:
			progress.erase(cell)
		else:
			progress[cell] = grown
	return advanced


## True when a crop cell still sits on valid soil.
static func _supported(world: VoxelWorld, crop: Vector3i) -> bool:
	var soil := world.get_block(crop + Vector3i.DOWN)
	return soil == BlockDB.FARMLAND or soil == BlockDB.DIRT or soil == BlockDB.GRASS


## Deterministic harvest: a ripe crop gives 2-3 Wheat and 0-2 Seeds; an unripe one
## gives a single seed back.  Pure function of the cell, so a replay is identical.
func harvest_loot(block_id: int, cell: Vector3i) -> Dictionary:
	if block_id == RIPE_BLOCK:
		return {
			ItemDB.WHEAT: 2 + _hash(cell, 11) % 2,
			ItemDB.WHEAT_SEEDS: 1 + _hash(cell, 29) % 2,
		}
	if is_crop(block_id):
		return {ItemDB.WHEAT_SEEDS: 1}
	return {}


## Clears the growth tracking for a cell (harvest or removal).
func forget(cell: Vector3i) -> void:
	progress.erase(cell)


## Bones feed the farm: a ripe-adjacent crop advances one stage immediately.
## Returns true when the crop actually advanced.
func fertilize(world: VoxelWorld, cell: Vector3i) -> bool:
	if world == null or not world.is_loaded(cell):
		return false
	var block_id := world.get_block(cell)
	if not is_crop(block_id) or block_id == RIPE_BLOCK:
		return false
	var stage := stage_of(block_id) + 1
	world.set_block(cell, block_for_stage(stage))
	if stage >= CROP_BLOCKS.size() - 1:
		progress.erase(cell)
	else:
		progress[cell] = 0.0
	return true


func to_dictionary() -> Array:
	var rows: Array = []
	var keys: Array = progress.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a < b)
	for cell: Vector3i in keys:
		rows.append([cell.x, cell.y, cell.z, float(progress[cell])])
	return rows


## Restores growth progress.  Every row is validated; an unreadable row is skipped
## rather than aborting the load.
func from_dictionary(rows: Variant) -> Dictionary:
	progress.clear()
	var accepted := 0
	var rejected := 0
	if typeof(rows) != TYPE_ARRAY:
		return {"accepted": 0, "rejected": 0}
	for entry: Variant in (rows as Array):
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 4:
			rejected += 1
			continue
		var row: Array = entry
		if typeof(row[0]) != TYPE_INT and typeof(row[0]) != TYPE_FLOAT:
			rejected += 1
			continue
		if typeof(row[1]) != TYPE_INT and typeof(row[1]) != TYPE_FLOAT:
			rejected += 1
			continue
		if typeof(row[2]) != TYPE_INT and typeof(row[2]) != TYPE_FLOAT:
			rejected += 1
			continue
		if typeof(row[3]) != TYPE_INT and typeof(row[3]) != TYPE_FLOAT:
			rejected += 1
			continue
		var elapsed := float(row[3])
		if elapsed < 0.0 or elapsed > STAGE_SECONDS:
			rejected += 1
			continue
		var cell := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		progress[cell] = elapsed
		accepted += 1
	return {"accepted": accepted, "rejected": rejected}


func count() -> int:
	return progress.size()


func _hash(cell: Vector3i, salt: int) -> int:
	var h: int = cell.x * 2654435761 + cell.y * 40503 + cell.z * 2246822519 + seed_value * 668265263 + salt
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	return absi(h ^ (h >> 16))
