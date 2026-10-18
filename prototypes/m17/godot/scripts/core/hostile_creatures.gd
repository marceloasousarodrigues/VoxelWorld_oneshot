class_name HostileCreatures
extends RefCounted

## Deterministic node-free hostile creature state (one "grunt" species).
##
## The model owns spawn selection, chase decisions, the attack cadence, damage,
## drops and bounded pruning.  Rendering and scheduling live in the game layer;
## the model has no dependency on the scene tree and never looks at the
## procedural generator to decide whether the ground is real -- it reads the live
## voxel world, so a mined or flooded floor stops the creature.

const CAP := 4
const SPAWN_RADIUS := 32.0
## A hostile never appears right on top of the player.
const MIN_SPAWN_DISTANCE := 10.0
const DESPAWN_RADIUS := 48.0
const AGGRO_RADIUS := 14.0
const SPEED := 2.2
const HIT_POINTS := 4
const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 2.0
const ATTACK_INTERVAL := 1.2
const DROP_ID := ItemDB.COAL
const DROP_COUNT := 1

var seed_value: int
var next_id := 1
var states: Dictionary = {}


func _init(seed: int = 17017) -> void:
	seed_value = seed


## Spawn candidates for the requested darkness flag.  `dark` false (daylight)
## yields nothing: hostiles are a night/darkness threat.
func spawn_candidates(focus: Vector3i, world: VoxelWorld, requested_cap: int = CAP, dark: bool = true) -> Array:
	var result: Array = []
	if not dark:
		return result
	var cap := mini(CAP, maxi(0, requested_cap))
	var center := Vector2(focus.x + 0.5, focus.z + 0.5)
	for ring in range(12, int(SPAWN_RADIUS) + 1, 4):
		for index in 16:
			if result.size() >= cap:
				return result
			var angle := TAU * float(index) / 16.0 + float(posmod(seed_value + ring, 97)) * 0.031
			var x := floori(center.x + cos(angle) * ring)
			var z := floori(center.y + sin(angle) * ring)
			var key := "%d:%d:%d" % [seed_value, x, z]
			if states.has(key) or _already_selected(result, key):
				continue
			if Vector2(float(x) + 0.5 - center.x, float(z) + 0.5 - center.y).length() < MIN_SPAWN_DISTANCE:
				continue
			var height := world.generator.height_at(x, z)
			if height <= WorldGen.SEA_LEVEL or height + 2 >= WorldGen.WORLD_HEIGHT:
				continue
			if not supports_standing(world, x, z, height):
				continue
			var state := {"id": next_id, "species": "grunt", "position": Vector3(x + 0.5, height + 1.0, z + 0.5),
				"health": HIT_POINTS, "alive": true, "key": key}
			next_id += 1
			states[key] = state
			result.append(state.duplicate(true))
	return result


## True when the *live* world supports the creature here: loaded solid,
## non-liquid ground with loaded air at the foot and head cells.
func supports_standing(world: VoxelWorld, x: int, z: int, height: int) -> bool:
	var ground_cell := Vector3i(x, height, z)
	var foot_cell := Vector3i(x, height + 1, z)
	var head_cell := Vector3i(x, height + 2, z)
	if not world.is_loaded(ground_cell) or not world.is_loaded(foot_cell) or not world.is_loaded(head_cell):
		return false
	var ground := world.get_block(ground_cell)
	if not BlockDB.is_solid(ground) or BlockDB.is_liquid(ground):
		return false
	return world.get_block(foot_cell) == BlockDB.AIR and world.get_block(head_cell) == BlockDB.AIR


## Pure chase decision: the next world position toward `target`, or the current
## position when the player is already in attack range or the destination column
## has no live supported ground.
func chase_destination(world: VoxelWorld, position: Vector3, target: Vector3, delta: float) -> Vector3:
	var direction := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var distance := direction.length()
	if delta <= 0.0 or distance <= ATTACK_RANGE:
		return position
	var step := minf(SPEED * delta, distance - ATTACK_RANGE)
	var next := position + direction.normalized() * step
	var x := floori(next.x)
	var z := floori(next.z)
	var height := world.generator.height_at(x, z)
	if height <= WorldGen.SEA_LEVEL or not supports_standing(world, x, z, height):
		return position
	return Vector3(next.x, float(height) + 1.0, next.z)


## Pure attack cadence: returns the damage to apply (0 when out of range or still
## cooling down) and the cooldown to carry into the next step.
func attack_step(in_range: bool, cooldown: float, delta: float) -> Dictionary:
	var remaining := maxf(0.0, cooldown - delta)
	if in_range and remaining <= 0.0:
		return {"damage": ATTACK_DAMAGE, "cooldown": ATTACK_INTERVAL}
	return {"damage": 0.0, "cooldown": remaining}


func damage(creature: Dictionary, amount: int) -> Dictionary:
	var state: Dictionary = creature.duplicate(true)
	if not state.get("alive", false) or amount <= 0:
		return {"creature": state, "alive": bool(state.get("alive", false)), "drops": 0}
	state.health = maxi(0, int(state.health) - amount)
	state.alive = state.health > 0
	var drops := DROP_COUNT if not state.alive else 0
	return {"creature": state, "alive": state.alive, "drops": drops}


## Removes dead or out-of-range hostiles, checking at most `max_work` entries per
## call so a large population can never stall a frame.
func prune(focus: Vector3, max_work: int = 8) -> Array:
	var removed: Array = []
	var checked := 0
	for key: Variant in states.keys():
		if checked >= max_work:
			break
		checked += 1
		var state: Dictionary = states[key]
		if not state.get("alive", false) or Vector2(state.position.x - focus.x, state.position.z - focus.z).length() > DESPAWN_RADIUS:
			removed.append(key)
			states.erase(key)
	return removed


func _already_selected(entries: Array, key: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("key", "")) == key:
			return true
	return false
