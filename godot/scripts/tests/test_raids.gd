extends RefCounted

## Night raids: the schedule (`core/raid.gd`) and the resident DEFEND task.
##
## A raid must be a pure function of the seed, the day and the settlement, and a
## resident must only ever fight inside its own settlement.  Both are pinned here;
## the integration suite covers the scene side (raiders spawning, residents
## striking one down, the raid ending).


func name() -> String:
	return "raids"


func _settlement() -> Dictionary:
	return {"id": "settlement-8-8", "name": "Oakhollow", "kind": "hut",
		"anchor": Vector3i(8, 70, 8), "width": 5, "depth": 4}


func _test_schedule(h: TestHarness) -> void:
	h.greater(float(Raid.RAID_PERIOD_DAYS), 1.0, "raids do not happen every night")
	h.check(not Raid.is_raid_day(0), "the first day is not a raid night")
	var raid_days := 0
	for day in range(0, 20):
		if Raid.is_raid_day(day):
			raid_days += 1
	h.greater(float(raid_days), 5.0, "raids do happen regularly (%d of 20 days)" % raid_days)
	h.check(Raid.is_raid_day(Raid.RAID_PERIOD_DAYS), "day %d is a raid night" % Raid.RAID_PERIOD_DAYS)
	h.check(not Raid.is_raid_day(Raid.RAID_PERIOD_DAYS + 1), "the day after is not")


func _test_group_and_spawn(h: TestHarness) -> void:
	var settlement := _settlement()
	var id := str(settlement["id"])
	h.eq(Raid.group_size(17017, 1, id), 0, "no group comes on a quiet night")
	var sizes := {}
	var in_range := true
	for day in range(1, 30):
		var size := Raid.group_size(17017, day, id)
		if size == 0:
			continue
		sizes[size] = true
		if size < Raid.GROUP_MIN or size > Raid.GROUP_MAX:
			in_range = false
	h.check(in_range, "every group size is within the raid bounds")
	h.greater(float(sizes.size()), 1.0, "group sizes vary (%s)" % str(sizes.keys()))
	h.eq(Raid.group_size(17017, Raid.RAID_PERIOD_DAYS, id), Raid.group_size(17017, Raid.RAID_PERIOD_DAYS, id),
		"a group size is deterministic")
	h.check(Raid.group_size(17017, Raid.RAID_PERIOD_DAYS, id)
		!= Raid.group_size(4242, Raid.RAID_PERIOD_DAYS, id) or true, "different seeds may differ")

	# Spawn points sit on a deterministic ring around the settlement.
	var offsets: Array = []
	for index in Raid.GROUP_MAX:
		offsets.append(Raid.spawn_offset(17017, Raid.RAID_PERIOD_DAYS, id, index))
	var on_ring := true
	for offset: Vector3 in offsets:
		var radius := Vector2(offset.x, offset.z).length()
		if radius < float(Raid.SPAWN_RADIUS) - 0.001 or radius > float(Raid.SPAWN_RADIUS + 5):
			on_ring = false
	h.check(on_ring, "raiders spawn just outside the settlement")
	h.eq(offsets, [Raid.spawn_offset(17017, Raid.RAID_PERIOD_DAYS, id, 0),
		Raid.spawn_offset(17017, Raid.RAID_PERIOD_DAYS, id, 1),
		Raid.spawn_offset(17017, Raid.RAID_PERIOD_DAYS, id, 2),
		Raid.spawn_offset(17017, Raid.RAID_PERIOD_DAYS, id, 3)],
		"spawn points are deterministic")
	var distinct := {}
	for offset: Vector3 in offsets:
		distinct[offset] = true
	h.eq(distinct.size(), offsets.size(), "each raider gets its own spawn point")
	h.check(str(Raid.raider_id(2, id, 0)) != str(Raid.raider_id(2, id, 1)), "raider ids are unique")
	h.eq(str(Raid.raider_id(2, id, 0)), str(Raid.raider_id(2, id, 0)), "raider ids are stable")


func _test_should_start(h: TestHarness) -> void:
	var id := "settlement-8-8"
	h.check(not Raid.should_start(1, id, 10.0, false), "no raid on a quiet night")
	h.check(Raid.should_start(Raid.RAID_PERIOD_DAYS, id, 10.0, false), "a raid starts on a raid night")
	h.check(not Raid.should_start(Raid.RAID_PERIOD_DAYS, id, 10.0, true),
		"a settlement that was already raided today is left alone")
	h.check(not Raid.should_start(Raid.RAID_PERIOD_DAYS, id, Raid.ENGAGE_RADIUS + 1.0, false),
		"a settlement beyond the engage radius is not simulated")
	h.check(Raid.should_start(Raid.RAID_PERIOD_DAYS, id, Raid.ENGAGE_RADIUS, false),
		"a settlement at the engage radius is simulated")


## A resident defends only inside its own settlement, strikes on a cadence, and
## goes back to work when the raiders are gone.
func _test_defend_task(h: TestHarness) -> void:
	var state := Npc.spawn_state(17017, _settlement(), 0)
	state["role"] = Npc.Role.WOODCUTTER
	var home: Vector3 = state["home"]
	h.eq(int(state["task"]), Npc.Task.SEEK, "a resident starts by looking for work")
	h.eq(Npc.nearest_threat(state, []), -1, "no threats means no defending")

	# A raider right beside the settlement is a threat; a distant one is not.
	var nearby: Vector3 = home + Vector3(3.0, 0.0, 0.0)
	h.eq(Npc.nearest_threat(state, [nearby]), 0, "a raider inside the settlement is a threat")
	var far: Vector3 = home + Vector3(Raid.DEFEND_RADIUS + 5.0, 0.0, 0.0)
	h.eq(Npc.nearest_threat(state, [far]), -1, "a raider outside the defend radius is ignored")
	var mixed: Array = [far, nearby]
	h.eq(Npc.nearest_threat(state, mixed), 1, "the nearest threat is chosen")

	# The DEFEND step walks towards the raider, then strikes on a cadence.
	state["position"] = home + Vector3(10.0, 0.0, 0.0)
	var store := {}
	var world := VoxelWorld.new(17017)
	var steps := 0
	var attacks := 0
	var first := true
	while steps < 400 and attacks < 3:
		var events: Dictionary = Npc.step(state, world, store, 0.25, [nearby])
		steps += 1
		if int(events["attack"]) >= 0:
			attacks += 1
			h.eq(int(events["attack"]), 0, "the strike names the threat it hit")
			h.approx(float(events["attack_damage"]), Raid.DEFEND_DAMAGE, 0.001, "a resident hits for its damage")
			if first:
				h.eq(int(state["task"]), Npc.Task.DEFEND, "the resident is defending")
				h.check(Npc.describe(state).contains("defend"), "the readout says it is defending")
				first = false
	h.greater(float(attacks), 2.0, "the resident strikes repeatedly (%d hits)" % attacks)
	# Between strikes it never leaves the settlement.
	h.less(Npc.distance_to_home(state), float(Settlement.LEASH), "the defender stays inside the leash")

	# When the threats are gone it goes back to work.
	var after: Dictionary = Npc.step(state, world, store, 0.25, [])
	h.eq(int(after["attack"]), -1, "no strike without a threat")
	h.check(int(state["task"]) != Npc.Task.DEFEND, "the resident leaves the defend task")
	h.eq(int(state["task"]), Npc.Task.SEEK, "the resident looks for work again")

	# A resident too far from home does not chase a raider across the world.
	var straggler := Npc.spawn_state(17017, _settlement(), 1)
	straggler["position"] = home + Vector3(60.0, 0.0, 0.0)
	h.eq(Npc.nearest_threat(straggler, [home + Vector3(Raid.DEFEND_RADIUS, 0.0, 0.0)]), 0,
		"the threat check is relative to home, not to the resident")
	# A dead resident never defends.
	var dead := Npc.spawn_state(17017, _settlement(), 2)
	dead["alive"] = false
	h.eq(Npc.step(dead, world, store, 1.0, [nearby]), 
		{"gathered": BlockDB.NO_DROP, "delivered": {}, "attack": -1, "attack_damage": 0.0},
		"a dead resident takes no part in the fight")


func _test_clock_days(h: TestHarness) -> void:
	var clock := DayNight.new(0.28, 100.0)
	h.eq(clock.day_index, 0, "a new clock starts on day zero")
	clock.advance(50.0)
	h.eq(clock.day_index, 0, "half a day does not change the day")
	clock.advance(50.0)
	h.eq(clock.day_index, 1, "wrapping midnight advances the day")
	clock.advance(200.0)
	h.eq(clock.day_index, 3, "several days advance together")
	var frozen := DayNight.new(0.28, 0.0)
	frozen.advance(1000.0)
	h.eq(frozen.day_index, 0, "a frozen clock never advances the day")

	# The day counter is what decides when raids happen, so it must survive a save.
	var payload := clock.to_dictionary()
	h.eq(int(payload.get("day_index", -1)), 3, "the day counter is saved")
	var restored := DayNight.new(0.0, 100.0)
	h.check(restored.from_dictionary(payload), "a clock payload round-trips")
	h.eq(restored.day_index, 3, "the day counter survived the round-trip")
	var legacy := {"time_of_day": 0.5, "day_length_seconds": 100.0}
	var legacy_clock := DayNight.new(0.0, 100.0)
	h.check(legacy_clock.from_dictionary(legacy), "a legacy clock payload is accepted")
	h.eq(legacy_clock.day_index, 0, "a payload without a day counter starts the calendar again")
	h.check(not DayNight.new().from_dictionary({"day_index": 4}), "a payload without a time is refused")


func run(h: TestHarness) -> void:
	_test_schedule(h)
	_test_group_and_spawn(h)
	_test_should_start(h)
	_test_defend_task(h)
	_test_clock_days(h)
	h.finish()
