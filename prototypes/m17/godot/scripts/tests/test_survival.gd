extends RefCounted

## Survival rules (`Survival`): fall damage, the breath/drowning step and the
## regeneration rule.  Every function here is a pure static function, so the
## rules are pinned directly instead of through the game layer.


func name() -> String:
	return "survival"


func run(h: TestHarness) -> void:
	h.section("survival")

	# --- fall damage ---------------------------------------------------------
	h.approx(Survival.fall_damage(0.0), 0.0, 1e-9, "an empty fall is no damage")
	h.approx(Survival.fall_damage(-4.0), 0.0, 1e-9, "a negative fall distance is no damage")
	h.approx(Survival.fall_damage(Survival.SAFE_FALL_DISTANCE), 0.0, 1e-9, "a fall exactly at the safe distance hurts nothing")
	h.approx(Survival.fall_damage(Survival.SAFE_FALL_DISTANCE - 0.5), 0.0, 1e-9, "a fall below the safe distance hurts nothing")
	h.approx(Survival.fall_damage(Survival.SAFE_FALL_DISTANCE + 0.5), 0.5, 1e-9,
		"half a block past the safe distance costs half a point")
	h.approx(Survival.fall_damage(10.0), 7.0, 1e-9, "a 10-block fall costs 7 points (distance - safe distance)")
	h.approx(Survival.fall_damage(23.0), 20.0, 1e-9, "a 23-block fall is fatal from full health")
	h.greater(Survival.fall_damage(20.0), Survival.fall_damage(15.0), "fall damage grows with the distance")
	h.eq(Survival.SAFE_FALL_DISTANCE, 3.0, "the safe fall distance is 3 blocks")
	h.eq(Survival.FALL_DAMAGE_PER_BLOCK, 1.0, "each block past the safe distance costs one point")

	# --- breath: refill ------------------------------------------------------
	var refill := Survival.breath_step(0.0, Survival.MAX_BREATH, false, 1.0)
	h.approx(refill["breath"], Survival.BREATH_REFILL_PER_SECOND, 1e-9, "surfaced breath refills at the refill rate")
	h.approx(refill["damage"], 0.0, 1e-9, "surfaced breath deals no damage")
	var capped := Survival.breath_step(Survival.MAX_BREATH - 0.1, Survival.MAX_BREATH, false, 1.0)
	h.approx(capped["breath"], Survival.MAX_BREATH, 1e-9, "refill is capped at the maximum")
	h.approx(Survival.breath_step(Survival.MAX_BREATH, Survival.MAX_BREATH, false, 1.0)["breath"], Survival.MAX_BREATH, 1e-9,
		"a full breath stays full")

	# --- breath: a zero-length step changes nothing --------------------------
	var idle := Survival.breath_step(9.0, Survival.MAX_BREATH, true, 0.0)
	h.approx(idle["breath"], 9.0, 1e-9, "a zero-length step changes no breath")
	h.approx(idle["damage"], 0.0, 1e-9, "a zero-length step deals no damage")

	# --- breath: drain -------------------------------------------------------
	var drain := Survival.breath_step(10.0, Survival.MAX_BREATH, true, 2.0)
	h.approx(drain["breath"], 8.0, 1e-9, "submerged breath drains at the drain rate")
	h.approx(drain["damage"], 0.0, 1e-9, "breath above zero deals no damage")

	# --- breath: drowning ----------------------------------------------------
	var drown := Survival.breath_step(0.0, Survival.MAX_BREATH, true, 1.0)
	h.approx(drown["breath"], 0.0, 1e-9, "empty breath stays empty while submerged")
	h.approx(drown["damage"], Survival.DROWN_DAMAGE_PER_SECOND, 1e-9, "a full second with no breath costs a point")

	# A step that straddles the moment breath runs out: only the time after
	# the breath ran out deals damage.
	var straddle := Survival.breath_step(0.5, Survival.MAX_BREATH, true, 1.0)
	h.approx(straddle["breath"], 0.0, 1e-9, "breath empties within the step")
	h.approx(straddle["damage"], 0.5, 1e-9, "only the time after the breath ran out deals damage")

	var long_drown := Survival.breath_step(0.0, Survival.MAX_BREATH, true, 3.0)
	h.approx(long_drown["damage"], 3.0 * Survival.DROWN_DAMAGE_PER_SECOND, 1e-9, "drowning damage scales with elapsed time")

	h.eq(Survival.MAX_BREATH, 15.0, "a full breath lasts 15 seconds")

	# --- regeneration --------------------------------------------------------
	var early := Survival.regen_step(10.0, 20.0, Survival.REGEN_DELAY_SECONDS - 0.1, 1.0)
	h.approx(early["healed"], 0.0, 1e-9, "no regeneration before the delay elapses")
	h.approx(early["health"], 10.0, 1e-9, "health is unchanged before the delay")
	var healing := Survival.regen_step(10.0, 20.0, Survival.REGEN_DELAY_SECONDS, 1.0)
	h.approx(healing["healed"], Survival.REGEN_PER_SECOND, 1e-9, "regeneration starts once the delay elapses")
	h.approx(healing["health"], 10.0 + Survival.REGEN_PER_SECOND, 1e-9, "the regenerated health is returned")
	var regen_cap := Survival.regen_step(19.9, 20.0, 100.0, 1.0)
	h.approx(regen_cap["health"], 20.0, 1e-9, "regeneration is capped at the maximum")
	h.approx(regen_cap["healed"], 0.1, 1e-6, "regeneration heals only up to the maximum")
	h.approx(Survival.regen_step(20.0, 20.0, 100.0, 1.0)["healed"], 0.0, 1e-9, "a full body does not regenerate")
	h.approx(Survival.regen_step(0.0, 20.0, 100.0, 1.0)["healed"], 0.0, 1e-9, "a dead body does not regenerate")
	h.approx(Survival.regen_step(10.0, 20.0, 100.0, 0.0)["healed"], 0.0, 1e-9, "a zero-length step regenerates nothing")

	h.finish()
