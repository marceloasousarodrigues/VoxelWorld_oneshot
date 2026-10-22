class_name Raid
extends RefCounted

## Deterministic night raids on settlements.
##
## A raid is *scheduled*, not random: every `RAID_PERIOD_DAYS` the night belongs to
## the raiders, and which settlement they hit, how many come and where they appear
## are all pure functions of the seed, the day index and the settlement's anchor.
## Nothing here touches the scene tree or the world; the game layer decides whether
## a raid is happening *now* (is it night, is the settlement loaded, is the player
## close enough to see it) and spawns the nodes from these decisions.
##
## This is what turns the survival loop into a reason to prepare: a raid comes at
## night, the residents fight back, and the player can stand with them.

## A raid night happens every this many in-game days.
const RAID_PERIOD_DAYS := 2
## Raiders spawn this far from the settlement anchor, on a deterministic ring.
const SPAWN_RADIUS := 22
## A raid group is between these sizes.
const GROUP_MIN := 2
const GROUP_MAX := 4
## How close a resident must be to a raider before it joins the fight.  Wider than
## the raider spawn ring, so the settlement reacts as soon as the raid starts.
const DEFEND_RADIUS := 30.0
## A resident strikes this often and for this much.
const DEFEND_INTERVAL := 1.4
const DEFEND_DAMAGE := 2.0
## A raid is abandoned if the player is farther than this from the settlement.
const ENGAGE_RADIUS := 128.0


## True when this day index is a raid night.  Day 0 is the first day, so the
## first raid comes on the night of day 1.
static func is_raid_day(day_index: int) -> bool:
	if day_index <= 0:
		return false
	return day_index % RAID_PERIOD_DAYS == 0


## How many raiders come for a settlement on a given night (empty when none do).
static func group_size(world_seed: int, day_index: int, settlement_id: String) -> int:
	if not is_raid_day(day_index):
		return 0
	return group_size_for_night(world_seed, day_index, settlement_id)


## The group size for a raid night, with no opinion about whether tonight is one
## (the caller has already decided that).
static func group_size_for_night(world_seed: int, day_index: int, settlement_id: String) -> int:
	var roll := absi((world_seed * 7919 + day_index * 104729 + settlement_id.hash()) % 1000)
	return GROUP_MIN + roll % (GROUP_MAX - GROUP_MIN + 1)


## A deterministic spawn point for one raider, on a ring around the settlement.
static func spawn_offset(world_seed: int, day_index: int, settlement_id: String, index: int) -> Vector3:
	var salt := world_seed + day_index * 31 + settlement_id.hash() + index * 977
	var angle := float(absi(salt) % 360) * PI / 180.0
	var radius := float(SPAWN_RADIUS + absi(salt / 7) % 5)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## A stable id for one raider of one raid, so a saved raid can be resumed.
static func raider_id(day_index: int, settlement_id: String, index: int) -> String:
	return "raid-%d-%s:%d" % [day_index, settlement_id, index]


## True when a raid on this settlement should be started "now": it is a raid night
## and the settlement is close enough to the player to be worth simulating.
static func should_start(day_index: int, settlement_id: String, distance_to_player: float,
		already_raided_today: bool) -> bool:
	if already_raided_today:
		return false
	if not is_raid_day(day_index):
		return false
	return distance_to_player <= ENGAGE_RADIUS
