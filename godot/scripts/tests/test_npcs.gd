extends RefCounted

## Settlements and their residents.
##
## Everything here is derived from the seed and the placed structures, and the
## residents' step is deterministic, so the same contracts the generator has
## apply to the people: the same world always has the same settlements and the
## same residents in the same places, and an NPC's work is always bounded to the
## settlement and to loaded chunks.

var _settlement := {}


func name() -> String:
	return "settlements and NPCs"


## The first settlement in the world, found by scanning outward.
func _first_settlement(world: VoxelWorld, limit: int = 8) -> Dictionary:
	for region_z in range(-limit, limit + 1):
		for region_x in range(-limit, limit + 1):
			var placement := world.generator.structure_placement(Vector2i(region_x, region_z))
			var settlement := Settlement.from_placement(world.world_seed, placement)
			if not settlement.is_empty():
				return settlement
	return {}


## A flat test world with a settlement-sized plot: a solid stone plateau with a
## few logs on top, so a resident has something to do without needing terrain.
func _test_plot() -> Dictionary:
	# Pinned to the M30 terrain: this plot is laid over the generator's natural trees.
	var world := VoxelWorld.new(17017, 1)
	for chunk_y in range(0, 6):
		for chunk_z in range(-1, 2):
			for chunk_x in range(-1, 2):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	var anchor := Vector3i(8, 70, 8)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for dy in range(-3, 1):
				world.set_block(anchor + Vector3i(dx, dy, dz), BlockDB.STONE, false)
	for dy in range(1, 4):
		world.set_block(anchor + Vector3i(2, dy, 2), BlockDB.OAK_LOG, false)
	var settlement := {
		"id": Settlement.id_for(anchor.x, anchor.z), "name": "Testhold", "kind": "hut",
		"anchor": anchor, "width": 5, "depth": 4,
	}
	return {"world": world, "settlement": settlement}


func _test_derivation(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var settlement := _first_settlement(world)
	h.check(not settlement.is_empty(), "the world contains at least one settlement")
	if settlement.is_empty():
		return
	h.check(settlement["id"].begins_with("settlement-"), "the settlement id is stable and readable (%s)" % settlement["id"])
	h.eq(settlement["id"], Settlement.id_for(int(settlement["anchor"].x), int(settlement["anchor"].z)),
		"the id is derived from the anchor")
	h.check(Settlement.is_settlement_kind(str(settlement["kind"])), "the settlement is built on a lived-in structure")
	h.check(not Settlement.is_settlement_kind("watchtower"), "a ruin is not a settlement")
	h.check(not (Settlement.name_for(17017, 1, 2) as String).is_empty(), "a settlement has a name")
	h.eq(Settlement.name_for(17017, 1, 2), Settlement.name_for(17017, 1, 2),
		"the name is deterministic")
	h.check(Settlement.name_for(17017, 1, 2) != Settlement.name_for(17017, 900, 900),
		"different settlements usually get different names")
	h.check((Settlement.from_placement(17017, {}) as Dictionary).is_empty(), "an empty placement makes no settlement")

	# Deriving the same settlement twice must give the same answer.
	var again := _first_settlement(VoxelWorld.new(17017))
	h.eq(again, settlement, "the same world derives the same settlement")

	# `nearby` is radius- and limit-bounded and sorted by distance.
	var near := Settlement.nearby(world, settlement["anchor"], 64, 4)
	h.check(near.size() >= 1, "the anchor's own settlement is nearby")
	h.eq(str((near[0] as Dictionary)["id"]), str(settlement["id"]), "the nearest settlement is first")
	var sorted := true
	for index in range(1, near.size()):
		if float((near[index] as Dictionary)["distance"]) < float((near[index - 1] as Dictionary)["distance"]) - 0.001:
			sorted = false
	h.check(sorted, "nearby() is sorted by distance")
	h.eq(Settlement.nearby(world, Vector3i(100000, 70, 100000), 64, 4).size(), 0,
		"a far away point has no settlements")
	h.less(float(Settlement.nearby(world, settlement["anchor"], 4000, 2).size()), 3.0,
		"the limit caps the number of settlements")


func _test_residents(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var settlement := _first_settlement(world)
	if settlement.is_empty():
		h.check(false, "a settlement exists for the resident tests")
		return
	var residents := Npc.residents_for(17017, settlement)
	h.greater(float(residents.size()), 0.0, "a settlement has residents")
	h.less(float(residents.size()), float(Npc.RESIDENT_LIMIT + 1), "a settlement is not overcrowded")
	var ids := {}
	var valid := true
	for state: Dictionary in residents:
		ids[str(state["id"])] = true
		if str(state["name"]).is_empty() or int(state["role"]) < 0 or int(state["role"]) > Npc.Role.MINER:
			valid = false
		if int(state["health"]) <= 0.0 or not bool(state["alive"]):
			valid = false
		if float(state["home"].y) != float(settlement["anchor"].y) + 1.0:
			valid = false
	h.check(valid, "every resident has a name, a role, health and a home")
	h.eq(ids.size(), residents.size(), "resident ids are unique")
	h.eq(Npc.residents_for(17017, settlement), residents, "residents are deterministic")
	h.eq(Npc.count_for(17017, str(settlement["id"])), residents.size(), "the resident count matches")
	h.check(Npc.role_name(Npc.Role.MINER) == "Miner", "roles have names")
	h.check(Npc.describe(residents[0]).contains(str((residents[0] as Dictionary)["name"])),
		"a resident describes itself with its name")

	# A different settlement id usually gets a different roster.
	var other := Settlement.from_placement(17017, {"id": "hut", "x": 1234, "z": -5678, "base_y": 70})
	var other_residents := Npc.residents_for(17017, other)
	h.check(str((other_residents[0] as Dictionary)["id"]) != str((residents[0] as Dictionary)["id"]),
		"another settlement has its own residents")


func _test_work_loop(h: TestHarness) -> void:
	var plot := _test_plot()
	var world: VoxelWorld = plot["world"]
	var settlement: Dictionary = plot["settlement"]
	var state := Npc.spawn_state(17017, settlement, 0)
	state["role"] = Npc.Role.WOODCUTTER
	state["position"] = Vector3(8.5, 70.0, 8.5)
	var store := {}

	# The resident finds the tree and walks to it.
	var target := Npc.find_target(world, state)
	h.check(target != Npc.NO_CELL, "the resident finds work in the plot")
	if target == Npc.NO_CELL:
		return
	h.check(BlockDB.is_defined(world.get_block(target)), "the resident targets a real block")
	h.check(world.get_block(target) in [BlockDB.OAK_LOG, BlockDB.PINE_LOG, BlockDB.BIRCH_LOG],
		"the woodcutter targets a log")
	var target_block := world.get_block(target)
	h.eq(Npc.drop_for(target_block), target_block, "a log drops a log")
	h.less(float(Vector2(target.x - 8, target.z - 8).length()), float(Npc.GATHER_RADIUS + 1),
		"the target is within the gathering radius")

	# A seek from an empty part of the world finds nothing.
	var nowhere := Npc.spawn_state(17017, settlement, 1)
	nowhere["home"] = Vector3(2000.0, 70.0, 2000.0)
	nowhere["position"] = Vector3(2000.5, 70.0, 2000.5)
	h.eq(Npc.find_target(world, nowhere), Npc.NO_CELL, "an unloaded region offers no work")

	# Step until the block is gone and the resident is carrying it.
	var gathered := 0
	var steps := 0
	while gathered == 0 and steps < 400:
		var events: Dictionary = Npc.step(state, world, store, 0.2)
		if int(events["gathered"]) != BlockDB.NO_DROP:
			gathered = int(events["gathered"])
		steps += 1
	h.greater(float(gathered), 0.0, "the resident gathered something in %d steps" % steps)
	h.check(gathered in [BlockDB.OAK_LOG, BlockDB.PINE_LOG, BlockDB.BIRCH_LOG],
		"the woodcutter gathered a log")
	h.eq(world.get_block(target), BlockDB.AIR, "the gathered block was removed from the world")
	h.eq(Npc.carried_total(state), 1, "the resident is carrying what it gathered")
	h.eq(int(state["gathered"]), 1, "the resident's gathered count went up")
	h.check(Npc.describe(state).contains("carrying") or Npc.describe(state).contains("work"),
		"the resident describes what it is doing (%s)" % Npc.describe(state))

	# Keep working until the carry limit sends it home, then it deposits.
	var delivered := {}
	steps = 0
	while delivered.is_empty() and steps < 3000:
		var events: Dictionary = Npc.step(state, world, store, 0.2)
		if not (events["delivered"] as Dictionary).is_empty():
			delivered = events["delivered"]
		steps += 1
	h.check(not delivered.is_empty(), "the resident delivered its load in %d steps" % steps)
	var delivered_total := 0
	for count: int in delivered.values():
		delivered_total += count
	h.eq(delivered_total, Npc.CARRY_CAP, "a full load is delivered at once")
	h.eq(Npc.carried_total(state), 0, "the resident is empty-handed after delivering")
	var stored_total := 0
	for count: int in store.values():
		stored_total += count
	h.eq(stored_total, Npc.CARRY_CAP, "the store holds what was delivered")
	h.eq(int(state["delivered"]), Npc.CARRY_CAP, "the resident's delivered count went up")
	h.less(Npc.distance_to_home(state), float(Npc.GATHER_RADIUS + 2), "the resident stays near home")


func _test_miner_and_bounds(h: TestHarness) -> void:
	var plot := _test_plot()
	var world: VoxelWorld = plot["world"]
	var state := Npc.spawn_state(17017, plot["settlement"], 1)
	state["role"] = Npc.Role.MINER
	var target := Npc.find_target(world, state)
	h.check(target != Npc.NO_CELL, "the miner finds stone in the plot")
	if target != Npc.NO_CELL:
		h.eq(world.get_block(target), BlockDB.STONE, "the miner targets stone")
		h.check(target.y <= int(state["home"].y), "the miner works at or below the surface (%d vs %d)" % [
			target.y, int(state["home"].y)])

	# Mining is bounded to the radius: nothing outside it is ever touched.
	var store := {}
	var mined: Dictionary = {}
	for step in 4000:
		var events: Dictionary = Npc.step(state, world, store, 0.2)
		var item := int(events["gathered"])
		if item != BlockDB.NO_DROP:
			mined[item] = true
			h.less(Npc.distance_to_home(state), float(Npc.GATHER_RADIUS + 2),
				"the resident never leaves its range")
			break
	h.check(mined.has(BlockDB.STONE) or mined.has(BlockDB.COBBLESTONE), "the miner produced stone")
	h.eq(int(state["carried"].get(BlockDB.COBBLESTONE, 0)), 1, "the mined stone is carried as cobblestone")

	# A dead resident does nothing.
	var dead := state.duplicate(true)
	dead["alive"] = false
	var idle: Dictionary = Npc.step(dead, world, store, 1.0)
	h.eq(int(idle["gathered"]), BlockDB.NO_DROP, "a dead resident gathers nothing")
	h.eq(int(idle["attack"]), -1, "a dead resident does not fight")
	h.check((idle["delivered"] as Dictionary).is_empty(), "a dead resident delivers nothing")

	# The leash pulls a straying resident home.
	var stray := Npc.spawn_state(17017, plot["settlement"], 2)
	stray["position"] = Vector3(float(plot["settlement"]["anchor"].x) + Settlement.LEASH + 10.0,
		float(plot["settlement"]["anchor"].y), float(plot["settlement"]["anchor"].z))
	Npc.step(stray, world, store, 0.2)
	h.eq(int(stray["task"]), Npc.Task.RETURN, "a resident beyond the leash heads home")


func _test_damage_and_persistence(h: TestHarness) -> void:
	var plot := _test_plot()
	var state := Npc.spawn_state(17017, plot["settlement"], 0)
	state["carried"] = {BlockDB.OAK_LOG: 3, ItemDB.COAL: 1}
	h.check(not Npc.damage(state, 5.0), "a resident survives a survivable hit")
	h.eq(float(state["health"]), Npc.HEALTH - 5.0, "damage reduces health exactly")
	h.check(Npc.damage(state, 100.0), "enough damage kills the resident")
	h.check(not bool(state["alive"]), "a dead resident is not alive")
	h.check(not Npc.damage(state, 5.0), "a dead resident cannot be killed again")
	var drops := Npc.death_drops(state)
	h.eq(drops.size(), 2, "a dead resident drops both stacks it carried")

	# A fresh resident round-trips through its serialised form.
	var fresh := Npc.spawn_state(17017, plot["settlement"], 1)
	fresh["carried"] = {ItemDB.STONE_PICKAXE: 1}
	fresh["position"] = Vector3(12.5, 70.0, 9.25)
	fresh["target"] = Vector3i(3, 60, 4)
	fresh["progress"] = 1.25
	fresh["gathered"] = 4
	var payload := Npc.to_dictionary(fresh)
	var restored := Npc.from_dictionary(payload, "Testhold")
	h.check(not restored.is_empty(), "a serialised resident round-trips")
	h.eq(str(restored["id"]), str(fresh["id"]), "the id survived")
	h.eq(int(restored["role"]), int(fresh["role"]), "the role survived")
	h.eq(restored["position"], fresh["position"], "the position survived exactly")
	h.eq(restored["home"], fresh["home"], "the home survived")
	h.eq(int(restored["carried"].get(ItemDB.STONE_PICKAXE, 0)), 1, "the carried stack survived")
	h.eq(int(restored["gathered"]), 4, "the gathered counter survived")
	h.eq(str(restored["settlement_name"]), "Testhold", "the settlement name is attached on load")
	h.eq(int(restored["task"]), Npc.Task.SEEK, "a loaded resident starts by looking for work")

	# A resident with no target serialises without one.
	fresh["target"] = Npc.NO_CELL
	h.check((Npc.to_dictionary(fresh)["target"] as Array).is_empty(), "no target serialises as an empty list")
	h.eq(Npc.from_dictionary(Npc.to_dictionary(fresh))["target"], Npc.NO_CELL,
		"an empty target list restores as no target")

	# Malformed payloads are refused instead of producing a broken resident.
	var rejects := [
		[{}, "an empty payload"],
		[{"id": "", "position": [0, 0, 0], "home": [0, 0, 0]}, "no id"],
		[{"id": "x", "position": "nope", "home": [0, 0, 0]}, "a bad position"],
		[{"id": "x", "position": [0, 0, 0]}, "no home"],
		[{"id": "x", "position": [0, 0, 0], "home": [0, 0, 0], "role": 99}, "an unknown role"],
	]
	for case: Array in rejects:
		h.check((Npc.from_dictionary(case[0]) as Dictionary).is_empty(),
			"a payload with %s is refused" % case[1])
	# ... and a payload with junk carried entries drops just those entries.
	var partial := Npc.from_dictionary({
		"id": "x", "position": [0, 0, 0], "home": [0, 0, 0], "role": 0,
		"carried": [[ItemDB.COAL, 2], [99999, 5], "junk"],
	})
	h.eq(int(partial["carried"].get(ItemDB.COAL, 0)), 2, "a valid carried entry survives")
	h.eq(partial["carried"].size(), 1, "invalid carried entries are dropped")


func run(h: TestHarness) -> void:
	_test_derivation(h)
	_test_residents(h)
	_test_work_loop(h)
	_test_miner_and_bounds(h)
	_test_damage_and_persistence(h)
	h.finish()
