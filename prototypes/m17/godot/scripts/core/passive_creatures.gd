class_name PassiveCreatures
extends RefCounted

## Deterministic node-free passive creature state. Rendering and scheduling live
## in the game layer; this model has no dependency on the scene tree.
const CAP := 6
const SPAWN_RADIUS := 38.0
const DESPAWN_RADIUS := 54.0
const WANDER_SPEED := 1.2
## The boar definition lives in `CreatureDB`; these remain for the existing
## callers that read the population constants.
const SPECIES := "boar"
const HIT_POINTS := 5

var seed_value: int
var next_id := 1
var states: Dictionary = {}

func _init(seed: int = 17017) -> void:
	seed_value = seed

func spawn_candidates(focus: Vector3i, world: VoxelWorld, requested_cap: int = CAP) -> Array:
	var result: Array = []
	var cap := mini(CAP, maxi(0, requested_cap))
	var center := Vector2(focus.x + 0.5, focus.z + 0.5)
	for ring in range(8, int(SPAWN_RADIUS) + 1, 4):
		for index in range(16):
			if result.size() >= cap:
				return result
			var angle := TAU * float(index) / 16.0 + float(posmod(seed_value + ring, 97)) * 0.031
			var x := floori(center.x + cos(angle) * ring)
			var z := floori(center.y + sin(angle) * ring)
			var key := "%d:%d:%d" % [seed_value, x, z]
			if states.has(key) or _already_selected(result, key):
				continue
			var height := world.generator.height_at(x, z)
			if height <= WorldGen.SEA_LEVEL or height + 2 >= WorldGen.WORLD_HEIGHT:
				continue
			if not supports_standing(world, x, z, height):
				continue
			var state := {"id": next_id, "species": SPECIES, "position": Vector3(x + 0.5, height + 1.0, z + 0.5),
				"health": CreatureDB.health(SPECIES), "alive": true, "wander": Vector3.ZERO, "key": key}
			next_id += 1
			states[key] = state
			result.append(state.duplicate(true))
	return result


## True when the *live* voxel world actually supports a creature in this column:
## the ground cell at `height` is loaded solid, non-liquid land and the foot and
## head cells above it are loaded air.
##
## This reads only the live world, never the procedural generator, so a ground
## block the player mined (or flooded) is rejected even though the generated
## surface still exists there.
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


## Pure wander decision for one step towards `target`: the world position the
## creature should move to.  It is the current `position` (no movement) when
## there is no step, when the destination leaves valid terrain, or when the
## destination column has no live supported ground -- so a creature never walks
## out over a hole or into water.
func wander_destination(world: VoxelWorld, position: Vector3, target: Vector3, delta: float) -> Vector3:
	var step := wander_step(position, target, delta)
	if step.length_squared() <= 0.00001:
		return position
	var next := position + step
	var x := floori(next.x)
	var z := floori(next.z)
	var height := world.generator.height_at(x, z)
	if height <= WorldGen.SEA_LEVEL or not supports_standing(world, x, z, height):
		return position
	return Vector3(next.x, float(height) + 1.0, next.z)

func _already_selected(entries: Array, key: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("key", "")) == key:
			return true
	return false

## Applies one hit.  The killing blow carries the species' data-driven loot list,
## so the caller awards it exactly once; a non-lethal or already-dead creature
## carries an empty list and can never drop twice.
func damage(creature: Dictionary, amount: int) -> Dictionary:
	var state: Dictionary = creature.duplicate(true)
	if not state.get("alive", false) or amount <= 0:
		return {"creature": state, "alive": bool(state.get("alive", false)), "drops": 0, "loot": []}
	state.health = maxi(0, int(state.health) - amount)
	state.alive = state.health > 0
	var loot: Array = []
	if not state.alive:
		loot = CreatureDB.loot_for(str(state.get("species", SPECIES)), _cell_of(state))
	return {"creature": state, "alive": state.alive, "drops": CreatureDB.loot_total(loot), "loot": loot}


func _cell_of(state: Dictionary) -> Vector3i:
	var position: Vector3 = state.get("position", Vector3.ZERO)
	return Vector3i(floori(position.x), floori(position.y), floori(position.z))

func wander_step(position: Vector3, target: Vector3, delta: float) -> Vector3:
	var direction := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if direction.length_squared() < 0.0001 or delta <= 0.0:
		return Vector3.ZERO
	return direction.normalized() * minf(WANDER_SPEED * delta, direction.length())

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
