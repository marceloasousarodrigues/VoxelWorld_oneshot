extends RefCounted

## Player health model (`Health`): clamping, the death-once contract, healing,
## revival, the signal behaviour and the save payload validation.


func name() -> String:
	return "health"


func run(h: TestHarness) -> void:
	h.section("health")

	# --- a fresh body starts full -------------------------------------------
	var health := Health.new()
	h.eq(health.max_health, Health.DEFAULT_MAX_HEALTH, "a fresh body has the default maximum")
	h.eq(health.health, Health.DEFAULT_MAX_HEALTH, "a fresh body starts at full health")
	h.approx(health.ratio(), 1.0, 1e-9, "a fresh body is at full ratio")
	h.check(not health.is_dead(), "a fresh body is alive")

	# Counters let every "emits nothing" assertion be exact.
	var changed := [0]
	var damaged := [0]
	var died := [0]
	var last_amount: Array = [0.0]
	var last_source: Array = [""]
	health.changed.connect(func() -> void: changed[0] += 1)
	health.damaged.connect(func(amount: float, source: String) -> void:
		damaged[0] += 1
		last_amount[0] = amount
		last_source[0] = source)
	health.died.connect(func() -> void: died[0] += 1)

	# --- damage is clamped and reports what it applied ----------------------
	h.approx(health.apply_damage(6.0, "test"), 6.0, 1e-9, "damage applies in full when it is smaller than health")
	h.approx(health.health, 14.0, 1e-9, "health drops by the applied damage")
	h.approx(health.ratio(), 0.7, 1e-9, "the ratio tracks the damage")
	h.eq(changed[0], 1, "a damage step reports one change")
	h.eq(damaged[0], 1, "a damage step reports one damaged event")
	h.approx(last_amount[0], 6.0, 1e-9, "the damaged signal carries the applied amount")
	h.eq(last_source[0], "test", "the damaged signal carries the source")

	# --- a non-positive amount is ignored ------------------------------------
	changed[0] = 0
	damaged[0] = 0
	died[0] = 0
	h.approx(health.apply_damage(0.0, "test"), 0.0, 1e-9, "zero damage is a no-op")
	h.approx(health.apply_damage(-5.0, "test"), 0.0, 1e-9, "negative damage is a no-op")
	h.approx(health.health, 14.0, 1e-9, "a no-op leaves health untouched")
	h.eq(changed[0] + damaged[0] + died[0], 0, "a no-op emits nothing")

	# --- overkill clamps to the remaining health ----------------------------
	changed[0] = 0
	damaged[0] = 0
	died[0] = 0
	h.approx(health.apply_damage(50.0, "fall"), 14.0, 1e-9, "overkill returns only the health that was applied")
	h.approx(health.health, 0.0, 1e-9, "health floors at zero")
	h.check(health.is_dead(), "zero health is dead")
	h.approx(health.ratio(), 0.0, 1e-9, "a dead body has zero ratio")
	h.eq(died[0], 1, "reaching zero emits died exactly once")

	# --- a dead body takes no more damage and never re-emits died -----------
	changed[0] = 0
	damaged[0] = 0
	died[0] = 0
	h.approx(health.apply_damage(5.0, "test"), 0.0, 1e-9, "a dead body applies no further damage")
	h.approx(health.health, 0.0, 1e-9, "health stays at zero")
	h.eq(changed[0] + damaged[0] + died[0], 0, "a dead body emits nothing, so died cannot repeat")

	# --- a dead body cannot heal --------------------------------------------
	changed[0] = 0
	h.approx(health.heal(5.0), 0.0, 1e-9, "a dead body cannot heal")
	h.approx(health.health, 0.0, 1e-9, "health stays at zero after a rejected heal")
	h.eq(changed[0], 0, "a rejected heal emits nothing")

	# --- revive restores the body -------------------------------------------
	changed[0] = 0
	health.revive()
	h.approx(health.health, health.max_health, 1e-9, "revive restores full health")
	h.check(not health.is_dead(), "a revived body is alive")
	h.eq(changed[0], 1, "revive reports the change")
	h.approx(health.apply_damage(3.0, "test"), 3.0, 1e-9, "a revived body takes damage again")

	# --- healing is clamped and capped --------------------------------------
	h.approx(health.heal(2.0), 2.0, 1e-9, "healing applies what it can")
	h.approx(health.health, 19.0, 1e-9, "healed health is updated")
	h.approx(health.heal(100.0), 1.0, 1e-9, "healing is capped at the maximum")
	h.approx(health.health, 20.0, 1e-9, "health never exceeds the maximum")
	changed[0] = 0
	h.approx(health.heal(5.0), 0.0, 1e-9, "healing a full body is a no-op")
	h.eq(changed[0], 0, "healing a full body emits nothing")
	h.approx(health.heal(0.0), 0.0, 1e-9, "zero healing is a no-op")

	# --- set_health clamps into range ---------------------------------------
	health.set_health(7.5)
	h.approx(health.health, 7.5, 1e-9, "set_health assigns the value")
	health.set_health(999.0)
	h.approx(health.health, 20.0, 1e-9, "set_health clamps above the maximum")
	health.set_health(-3.0)
	h.approx(health.health, 0.0, 1e-9, "set_health clamps below zero")
	h.check(health.is_dead(), "set_health to zero is dead")
	var set_health_deaths := [0]
	var set_health_subject := Health.new()
	var set_health_changed := [0]
	set_health_subject.died.connect(func() -> void: set_health_deaths[0] += 1)
	set_health_subject.changed.connect(func() -> void: set_health_changed[0] += 1)
	set_health_subject.set_health(0.0)
	h.eq(set_health_deaths[0], 1, "set_health transition to zero emits died once")
	h.eq(set_health_changed[0], 1, "set_health transition to zero emits changed")
	set_health_subject.set_health(0.0)
	h.eq(set_health_deaths[0], 1, "repeated set_health zero does not emit died again")

	# --- a custom maximum ----------------------------------------------------
	var tough := Health.new(40.0, 12.0)
	h.eq(tough.max_health, 40.0, "a custom maximum is respected")
	h.eq(tough.health, 12.0, "a custom starting health is respected")
	h.approx(tough.ratio(), 0.3, 1e-9, "the ratio uses the custom maximum")
	var bare := Health.new(40.0)
	h.eq(bare.health, 40.0, "a body created with only a maximum starts full")

	# --- save round-trip -----------------------------------------------------
	var payload: Dictionary = tough.to_dictionary()
	var restored := Health.new()
	h.check(restored.from_dictionary(payload), "health restores from its save payload")
	h.approx(restored.max_health, 40.0, 1e-9, "the restored maximum matches")
	h.approx(restored.health, 12.0, 1e-9, "the restored health matches")

	# --- validation ----------------------------------------------------------
	var subject := Health.new(20.0, 10.0)
	h.check(not subject.from_dictionary({"max_health": 0.0, "health": 5.0}), "a zero maximum is rejected")
	h.check(not subject.from_dictionary({"max_health": -4.0, "health": 5.0}), "a negative maximum is rejected")
	h.check(not subject.from_dictionary({"max_health": "twenty", "health": 5.0}), "a non-numeric maximum is rejected")
	h.check(not subject.from_dictionary({"max_health": 20.0, "health": "lots"}), "a non-numeric health is rejected")
	h.check(not subject.from_dictionary({}), "a payload without health is rejected")
	h.approx(subject.health, 10.0, 1e-9, "a rejected payload leaves health untouched")
	h.approx(subject.max_health, 20.0, 1e-9, "a rejected payload leaves the maximum untouched")
	h.check(subject.from_dictionary({"max_health": 20.0, "health": 999.0}), "an over-range health is clamped, not rejected")
	h.approx(subject.health, 20.0, 1e-9, "the over-range health clamps to the maximum")
	h.check(subject.from_dictionary({"max_health": 20.0, "health": -5.0}), "an under-range health is clamped, not rejected")
	h.approx(subject.health, 0.0, 1e-9, "the under-range health clamps to zero")

	h.finish()
