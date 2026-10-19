class_name StationRegistry
extends RefCounted

## Associates persistent station inventories with the world objects that own them
## (M19).
##
## Station state is keyed by the station's *world position* (an integer cell), not
## by chunk or node identity.  That makes it independent of chunk load/unload
## order, of generation order and of the streaming architecture: a crafting table
## at (72, 66, -88) is the same station whether its chunk is loaded, unloaded or
## reloaded.
##
## Only stations the player has actually used (or that were restored from a save)
## hold state in memory, so a large world does not accumulate an inventory per
## station block that was ever generated.  Stale state -- a station whose block
## was replaced by something else -- is dropped when it is next touched and can be
## swept with `prune()`.

signal station_changed(position: Vector3i)

## How far from the player a furnace keeps processing.  A furnace outside this
## radius (or in an unloaded chunk) is simply paused, exactly like a Minecraft
## chunk that is not loaded: its progress is kept and resumes when the player
## returns.
const ACTIVE_RADIUS := 64.0

var world: VoxelWorld
## World position -> Station.
var _stations: Dictionary = {}


func _init(world_ref: VoxelWorld = null) -> void:
	world = world_ref


# --- lookup / lifecycle ---------------------------------------------------

## The station kind a block at this position provides, or "" (also when the cell
## is not loaded, so a station is only ever addressed in the live world).
func kind_at(position: Vector3i) -> String:
	if world == null or not world.is_loaded(position):
		return ""
	return Station.kind_for_block(world.get_block(position))


## The station at a world position, creating its (empty) state the first time it
## is asked for and the cell really holds a station.  Returns null when the cell
## is not a station, and drops any stale state it finds there.
func station_at(position: Vector3i) -> Station:
	var kind := kind_at(position)
	if kind.is_empty():
		if _stations.has(position):
			_stations.erase(position)
			station_changed.emit(position)
		return null
	var existing: Station = _stations.get(position)
	if existing != null:
		if existing.kind == kind:
			return existing
		# The block at this position became a different station kind.
		_stations.erase(position)
		station_changed.emit(position)
	var station := Station.new(kind)
	_stations[position] = station
	station_changed.emit(position)
	return station


## The station state already held for this position, or null.  Never creates one.
func peek(position: Vector3i) -> Station:
	return _stations.get(position)


func has(position: Vector3i) -> bool:
	return _stations.has(position)


func count() -> int:
	return _stations.size()


func positions() -> Array:
	var list: Array = _stations.keys()
	list.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a < b)
	return list


## Forgets the state at a position and returns the station that was there (null
## when there was none).  Used when the station block is destroyed.
func remove_station(position: Vector3i) -> Station:
	var station: Station = _stations.get(position)
	if station == null:
		return null
	_stations.erase(position)
	station_changed.emit(position)
	return station


## Removes the station at a position and returns everything it held as a list of
## stacks (`{item, count, durability}`).  The caller decides where they go.
func take_contents(position: Vector3i) -> Array:
	var station := remove_station(position)
	return [] if station == null else _drain(station)


## Drops state for every station whose block is no longer that station (mined,
## replaced, or a different station kind).  Returns the positions removed.
func prune() -> Array:
	var removed: Array = []
	for position: Vector3i in _stations.keys():
		var station: Station = _stations[position]
		# An unloaded chunk is not evidence that the station is gone; its state
		# must survive until the cell can be inspected again.
		if not world.is_loaded(position):
			continue
		if kind_at(position) != station.kind:
			_stations.erase(position)
			station_changed.emit(position)
			removed.append(position)
	return removed


# --- processing -----------------------------------------------------------

## Advances every active furnace near `focus` by `delta` seconds and returns how
## many stations changed.  Only loaded cells within `ACTIVE_RADIUS` are stepped,
## so the per-frame cost is bounded by the player's neighbourhood rather than the
## size of the world.
func tick(delta: float, focus: Vector3, radius: float = ACTIVE_RADIUS) -> int:
	var changed := 0
	if delta <= 0.0:
		return 0
	for position: Vector3i in _stations.keys():
		var station: Station = _stations[position]
		if not station.is_furnace():
			continue
		if not world.is_loaded(position):
			continue
		if Vector3(position.x + 0.5, position.y + 0.5, position.z + 0.5).distance_to(focus) > radius:
			continue
		if station.step(delta):
			station_changed.emit(position)
			changed += 1
	return changed


# --- persistence ----------------------------------------------------------

func to_dictionary() -> Array:
	var rows: Array = []
	for position: Vector3i in positions():
		var station: Station = _stations[position]
		rows.append([position.x, position.y, position.z, station.to_dictionary()])
	return rows


## Restores station state from a saved payload that `to_dictionary` produced.
## Every row is validated before it is accepted; an unreadable row is skipped
## (and counted in the return value as rejected) rather than aborting the load.
func from_dictionary(rows: Variant) -> Dictionary:
	_stations.clear()
	var accepted := 0
	var rejected := 0
	if typeof(rows) != TYPE_ARRAY:
		return {"accepted": 0, "rejected": 0}
	for entry: Variant in (rows as Array):
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 4:
			rejected += 1
			continue
		var row: Array = entry
		var payload: Variant = row[3]
		if typeof(payload) != TYPE_DICTIONARY:
			rejected += 1
			continue
		var kind := str((payload as Dictionary).get("kind", ""))
		if not Station.KIND_LAYOUTS.has(kind):
			rejected += 1
			continue
		var station := Station.new(kind)
		if not station.from_dictionary(payload as Dictionary):
			rejected += 1
			continue
		var position := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		_stations[position] = station
		accepted += 1
	return {"accepted": accepted, "rejected": rejected}


func _drain(station: Station) -> Array:
	var stacks: Array = []
	for index in station.inventory.size():
		var stack := station.inventory.take(index, -1)
		if not stack.is_empty():
			stacks.append(stack)
	return stacks
