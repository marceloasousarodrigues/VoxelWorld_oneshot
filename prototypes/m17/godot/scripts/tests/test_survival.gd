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

	# --- hunger: the exhaustion budget --------------------------------------
	h.eq(Survival.MAX_HUNGER, 20.0, "a full hunger bar is 20")
	var hunger_full := Survival.hunger_step(Survival.MAX_HUNGER, 0.0, Survival.ACTIVITY_EXHAUSTION["idle"], 1.0)
	h.approx(hunger_full["hunger"], Survival.MAX_HUNGER, 1e-9, "a full hunger bar stays full while idle")
	h.approx(hunger_full["exhaustion"], Survival.ACTIVITY_EXHAUSTION["idle"], 1e-9,
		"idling still builds a little exhaustion")

	# A full exhaustion budget loses exactly one hunger point.
	var spend := Survival.hunger_step(20.0, Survival.EXHAUSTION_PER_HUNGER, 0.0, 1.0)
	h.approx(spend["hunger"], 19.0, 1e-9, "a full exhaustion budget costs exactly one hunger point")
	h.approx(spend["exhaustion"], 0.0, 1e-9, "the spent exhaustion is consumed")

	# Sprinting drains faster than walking, and both faster than standing still.
	h.greater(float(Survival.ACTIVITY_EXHAUSTION["sprint"]), float(Survival.ACTIVITY_EXHAUSTION["walk"]),
		"sprinting builds exhaustion faster than walking")
	h.greater(float(Survival.ACTIVITY_EXHAUSTION["walk"]), float(Survival.ACTIVITY_EXHAUSTION["idle"]),
		"walking builds exhaustion faster than idling")
	var sprinted := Survival.hunger_step(20.0, 0.0, Survival.ACTIVITY_EXHAUSTION["sprint"], 60.0)
	h.less(sprinted["hunger"], 20.0, "a minute of sprinting costs at least one hunger point")

	# Hunger never goes negative and a zero-length step changes nothing.
	h.approx(Survival.hunger_step(0.0, 0.0, 0.0, 1.0)["hunger"], 0.0, 1e-9, "hunger stops at zero")
	h.approx(Survival.hunger_step(10.0, 0.0, 0.0, 0.0)["hunger"], 10.0, 1e-9, "a zero-length step changes no hunger")
	h.approx(Survival.hunger_step(30.0, 0.0, 0.0, 1.0)["hunger"], Survival.MAX_HUNGER, 1e-9,
		"an over-full hunger bar is clamped")

	# --- hunger: starvation --------------------------------------------------
	h.approx(Survival.starvation_damage(10.0, 20.0, 1.0), 0.0, 1e-9, "a fed player takes no starvation damage")
	h.approx(Survival.starvation_damage(0.0, 20.0, 1.0), Survival.STARVE_DAMAGE_PER_SECOND, 1e-9,
		"an empty hunger bar costs health every second")
	h.approx(Survival.starvation_damage(0.0, 20.0, 4.0), 1.0, 1e-6, "starvation damage scales with elapsed time")
	h.approx(Survival.starvation_damage(0.0, Survival.STARVE_HEALTH_FLOOR, 4.0), 0.0, 1e-9,
		"starvation cannot take the last point of health")
	h.approx(Survival.starvation_damage(0.0, Survival.STARVE_HEALTH_FLOOR + 0.5, 4.0), 0.5, 1e-6,
		"starvation stops exactly at the floor")
	h.approx(Survival.starvation_damage(0.0, 20.0, 0.0), 0.0, 1e-9, "a zero-length step starves nobody")

	# --- hunger: eating ------------------------------------------------------
	var snack := Survival.food_effect(Survival.MAX_HUNGER, 4.0, 0.0)
	h.approx(snack["hunger"], Survival.MAX_HUNGER, 1e-9, "eating at full hunger wastes the food")
	h.check(not bool(snack["improved"]), "eating at full hunger is not an improvement")
	var meal := Survival.food_effect(10.0, 6.0, 0.0)
	h.approx(meal["hunger"], 16.0, 1e-9, "food adds its value to hunger")
	h.check(bool(meal["improved"]), "eating while hungry is an improvement")
	var healing_meal := Survival.food_effect(4.0, 10.0, 4.0)
	h.approx(healing_meal["hunger"], 14.0, 1e-9, "the golden apple fills ten hunger points")
	h.approx(healing_meal["heal"], 4.0, 1e-9, "the golden apple also heals")
	var capped_meal := Survival.food_effect(19.0, 10.0, 2.0)
	h.approx(capped_meal["hunger"], Survival.MAX_HUNGER, 1e-9, "eating cannot overfill hunger")
	h.check(bool(capped_meal["improved"]), "a partly wasted meal is still an improvement")
	h.approx(Survival.food_effect(10.0, 0.0, 0.0)["hunger"], 10.0, 1e-9, "a non-food item feeds nobody")
	h.check(not bool(Survival.food_effect(10.0, 0.0, 0.0)["improved"]), "a non-food item is not edible")

	# --- hunger: fed regeneration -------------------------------------------
	var unfed := Survival.regen_step(10.0, 20.0, 100.0, 1.0, 0.0, 0.0)
	h.approx(unfed["healed"], 0.0, 1e-9, "a starving body does not regenerate")
	var fed := Survival.regen_step(10.0, 20.0, 100.0, 1.0, Survival.MAX_HUNGER, 0.0)
	h.approx(fed["healed"], Survival.REGEN_PER_SECOND, 1e-9, "a fed body regenerates")
	h.greater(float(fed["exhaustion"]), 0.0, "regenerating burns hunger")
	var hungry := Survival.regen_step(10.0, 20.0, 100.0, 1.0, Survival.MIN_REGEN_HUNGER - 0.1, 0.0)
	h.approx(hungry["healed"], 0.0, 1e-9, "a very hungry body does not regenerate")
	h.approx(Survival.regen_step(10.0, 20.0, 100.0, 1.0, -1.0, 0.0)["healed"], Survival.REGEN_PER_SECOND, 1e-9,
		"without hunger tracking the old regeneration rule still applies")

	h.finish()
