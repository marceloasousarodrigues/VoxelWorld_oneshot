class_name Npc
extends RefCounted

## Node-free model for one settlement resident.
##
## The model owns everything that decides what an NPC does: its identity, its
## task, where it walks, which block it works on, what it carries and what it
## delivers.  It is deterministic given the same world and the same sequence of
## deltas, so it can be tested without a scene tree and replayed.
##
## Residents earn their keep: a woodcutter fells nearby trees and a miner works
## nearby stone and ore, they carry what they gather back to the settlement, and
## the settlement's shared store keeps the result.  Gathering only ever touches
## *exposed* blocks inside a bounded radius of home in a loaded chunk, so an NPC
## can never dig a hole through the world, tunnel out of sight, or edit a chunk
## the player has not streamed in.
##
## State is a plain dictionary so it can be saved and restored verbatim:
##
##     { "id", "name", "role", "task", "position": Vector3, "home": Vector3,
##       "target": Vector3i, "target_block": int, "progress": float,
##       "carried": { item_id: count }, "health": float, "alive": bool,
##       "gathered": int, "delivered": int }

const CAP := 6
const RESIDENT_LIMIT := 3
const WALK_SPEED := 1.25
## Close enough to a block to work on it.
const WORK_RANGE := 1.9
## Seconds of work that removes one block.
const GATHER_SECONDS := 3.5
## How far from home a resident may look for work.
const GATHER_RADIUS := 10
## Trips to the store are made once this much is carried.
const CARRY_CAP := 6
const HEALTH := 12.0
## How far above or below its feet a resident can still work.
const REACH_HEIGHT := 3
## Cells examined per search, so a search is always bounded.
const SEARCH_BUDGET := 3000
## A resident that finds no work waits this long before looking again, so an idle
## NPC in a bare region costs nothing.
const SEEK_RETRY_SECONDS := 1.5
## Residents further than this from the player are frozen (their nodes are retired,
## their state is kept) so a distant settlement costs nothing per frame.
const ACTIVE_RADIUS := 96.0
## The cell value that means "no target".
const NO_CELL := Vector3i(2147483647, 0, 0)

enum Role { WOODCUTTER, MINER }
enum Task { SEEK, WALK, WORK, RETURN, DEFEND }

const ROLE_NAMES := ["Woodcutter", "Miner"]
const NAMES := ["Bram", "Cora", "Dill", "Elsa", "Fern", "Gwen", "Hale", "Ines",
	"Jori", "Kell", "Lorn", "Mabel", "Nell", "Oren", "Pia", "Quin", "Rue", "Sten",
	"Tove", "Ulme", "Vera", "Wren", "Yara", "Zell"]

const WOODCUTTER_BLOCKS := [BlockDB.OAK_LOG, BlockDB.PINE_LOG, BlockDB.BIRCH_LOG]
const MINER_BLOCKS := [BlockDB.STONE, BlockDB.COAL_ORE, BlockDB.IRON_ORE, BlockDB.COBBLESTONE]


# --- identity -------------------------------------------------------------

## The roles a settlement hands out, deterministically, in order.
static func roles_for(world_seed: int, settlement_id: String, count: int) -> Array:
	var roles: Array = []
	var salt := settlement_id.hash()
	for index in count:
		var roll := (salt + index * 7919 + world_seed) % 100
		roles.append(Role.MINER if roll < 35 else Role.WOODCUTTER)
	return roles


static func count_for(world_seed: int, settlement_id: String) -> int:
	var roll := absi((settlement_id.hash() + world_seed * 31) % 1000)
	return 1 + roll % RESIDENT_LIMIT


## A brand new resident for a settlement.  `anchor` is the top solid block of the
## settlement's plot, so the resident stands one block above it.
static func spawn_state(world_seed: int, settlement: Dictionary, index: int) -> Dictionary:
	var anchor: Vector3i = settlement["anchor"]
	var salt := str(settlement["id"]).hash() + index * 131
	var name_index := absi(salt + world_seed) % NAMES.size()
	var offset := _spawn_offset(salt, index, int(settlement.get("width", 3)), int(settlement.get("depth", 3)))
	var roles := roles_for(world_seed, str(settlement["id"]), index + 1)
	var feet_y := float(anchor.y) + 1.0
	return {
		"id": "%s:npc%d" % [settlement["id"], index],
		"settlement": str(settlement["id"]),
		"name": str(NAMES[name_index]),
		"role": int(roles[index]),
		"task": Task.SEEK,
		"position": Vector3(float(anchor.x) + offset.x + 0.5, feet_y, float(anchor.z) + offset.y + 0.5),
		"home": Vector3(float(anchor.x) + 0.5, feet_y, float(anchor.z) + 0.5),
		"settlement_name": str(settlement.get("name", "")),
		"target": NO_CELL,
		"target_block": BlockDB.AIR,
		"progress": 0.0,
		"carried": {},
		"health": HEALTH,
		"alive": true,
		"gathered": 0,
		"delivered": 0,
		"seek_timer": 0.0,
		"attack_timer": 0.0,
	}


## Residents of a settlement, in index order.
static func residents_for(world_seed: int, settlement: Dictionary) -> Array:
	var count := count_for(world_seed, str(settlement["id"]))
	var residents: Array = []
	for index in count:
		residents.append(spawn_state(world_seed, settlement, index))
	return residents


static func _spawn_offset(salt: int, index: int, width: int, depth: int) -> Vector2i:
	var spread := maxi(1, maxi(width, depth))
	var x := absi(salt + index * 37) % spread - spread / 2
	var z := absi(salt + index * 53) % maxi(1, depth)
	return Vector2i(x, z * 2 + 2)


# --- queries --------------------------------------------------------------

static func role_name(role: int) -> String:
	if role >= 0 and role < ROLE_NAMES.size():
		return ROLE_NAMES[role]
	return "Resident"


static func task_name(task: int) -> String:
	match task:
		Task.SEEK:
			return "looking for work"
		Task.WALK:
			return "walking to work"
		Task.WORK:
			return "working"
		Task.RETURN:
			return "carrying to the store"
		Task.DEFEND:
			return "defending the settlement"
	return "idling"


static func targetable_blocks(role: int) -> Array:
	return MINER_BLOCKS if role == Role.MINER else WOODCUTTER_BLOCKS


static func carried_total(state: Dictionary) -> int:
	var total := 0
	for item_id in (state.get("carried", {}) as Dictionary):
		total += int((state["carried"] as Dictionary)[item_id])
	return total


static func carried_text(state: Dictionary) -> String:
	var parts: Array = []
	var carried: Dictionary = state.get("carried", {})
	var keys: Array = carried.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d %s" % [int(carried[item_id]), ItemDB.name_of(int(item_id))])
	return "" if parts.is_empty() else " + ".join(parts)


## What a broken block gives the resident (the item drop, using the same rules as
## the player's mining).
static func drop_for(block_id: int) -> int:
	var drop := ItemDB.drop_for_block(block_id)
	return drop if drop != BlockDB.NO_DROP else block_id


## Nearest exposed block of the resident's kind within `GATHER_RADIUS` of home.
## "Exposed" means a neighbouring cell is air, so a resident never tunnels through
## solid rock, and only loaded chunks are considered, so it never edits a chunk
## the player has not streamed in.  Returns `NO_CELL` when there is no work.
static func find_target(world: VoxelWorld, state: Dictionary) -> Vector3i:
	var home: Vector3 = state["home"]
	var origin := Vector3i(floori(home.x), floori(home.y), floori(home.z))
	var wanted: Array = targetable_blocks(int(state["role"]))
	var from: Vector3 = state["position"]
	# Woodcutters work upwards (trees), miners downwards (ore and stone).  The
	# first band that has any exposed work wins, and the nearest block in that
	# band is chosen, so both the result and the cost are deterministic.
	var bands: Array = []
	if int(state["role"]) == Role.MINER:
		for step in GATHER_RADIUS + 1:
			bands.append(-step)
	else:
		bands.append(-1)
		bands.append(0)
		for step in range(1, 13):
			bands.append(step)
	var examined := 0
	for dy: int in bands:
		var cell_y := origin.y + dy
		if absi(cell_y - floori(from.y)) > REACH_HEIGHT:
			# A resident cannot work a block it cannot reach: it does not climb.
			continue
		var best := NO_CELL
		var best_distance := INF
		for dz in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
			for dx in range(-GATHER_RADIUS, GATHER_RADIUS + 1):
				if dx * dx + dz * dz > GATHER_RADIUS * GATHER_RADIUS:
					continue
				examined += 1
				if examined > SEARCH_BUDGET:
					return NO_CELL
				var cell := Vector3i(origin.x + dx, cell_y, origin.z + dz)
				if not world.is_loaded(cell):
					continue
				var block_id := world.get_block(cell)
				if not wanted.has(block_id):
					continue
				if not _is_exposed(world, cell):
					continue
				var distance := from.distance_squared_to(Vector3(cell) + Vector3(0.5, 0.5, 0.5))
				if distance < best_distance:
					best_distance = distance
					best = cell
		if best != NO_CELL:
			return best
	return NO_CELL


static func _is_exposed(world: VoxelWorld, cell: Vector3i) -> bool:
	for offset: Vector3i in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
		var neighbour := cell + offset
		if world.is_loaded(neighbour) and world.get_block(neighbour) == BlockDB.AIR:
			return true
	return false


static func distance_to_home(state: Dictionary) -> float:
	var position: Vector3 = state["position"]
	var home: Vector3 = state["home"]
	return Vector2(position.x - home.x, position.z - home.z).length()


# --- the task loop --------------------------------------------------------

## Advances one resident by `delta`.  Mutates `state` and `store` and returns the
## events that happened this step:
##     { "gathered": item_id, "delivered": { item_id: count },
##       "attack": int, "attack_damage": float }
## `attack` is an index into the `threats` array the caller passed, so the game
## layer can apply the damage to the right raider.  Everything else is 0/-1 or
## empty when nothing happened.
##
## `threats` is a list of world positions (raiders); a resident within
## `Raid.DEFEND_RADIUS` of home switches to defending, walking to the nearest one
## and striking it on a cadence.  Work resumes when the threats are gone.
static func step(state: Dictionary, world: VoxelWorld, store: Dictionary, delta: float,
		threats: Array = []) -> Dictionary:
	var events := {"gathered": BlockDB.NO_DROP, "delivered": {}, "attack": -1, "attack_damage": 0.0}
	if world == null or not bool(state.get("alive", true)) or delta <= 0.0:
		return events
	var threatened := nearest_threat(state, threats)
	if threatened >= 0:
		_defend(state, threats, threatened, delta, events)
		return events
	if int(state["task"]) == Task.DEFEND:
		# The raid is over: back to work.
		state["task"] = Task.SEEK
		state["target"] = NO_CELL
	match int(state["task"]):
		Task.SEEK:
			_seek(state, world, delta)
		Task.WALK:
			_walk_to_target(state, delta)
		Task.WORK:
			_work(state, world, delta, events)
		Task.RETURN:
			_deliver(state, store, delta, events)
	# A leash: nobody may wander off from their settlement.
	if distance_to_home(state) > Settlement.LEASH:
		state["task"] = Task.RETURN
	return events


## The index of the nearest threat a resident would defend against, or -1.
static func nearest_threat(state: Dictionary, threats: Array) -> int:
	if threats.is_empty():
		return -1
	var home: Vector3 = state["home"]
	var best := -1
	var best_distance := Raid.DEFEND_RADIUS
	for index in threats.size():
		var threat: Vector3 = threats[index]
		var distance := Vector2(threat.x - home.x, threat.z - home.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = index
	return best


## Walks to the threat and strikes it: a resident fights with its hands, on a
## cadence, and never chases a raider out of the settlement.
static func _defend(state: Dictionary, threats: Array, threat_index: int, delta: float,
		events: Dictionary) -> void:
	state["task"] = Task.DEFEND
	state["target"] = NO_CELL
	var threat: Vector3 = threats[threat_index]
	var timer := maxf(0.0, float(state.get("attack_timer", 0.0)) - delta)
	var position: Vector3 = state["position"]
	var flat := Vector2(threat.x - position.x, threat.z - position.z)
	if flat.length() > 1.6:
		_move_towards(state, threat, delta)
		state["attack_timer"] = timer
		return
	if timer > 0.0:
		state["attack_timer"] = timer
		return
	state["attack_timer"] = Raid.DEFEND_INTERVAL
	events["attack"] = threat_index
	events["attack_damage"] = Raid.DEFEND_DAMAGE


static func _seek(state: Dictionary, world: VoxelWorld, delta: float) -> void:
	if carried_total(state) >= CARRY_CAP:
		state["task"] = Task.RETURN
		return
	var wait := maxf(0.0, float(state.get("seek_timer", 0.0)) - delta)
	state["seek_timer"] = wait
	if wait > 0.0:
		return
	var target := find_target(world, state)
	if target == NO_CELL:
		state["target"] = NO_CELL
		state["target_block"] = BlockDB.AIR
		state["seek_timer"] = SEEK_RETRY_SECONDS
		return
	state["target"] = target
	state["target_block"] = world.get_block(target)
	state["progress"] = 0.0
	state["seek_timer"] = 0.0
	state["task"] = Task.WALK


static func _walk_to_target(state: Dictionary, delta: float) -> void:
	var target: Vector3i = state["target"]
	if target == NO_CELL:
		state["task"] = Task.SEEK
		return
	var position: Vector3 = state["position"]
	if absi(target.y - floori(position.y)) > REACH_HEIGHT:
		# Out of vertical reach (someone mined the floor out from under it, or it
		# is looking at something above a cliff): pick other work.
		state["task"] = Task.SEEK
		state["target"] = NO_CELL
		state["seek_timer"] = SEEK_RETRY_SECONDS
		return
	var destination := Vector3(float(target.x) + 0.5, float(target.y), float(target.z) + 0.5)
	var flat := Vector2(destination.x - position.x, destination.z - position.z)
	if flat.length() > WORK_RANGE:
		_move_towards(state, destination, delta)
		return
	state["task"] = Task.WORK
	state["progress"] = 0.0


static func _work(state: Dictionary, world: VoxelWorld, delta: float, events: Dictionary) -> void:
	var target: Vector3i = state["target"]
	if target == NO_CELL:
		state["task"] = Task.SEEK
		return
	var block_id := world.get_block(target)
	if block_id != int(state["target_block"]) or block_id == BlockDB.AIR:
		# Someone else (the player, another resident) got there first.
		state["task"] = Task.SEEK
		state["progress"] = 0.0
		return
	state["progress"] = float(state["progress"]) + delta
	if float(state["progress"]) < GATHER_SECONDS:
		return
	var drop := drop_for(block_id)
	if not world.set_block(target, BlockDB.AIR):
		state["task"] = Task.SEEK
		state["progress"] = 0.0
		return
	var carried: Dictionary = state["carried"]
	carried[drop] = int(carried.get(drop, 0)) + 1
	state["carried"] = carried
	state["gathered"] = int(state.get("gathered", 0)) + 1
	state["progress"] = 0.0
	state["target"] = NO_CELL
	state["task"] = Task.RETURN if carried_total(state) >= CARRY_CAP else Task.SEEK
	events["gathered"] = drop


static func _deliver(state: Dictionary, store: Dictionary, delta: float, events: Dictionary) -> void:
	var carried: Dictionary = state["carried"]
	if carried.is_empty():
		state["task"] = Task.SEEK
		return
	var destination: Vector3 = state["home"]
	if Vector2(destination.x - (state["position"] as Vector3).x,
			destination.z - (state["position"] as Vector3).z).length() > WORK_RANGE:
		_move_towards(state, destination, delta)
		return
	for item_id in carried:
		var amount := int(carried[item_id])
		store[int(item_id)] = int(store.get(int(item_id), 0)) + amount
		state["delivered"] = int(state.get("delivered", 0)) + amount
	events["delivered"] = carried.duplicate()
	state["carried"] = {}
	state["task"] = Task.SEEK


static func _move_towards(state: Dictionary, destination: Vector3, delta: float) -> void:
	var position: Vector3 = state["position"]
	var flat := Vector2(destination.x - position.x, destination.z - position.z)
	if flat.length() <= 0.001:
		return
	var direction := flat.normalized()
	var step := minf(WALK_SPEED * delta, flat.length())
	state["position"] = Vector3(position.x + direction.x * step, position.y, position.z + direction.y * step)


# --- lives ----------------------------------------------------------------

## Applies damage; returns true when this killed the resident.
static func damage(state: Dictionary, amount: float) -> bool:
	if not bool(state.get("alive", true)):
		return false
	state["health"] = maxf(0.0, float(state["health"]) - maxf(0.0, amount))
	if float(state["health"]) <= 0.0:
		state["alive"] = false
		return true
	return false


## Drops everything a dead resident was carrying where it fell.
static func death_drops(state: Dictionary) -> Array:
	var drops: Array = []
	var carried: Dictionary = state.get("carried", {})
	var keys: Array = carried.keys()
	keys.sort()
	for item_id in keys:
		drops.append({"item": int(item_id), "count": int(carried[item_id])})
	return drops


static func describe(state: Dictionary) -> String:
	return "%s the %s — %s%s" % [
		str(state["name"]), role_name(int(state["role"])), task_name(int(state["task"])),
		"" if carried_total(state) == 0 else "  (%s)" % carried_text(state),
	]


# --- persistence ----------------------------------------------------------

static func to_dictionary(state: Dictionary) -> Dictionary:
	var carried: Array = []
	var keys: Array = (state.get("carried", {}) as Dictionary).keys()
	keys.sort()
	for item_id in keys:
		carried.append([int(item_id), int((state["carried"] as Dictionary)[item_id])])
	var position: Vector3 = state["position"]
	var home: Vector3 = state["home"]
	var target: Vector3i = state["target"]
	return {
		"id": str(state["id"]),
		"settlement": str(state.get("settlement", "")),
		"name": str(state["name"]),
		"role": int(state["role"]),
		"task": int(state["task"]),
		"position": [position.x, position.y, position.z],
		"home": [home.x, home.y, home.z],
		# "No target" is written as an empty list so it never looks like a real cell.
		"target": [] if target == NO_CELL else [target.x, target.y, target.z],
		"target_block": int(state.get("target_block", BlockDB.AIR)),
		"progress": float(state.get("progress", 0.0)),
		"carried": carried,
		"health": float(state.get("health", HEALTH)),
		"alive": bool(state.get("alive", true)),
		"gathered": int(state.get("gathered", 0)),
		"delivered": int(state.get("delivered", 0)),
	}


## Reads a saved resident, validating the parts the game depends on.  Returns {}
## when the payload is unusable.
static func from_dictionary(data: Dictionary, settlement_name: String = "") -> Dictionary:
	var id := str(data.get("id", ""))
	if id.is_empty():
		return {}
	var role := int(data.get("role", Role.WOODCUTTER))
	if role < 0 or role > Role.MINER:
		return {}
	var position: Variant = data.get("position")
	var home: Variant = data.get("home")
	if typeof(position) != TYPE_ARRAY or (position as Array).size() < 3:
		return {}
	if typeof(home) != TYPE_ARRAY or (home as Array).size() < 3:
		return {}
	var carried := {}
	var rows: Variant = data.get("carried", [])
	if typeof(rows) == TYPE_ARRAY:
		for row: Variant in (rows as Array):
			if typeof(row) != TYPE_ARRAY or (row as Array).size() < 2:
				continue
			var item_id := int((row as Array)[0])
			var count := int((row as Array)[1])
			if ItemDB.is_valid(item_id) and count > 0:
				carried[item_id] = count
	var target := NO_CELL
	var saved_target: Variant = data.get("target")
	if typeof(saved_target) == TYPE_ARRAY and (saved_target as Array).size() >= 3:
		var as_array: Array = saved_target
		target = Vector3i(int(as_array[0]), int(as_array[1]), int(as_array[2]))
	return {
		"id": id,
		"settlement": str(data.get("settlement", "")),
		"settlement_name": settlement_name,
		"name": str(data.get("name", "Resident")),
		"role": role,
		"task": Task.SEEK,
		"position": Vector3(float((position as Array)[0]), float((position as Array)[1]), float((position as Array)[2])),
		"home": Vector3(float((home as Array)[0]), float((home as Array)[1]), float((home as Array)[2])),
		"target": target,
		"target_block": int(data.get("target_block", BlockDB.AIR)),
		"progress": maxf(0.0, float(data.get("progress", 0.0))),
		"carried": carried,
		"health": clampf(float(data.get("health", HEALTH)), 0.0, HEALTH),
		"alive": bool(data.get("alive", true)),
		"gathered": maxi(0, int(data.get("gathered", 0))),
		"delivered": maxi(0, int(data.get("delivered", 0))),
		"seek_timer": maxf(0.0, float(data.get("seek_timer", 0.0))),
		"attack_timer": maxf(0.0, float(data.get("attack_timer", 0.0))),
	}
