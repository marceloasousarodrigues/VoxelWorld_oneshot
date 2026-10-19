class_name StationInventory
extends RefCounted

## A reusable, node-free inventory container for a placed world-object station
## (M19).  It is the same idea as the player's `Inventory` -- fixed slots, item
## id + count + durability, a stack cap, a `changed` signal -- but each slot has a
## *role* that decides what it will hold and one model serves every station kind.
##
## Roles are declared once when the container is configured, so a crafting table
## (nine grid slots + one result) and a furnace (input + fuel + output) share all
## of the movement, splitting, merging, stacking and validation code instead of
## hardcoding slot logic into each interface.
##
## Every mutating operation is atomic and count-preserving: operations that would
## duplicate or destroy an item are rejected and return the untouched stack, so a
## caller can always tell exactly what it is still holding.

signal changed()

const ROLE_GRID := "grid"
const ROLE_INPUT := "input"
const ROLE_FUEL := "fuel"
const ROLE_OUTPUT := "output"

## Item ids in each slot; `BlockDB.AIR` marks an empty slot.
var roles: Array[String] = []
var slots: Array[int] = []
var counts: Array[int] = []
## Remaining durability per slot (0 for blocks, materials and food).
var durability: Array[int] = []


func _init(slot_roles: Array[String] = []) -> void:
	configure(slot_roles)


## Replaces the slot layout, clearing every slot.
func configure(slot_roles: Array[String]) -> void:
	roles = slot_roles.duplicate()
	slots.resize(roles.size())
	counts.resize(roles.size())
	durability.resize(roles.size())
	slots.fill(BlockDB.AIR)
	counts.fill(0)
	durability.fill(0)


func size() -> int:
	return roles.size()


func role_of(index: int) -> String:
	if index < 0 or index >= size():
		return ""
	return roles[index]


func is_empty(index: int) -> bool:
	return index < 0 or index >= size() or slots[index] == BlockDB.AIR or counts[index] <= 0


func item_at(index: int) -> int:
	return BlockDB.AIR if is_empty(index) else slots[index]


func count_at(index: int) -> int:
	return 0 if is_empty(index) else counts[index]


func durability_of(index: int) -> int:
	if index < 0 or index >= size():
		return 0
	return durability[index]


func total_of(item_id: int) -> int:
	var total := 0
	for index in size():
		if slots[index] == item_id:
			total += counts[index]
	return total


func total_items() -> int:
	var total := 0
	for index in size():
		total += counts[index]
	return total


## True when the slot will accept this item through a player-facing move.  The
## output slot refuses everything (only the station itself writes there), the
## fuel slot only accepts a fuel, and the input slot only a smeltable item; a
## grid slot accepts any real item.
func accepts(index: int, item_id: int) -> bool:
	if index < 0 or index >= size():
		return false
	if item_id == BlockDB.AIR or not ItemDB.is_valid(item_id):
		return false
	match roles[index]:
		ROLE_OUTPUT:
			return false
		ROLE_FUEL:
			return Smelting.is_fuel(item_id)
		ROLE_INPUT:
			return Smelting.is_smeltable(item_id)
		_:
			return true


## Inserts a stack into one slot, respecting the role and the stack cap.  Returns
## whatever did not fit: an empty dictionary means the slot absorbed it all, and
## the caller keeps exactly the returned stack.  `slot` is never over-filled and
## no other slot is touched, so the operation is trivially count-preserving.
func insert(index: int, stack: Dictionary, allow_output: bool = false) -> Dictionary:
	if index < 0 or index >= size() or stack.is_empty():
		return stack
	var item_id := int(stack.get("item", BlockDB.AIR))
	var amount := int(stack.get("count", 0))
	if amount <= 0 or not ItemDB.is_valid(item_id):
		return stack
	if not allow_output and not accepts(index, item_id):
		return stack
	# A different item is never overwritten, even by the station itself: every
	# writer checks the slot fits first, and inserting must never silently
	# destroy what is already there.
	if not is_empty(index) and slots[index] != item_id:
		return stack
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var wear := clampi(int(stack.get("durability", ItemDB.max_durability(item_id))),
		0, maxi(0, ItemDB.max_durability(item_id)))
	var held := counts[index] if slots[index] == item_id else 0
	var placed := mini(maxi(0, capacity - held), amount)
	if placed <= 0:
		return stack
	slots[index] = item_id
	counts[index] = held + placed
	durability[index] = wear
	changed.emit()
	if placed >= amount:
		return {}
	return {"item": item_id, "count": amount - placed, "durability": wear}


## Takes items out of one slot.  `amount` < 0 takes the whole stack.  Returns the
## taken stack `{item, count, durability}` or `{}` when there was nothing to take.
func take(index: int, amount: int = -1) -> Dictionary:
	if is_empty(index):
		return {}
	var taken := counts[index] if amount < 0 else mini(counts[index], maxi(0, amount))
	if taken <= 0:
		return {}
	var stack := {"item": slots[index], "count": taken, "durability": durability[index]}
	counts[index] -= taken
	if counts[index] <= 0:
		_clear(index)
	changed.emit()
	return stack


## Removes up to `amount` of an item from anywhere in the container, returning how
## many were actually removed.  Used by the furnace to spend input and fuel.
func remove_item(item_id: int, amount: int = 1) -> int:
	var removed := 0
	for index in size():
		if removed >= amount:
			break
		while removed < amount and slots[index] == item_id and counts[index] > 0:
			counts[index] -= 1
			removed += 1
			if counts[index] <= 0:
				_clear(index)
	if removed > 0:
		changed.emit()
	return removed


## Adds a stack wherever it fits, filling matching stacks first and then empty
## accepting slots (never the output).  Returns how many items did not fit, so a
## quick-move can never duplicate or lose an item.  `insert` refuses a slot it
## cannot use, so the loop just moves on.
func deposit(stack: Dictionary) -> int:
	var carried := stack.duplicate()
	for index in size():
		if carried.is_empty() or int(carried.get("count", 0)) <= 0:
			break
		carried = insert(index, carried)
	return int(carried.get("count", 0))


## Empties one slot (item, count and durability).
func clear_slot(index: int) -> void:
	if is_empty(index):
		return
	_clear(index)
	changed.emit()


func clear_all() -> void:
	for index in size():
		_clear(index)
	changed.emit()


## Swaps two slots completely.  Refused when either target would not accept what
## it is about to hold, so a swap can never place a block into a fuel slot.
func swap(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= size() or b >= size():
		return false
	if not is_empty(a) and not accepts(b, slots[a]):
		return false
	if not is_empty(b) and not accepts(a, slots[b]):
		return false
	var item_a := slots[a]
	var count_a := counts[a]
	var wear_a := durability[a]
	slots[a] = slots[b]
	counts[a] = counts[b]
	durability[a] = durability[b]
	slots[b] = item_a
	counts[b] = count_a
	durability[b] = wear_a
	changed.emit()
	return true


## Moves what it can from one slot to another: a matching stack is topped up
## (respecting the cap) and the remainder stays behind, otherwise the two slots
## are swapped.  Returns true when the container changed.
func move(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= size() or to >= size():
		return false
	if is_empty(from):
		return false
	if not accepts(to, slots[from]):
		return false
	if not is_empty(to) and slots[to] == slots[from] and ItemDB.max_stack(slots[from]) > 1:
		var room := maxi(0, ItemDB.max_stack(slots[from]) - counts[to])
		var moved := mini(room, counts[from])
		if moved <= 0:
			return false
		counts[to] += moved
		counts[from] -= moved
		if counts[from] <= 0:
			_clear(from)
		changed.emit()
		return true
	return swap(from, to)


## Takes part of a stack out of one slot (the split half of a click-to-carry).
func split(index: int, amount: int) -> Dictionary:
	return take(index, amount)


func to_dictionary() -> Dictionary:
	var rows: Array = []
	for index in size():
		rows.append([roles[index], slots[index], counts[index], durability[index]])
	return {"slots": rows}


## Replaces the whole container from serialised data.  Atomic: the payload is
## validated into scratch arrays first, so a malformed save leaves the live
## container byte-identical instead of half-applied.
func from_dictionary(data: Dictionary) -> bool:
	var rows: Variant = data.get("slots")
	if typeof(rows) != TYPE_ARRAY:
		return false
	var array: Array = rows
	if array.size() != size():
		return false
	var new_slots: Array[int] = []
	var new_counts: Array[int] = []
	var new_wear: Array[int] = []
	for index in size():
		var row: Variant = array[index]
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 4:
			return false
		var values: Array = row
		if str(values[0]) != roles[index]:
			return false
		var item_id := int(values[1])
		var count := int(values[2])
		var wear := int(values[3])
		if not ItemDB.is_valid(item_id) or count < 0:
			return false
		if count > 0 and item_id == BlockDB.AIR:
			return false
		if count > maxi(1, ItemDB.max_stack(item_id)):
			return false
		if count > 0 and not accepts(index, item_id):
			# The output slot is the only restricted slot the station itself
			# writes to, so a saved output is legal even though a player move
			# into it is not.
			if roles[index] != ROLE_OUTPUT:
				return false
		if count <= 0:
			item_id = BlockDB.AIR
			wear = 0
		new_slots.append(item_id)
		new_counts.append(count)
		new_wear.append(wear)
	for index in size():
		slots[index] = new_slots[index]
		counts[index] = new_counts[index]
		durability[index] = new_wear[index]
	changed.emit()
	return true


func _clear(index: int) -> void:
	slots[index] = BlockDB.AIR
	counts[index] = 0
	durability[index] = 0
