class_name CreatureDB
extends RefCounted

## Data-driven creature definitions and loot tables for the M21 Godot game.
##
## Every species declares its identity, combat numbers and a drop table.  A drop
## row is `{item, min, max, chance}`; the roll is a pure hash of the kill cell and
## the species, so a replayed world drops identically and no shared item id can
## leak a species' loot into another one (the M20 bug where a boar dropped an Oak
## Log because the drop was a single hard-coded constant).
##
## Nothing here touches the scene tree or the world.  The creature models and the
## game layer ask this table what a kill produced and award those stacks through
## the same authoritative inventory path mining uses.

## Item drop rows.  `chance` is 0..1 and rolled first; `min`/`max` bound the count.
const SPECIES := {
	"boar": {
		"name": "Boar",
		"health": 5,
		"drops": [
			{"item": ItemDB.RAW_MEAT, "min": 1, "max": 2, "chance": 1.0},
			{"item": ItemDB.HIDE, "min": 1, "max": 1, "chance": 1.0},
			{"item": ItemDB.BONE, "min": 1, "max": 1, "chance": 0.7},
		],
	},
	"grunt": {
		"name": "Grunt",
		"health": 4,
		"drops": [
			{"item": ItemDB.BONE, "min": 1, "max": 2, "chance": 1.0},
			{"item": ItemDB.COAL, "min": 1, "max": 1, "chance": 0.5},
		],
	},
}


static func has_species(species: String) -> bool:
	return SPECIES.has(species)


static func definition(species: String) -> Dictionary:
	return (SPECIES.get(species, {}) as Dictionary).duplicate(true)


static func name_of(species: String) -> String:
	return str((SPECIES.get(species, {}) as Dictionary).get("name", "Creature"))


## Max health of the species (1 when the species is unknown, so nothing is
## invincible by accident).
static func health(species: String) -> int:
	return int((SPECIES.get(species, {}) as Dictionary).get("health", 1))


## The loot a kill produces, as `[{item, count}, ...]`.  Deterministic in the
## kill cell and the species, so the same encounter always drops the same stacks.
static func loot_for(species: String, cell: Vector3i) -> Array:
	var loot: Array = []
	var entry: Dictionary = SPECIES.get(species, {})
	for row: Dictionary in (entry.get("drops", []) as Array):
		var salt := int(row["item"]) * 7919 + 17
		var roll := _roll(cell, salt) % 1000
		if roll >= int(round(float(row.get("chance", 1.0)) * 1000.0)):
			continue
		var span := int(row.get("max", 1)) - int(row.get("min", 1)) + 1
		var count := int(row.get("min", 1)) + (_roll(cell, salt + 101) % maxi(1, span))
		if count > 0:
			loot.append({"item": int(row["item"]), "count": count})
	return loot


## Total number of items a loot list contains (for summaries).
static func loot_total(loot: Array) -> int:
	var total := 0
	for row: Dictionary in loot:
		total += int(row.get("count", 0))
	return total


## A one-line, human-readable description such as "+2 Raw Meat +1 Hide".
static func loot_label(loot: Array) -> String:
	var parts: Array = []
	for row: Dictionary in loot:
		parts.append("+%d %s" % [int(row.get("count", 0)), ItemDB.name_of(int(row.get("item", BlockDB.AIR)))])
	return " ".join(parts)


static func _roll(cell: Vector3i, salt: int) -> int:
	var h: int = cell.x * 2654435761 + cell.y * 40503 + cell.z * 2246822519 + salt * 668265263
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	return absi(h ^ (h >> 16))
