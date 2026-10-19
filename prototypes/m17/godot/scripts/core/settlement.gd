class_name Settlement
extends RefCounted

## Settlements are *derived*, not stored.
##
## A settlement exists wherever the world generator placed a structure people live
## in (a hut or a campsite), so its identity -- id, name, anchor -- is a pure
## function of the seed and the structure's position.  The same world therefore
## always has the same settlements, whichever direction the player arrives from,
## and only the things that actually change (the shared store and each resident's
## task state) are saved.
##
## Nothing here touches the scene tree: the game layer decides which settlements
## are close enough to exist and spawns nodes for their residents.

## Structure ids that count as a settlement.
const KINDS := ["hut", "campsite"]
## How far a resident may wander from the settlement anchor.
const LEASH := 24.0
## Default radius (blocks) for "settlements near the player".
const DEFAULT_RADIUS := 160

const _PREFIXES := ["Oak", "Stone", "Fern", "Ash", "Pine", "Clay", "Moss", "Willow",
	"Cold", "Bright", "Thorn", "Sand"]
const _SUFFIXES := ["rest", "brook", "hollow", "ford", "watch", "bank", "gate", "mere",
	"water", "stead", "field", "crossing"]


static func is_settlement_kind(id: String) -> bool:
	return KINDS.has(id)


## Deterministic, readable name for the settlement anchored here.
static func name_for(world_seed: int, x: int, z: int) -> String:
	var prefix := str(_PREFIXES[_hash2(x, z, world_seed + 401) % _PREFIXES.size()])
	var suffix := str(_SUFFIXES[_hash2(x, z, world_seed + 402) % _SUFFIXES.size()])
	return "%s%s" % [prefix, suffix]


## Stable identity for a settlement at a world position.
static func id_for(x: int, z: int) -> String:
	return "settlement-%d-%d" % [x, z]


## The settlement a placement describes, or `{}` when the structure is not one
## people live in.
static func from_placement(world_seed: int, placement: Dictionary) -> Dictionary:
	if placement.is_empty() or not is_settlement_kind(str(placement["id"])):
		return {}
	var definition := StructureDB.definition(str(placement["id"]))
	var size := StructureDB.footprint(definition)
	var x := int(placement["x"])
	var z := int(placement["z"])
	return {
		"id": id_for(x, z),
		"name": name_for(world_seed, x, z),
		"kind": str(placement["id"]),
		"anchor": Vector3i(x, int(placement["base_y"]) - 1, z),
		"width": size.x,
		"depth": size.z,
	}


## Every settlement whose anchor is within `radius_blocks` of `center`, nearest
## first, capped at `limit`.  The scan is bounded to the regions that radius can
## reach, so asking from anywhere is cheap.
static func nearby(world: VoxelWorld, center: Vector3i, radius_blocks: int = DEFAULT_RADIUS,
		limit: int = 4) -> Array:
	if world == null:
		return []
	var region_radius := int(ceil(float(radius_blocks) / float(WorldGen.STRUCTURE_REGION))) + 1
	var radius_squared := radius_blocks * radius_blocks
	var found: Array = []
	for region_z in range(WorldGen.structure_region_of(center.z) - region_radius,
			WorldGen.structure_region_of(center.z) + region_radius + 1):
		for region_x in range(WorldGen.structure_region_of(center.x) - region_radius,
				WorldGen.structure_region_of(center.x) + region_radius + 1):
			var placement := world.generator.structure_placement(Vector2i(region_x, region_z))
			var settlement := from_placement(world.world_seed, placement)
			if settlement.is_empty():
				continue
			var anchor: Vector3i = settlement["anchor"]
			var dx := anchor.x - center.x
			var dz := anchor.z - center.z
			if dx * dx + dz * dz > radius_squared:
				continue
			settlement["distance"] = sqrt(float(dx * dx + dz * dz))
			found.append(settlement)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["distance"]), float(b["distance"])):
			return str(a["id"]) < str(b["id"])
		return float(a["distance"]) < float(b["distance"]))
	return found.slice(0, maxi(0, limit))


static func _hash2(x: int, z: int, salt: int) -> int:
	var h: int = x * 374761393 + z * 668265263 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)
