extends RefCounted

const CreatureModel = preload("res://scripts/core/passive_creatures.gd")

func name() -> String:
	return "passive creatures"

func _has_column(creatures: Array, x: int, z: int) -> bool:
	for creature: Dictionary in creatures:
		if floori(creature.position.x) == x and floori(creature.position.z) == z:
			return true
	return false


func run(h: TestHarness) -> void:
	h.section("passive creature model")
	var model = CreatureModel.new(17017)
	var world := VoxelWorld.new(17017)
	for x in range(-3, 3):
		for z in range(-3, 3):
			world.ensure_chunk(Vector3i(x, 3, z))
			world.ensure_chunk(Vector3i(x, 4, z))
			world.ensure_chunk(Vector3i(x, 5, z))
	var first := model.spawn_candidates(Vector3i(0, 0, 0), world, 6)
	var second = CreatureModel.new(17017).spawn_candidates(Vector3i(0, 0, 0), world, 6)
	h.eq(first, second, "spawn identities and candidates are deterministic")
	h.check(first.size() <= 6, "spawn candidates respect the population cap")
	for creature: Dictionary in first:
		var x := floori(creature.position.x)
		var z := floori(creature.position.z)
		var height := world.generator.height_at(x, z)
		var ground := world.generator._surface_block(world.generator.biome_at(x, z), height)
		h.check(Vector2(creature.position.x - 0.5, creature.position.z - 0.5).length() <= CreatureModel.SPAWN_RADIUS, "candidate remains inside spawn radius")
		h.eq(creature.position.y, float(height + 1), "candidate stands one unit above a valid land surface")
		h.check(height > WorldGen.SEA_LEVEL and BlockDB.is_solid(ground), "candidate ground is solid land, not water")
	h.check(model.damage(first[0], 1).alive, "nonlethal damage keeps creature alive")
	var killed: Dictionary = model.damage(first[0], 99)
	h.check(not killed.alive, "lethal damage kills creature")
	h.check(killed.drops == CreatureDB.loot_total(killed.loot), "the drop count matches the loot list")
	h.check(killed.loot.size() > 0, "a boar death yields a species-specific drop list")
	# The reported M20 defect: a boar must never drop an Oak Log.
	var items: Array = []
	for row: Dictionary in killed.loot:
		items.append(int(row["item"]))
	h.check(items.has(ItemDB.RAW_MEAT), "a boar drops raw meat")
	h.check(items.has(ItemDB.HIDE), "a boar drops a hide")
	h.check(not items.has(BlockDB.OAK_LOG), "a boar never drops an Oak Log")
	h.eq(model.damage(killed.creature, 1).drops, 0, "dead creature cannot drop twice")
	h.eq(model.damage(killed.creature, 1).loot.size(), 0, "a dead creature carries no second loot list")
	# Determinism: the same kill cell produces the exact same loot.
	var repeat: Dictionary = CreatureModel.new(17017).damage(first[0], 99)
	h.eq(repeat.loot, killed.loot, "boar loot is deterministic for a kill cell")
	var wander: Vector3 = model.wander_step(Vector3.ZERO, Vector3(50, 0, 0), 1.0)
	h.check(wander.length() <= CreatureModel.WANDER_SPEED + 0.001, "wandering step is speed bounded")
	var before_prune: int = model.states.size()
	var pruned: Array = model.prune(Vector3(1000, 0, 1000), 1)
	h.eq(pruned.size(), 1, "pruning work is explicitly bounded")
	h.eq(model.states.size(), before_prune - 1, "out-of-range creature state is despawned")

	# Creatures must follow *live* world ground, not the procedural generator: if
	# the player mines the ground block the creature may no longer spawn or step
	# there (it would be standing over a hole).
	h.section("passive creatures follow live ground")
	var probe: Variant = CreatureModel.new(17017)
	var anchor: Dictionary = first[0]
	var ax := floori(anchor.position.x)
	var az := floori(anchor.position.z)
	var ground_height := world.generator.height_at(ax, az)
	var ground_cell := Vector3i(ax, ground_height, az)
	var original_ground := world.get_block(ground_cell)
	h.check(BlockDB.is_solid(original_ground), "the accepted candidate stands on solid generated land")
	h.check(world.set_block(ground_cell, BlockDB.AIR), "the candidate's ground block can be mined")
	var after: Array = CreatureModel.new(17017).spawn_candidates(Vector3i(0, 0, 0), world, 6)
	h.check(not _has_column(after, ax, az), "a mined ground column is not chosen as a spawn candidate")
	h.check(after.size() > 0, "valid ground still yields spawn candidates after an edit")
	h.check(not probe.supports_standing(world, ax, az, ground_height), "a mined column no longer supports standing")
	var standing := Vector3(float(ax) + 0.5, float(ground_height) + 1.0, float(az) + 0.5)
	var toward := standing + Vector3(2.0, 0.0, 0.0)
	var refused: Vector3 = probe.wander_destination(world, standing, toward, 0.1)
	h.eq(refused, standing, "a wander step over a mined hole is refused")
	world.set_block(ground_cell, original_ground)
	h.check(probe.supports_standing(world, ax, az, ground_height), "restored ground supports standing again")
	var advanced: Vector3 = probe.wander_destination(world, standing, toward, 0.1)
	h.check(not advanced.is_equal_approx(standing), "a wander step over valid ground still advances")
	h.finish()
