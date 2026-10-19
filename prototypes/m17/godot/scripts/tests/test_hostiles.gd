extends RefCounted

## Hostile creature model: deterministic spawn in the dark, live-ground movement,
## chase/attack cadence, damage, drops and bounded pruning.  Node-free, so the
## rules are testable without a scene tree.

const HostileModel = preload("res://scripts/core/hostile_creatures.gd")


func name() -> String:
	return "hostile creatures"


func _has_column(creatures: Array, x: int, z: int) -> bool:
	for creature: Dictionary in creatures:
		if floori(creature.position.x) == x and floori(creature.position.z) == z:
			return true
	return false


func run(h: TestHarness) -> void:
	h.section("hostile creature model")
	var model = HostileModel.new(17017)
	var world := VoxelWorld.new(17017)
	for x in range(-3, 3):
		for z in range(-3, 3):
			world.ensure_chunk(Vector3i(x, 3, z))
			world.ensure_chunk(Vector3i(x, 4, z))
			world.ensure_chunk(Vector3i(x, 5, z))

	# Only the dark spawns hostiles.
	h.eq(model.spawn_candidates(Vector3i(0, 0, 0), world, 4, false).size(), 0,
		"hostiles do not spawn in daylight")
	var first: Array = model.spawn_candidates(Vector3i(0, 0, 0), world, HostileModel.CAP, true)
	var second: Array = HostileModel.new(17017).spawn_candidates(Vector3i(0, 0, 0), world, HostileModel.CAP, true)
	h.eq(first, second, "hostile spawn identities and candidates are deterministic")
	h.check(first.size() > 0, "the dark spawns at least one hostile near the player")
	h.check(first.size() <= HostileModel.CAP, "hostile candidates respect the population cap")
	for creature: Dictionary in first:
		var x := floori(creature.position.x)
		var z := floori(creature.position.z)
		var height := world.generator.height_at(x, z)
		var offset := Vector2(creature.position.x - 0.5, creature.position.z - 0.5)
		h.check(offset.length() >= HostileModel.MIN_SPAWN_DISTANCE - 2.0,
			"a hostile does not spawn on top of the player")
		h.check(offset.length() <= HostileModel.SPAWN_RADIUS + 1.0, "candidate remains inside spawn radius")
		h.eq(creature.position.y, float(height + 1), "candidate stands one unit above valid land")
		h.check(BlockDB.is_solid(world.get_block(Vector3i(x, height, z))), "candidate ground is solid")

	# Damage, death and a single drop.
	h.check(model.damage(first[0], 1).alive, "nonlethal damage keeps the hostile alive")
	var killed: Dictionary = model.damage(first[0], 99)
	h.check(not killed.alive, "lethal damage kills the hostile")
	h.eq(killed.drops, CreatureDB.loot_total(killed.loot), "the hostile drop count matches its loot list")
	var items: Array = []
	for row: Dictionary in killed.loot:
		items.append(int(row["item"]))
	h.check(items.has(ItemDB.BONE), "a grunt drops bones")
	h.check(not items.has(BlockDB.OAK_LOG), "a grunt never drops an Oak Log")
	h.eq(model.damage(killed.creature, 1).drops, 0, "a dead hostile cannot drop twice")
	h.eq(int(first[0]["health"]), CreatureDB.health("grunt"),
		"the grunt health comes from the species definition")

	# Chase: advances toward the player, stops inside attack range, and refuses a
	# step whose destination has no live ground.
	var anchor: Dictionary = first[0]
	var standing: Vector3 = anchor.position
	var far_target := standing + Vector3(6.0, 0.0, 0.0)
	var chased: Vector3 = model.chase_destination(world, standing, far_target, 0.5)
	h.check(chased.x > standing.x, "the hostile advances toward the player")
	h.check((chased - standing).length() <= HostileModel.SPEED * 0.5 + 0.001, "chase step is speed bounded")
	var in_range_target := standing + Vector3(HostileModel.ATTACK_RANGE * 0.5, 0.0, 0.0)
	h.eq(model.chase_destination(world, standing, in_range_target, 0.5), standing,
		"the hostile stops once the player is in attack range")
	var ax := floori(standing.x)
	var az := floori(standing.z)
	var ground_height := world.generator.height_at(ax, az)
	var ground_cell := Vector3i(ax, ground_height, az)
	var original_ground := world.get_block(ground_cell)
	h.check(world.set_block(ground_cell, BlockDB.AIR), "the hostile's ground block can be mined")
	# A short step keeps the destination inside the mined column.
	h.eq(model.chase_destination(world, standing, far_target, 0.1), standing,
		"a chase step over a mined hole is refused")
	h.check(not model.supports_standing(world, ax, az, ground_height), "a mined column no longer supports the hostile")
	world.set_block(ground_cell, original_ground)
	h.check(model.supports_standing(world, ax, az, ground_height), "restored ground supports the hostile again")

	# Attack cadence: only when in range and off cooldown.
	var away: Dictionary = model.attack_step(false, 0.0, 0.1)
	h.eq(away.damage, 0.0, "a hostile out of range deals no damage")
	var hit: Dictionary = model.attack_step(true, 0.0, 0.1)
	h.eq(hit.damage, HostileModel.ATTACK_DAMAGE, "an in-range hostile deals its attack damage")
	h.eq(hit.cooldown, HostileModel.ATTACK_INTERVAL, "a hit starts the attack cooldown")
	var during: Dictionary = model.attack_step(true, hit.cooldown, 0.2)
	h.eq(during.damage, 0.0, "a hostile cannot hit again during its cooldown")
	var after: Dictionary = model.attack_step(true, during.cooldown, HostileModel.ATTACK_INTERVAL)
	h.eq(after.damage, HostileModel.ATTACK_DAMAGE, "the hostile hits again once the cooldown elapses")

	# Bounded pruning of dead or distant hostiles.
	var before_prune: int = model.states.size()
	var pruned: Array = model.prune(Vector3(1000, 0, 1000), 1)
	h.eq(pruned.size(), 1, "hostile pruning work is explicitly bounded")
	h.eq(model.states.size(), before_prune - 1, "an out-of-range hostile state is despawned")

	h.finish()
