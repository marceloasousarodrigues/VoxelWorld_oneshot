class_name Inventory
extends RefCounted

## Player inventory: 27 main slots plus the nine-slot hotbar.
##
## The model is deliberately small and serialisable: every slot stores an item id,
## a count and (for tools) a remaining durability, `AIR` means empty, and nothing
## here knows about nodes or UI.
##
## Slot order is Minecraft-like: indices 0..8 are the hotbar (the row shown in the
## world) and indices 9..35 are the three main rows shown by the inventory
## interface.  `selected` always addresses a hotbar slot, so the item held in the
## world can never be a slot that is only visible inside a menu.
##
## `slots` holds `ItemDB` item ids.  Block ids are item ids, so a slot holding a
## block is still a block id; ids at or above `ItemDB.BLOCK_COUNT` are materials,
## food and tools.  Stacks respect `ItemDB.max_stack` (blocks and materials stack
## to 64, tools stack to 1), which is what makes the inventory genuinely fill up.

signal changed()

const HOTBAR_SIZE := 9
const MAIN_ROWS := 3
const MAIN_SIZE := HOTBAR_SIZE * MAIN_ROWS
const SIZE := HOTBAR_SIZE + MAIN_SIZE
const MAIN_FIRST := HOTBAR_SIZE


func size() -> int:
	return SIZE


## Item ids in the inventory; `BlockDB.AIR` marks an empty slot.
var slots: Array[int] = []
## Matching stack sizes.
var counts: Array[int] = []
## Remaining durability per slot.  0 means "not applicable" (blocks, materials)
## or "already consumed" for a tool that should have been cleared.
var durability: Array[int] = []
var selected := 0


func _init() -> void:
	slots.resize(SIZE)
	counts.resize(SIZE)
	durability.resize(SIZE)
	slots.fill(BlockDB.AIR)
	counts.fill(0)
	durability.fill(0)


## Gives the player a starter kit so a new world is immediately buildable.
##
## The kit fills the hotbar only; the 27 main slots stay empty, so the first
## mining drop always has somewhere to go.  (Before M20 the nine-slot inventory
## was full at spawn, which is why an iron/coal drop could be refused.)
func give_starter_kit() -> void:
	var kit: Array = [
		[BlockDB.GRASS, 16],
		[BlockDB.DIRT, 16],
		[BlockDB.STONE, 16],
		[BlockDB.PLANKS, 16],
		[BlockDB.SAND, 16],
		[BlockDB.GLASS, 8],
		[BlockDB.COBBLESTONE, 16],
		[BlockDB.OAK_LOG, 16],
		[BlockDB.CRAFTING_TABLE, 2],
	]
	for index in HOTBAR_SIZE:
		slots[index] = int(kit[index][0])
		counts[index] = int(kit[index][1])
		durability[index] = _initial_durability(int(kit[index][0]))
	changed.emit()


## Adds items and returns the number of items that did not fit.  Stack sizes are
## respected (`ItemDB.max_stack`), so a full inventory really does reject items
## instead of merging an unbounded pile into one slot.  A tool never merges: each
## one occupies its own slot at full durability unless `tool_durability` says
## otherwise.
func add(item_id: int, amount: int = 1, tool_durability: int = -1) -> int:
	if item_id == BlockDB.AIR or amount <= 0 or not ItemDB.is_valid(item_id):
		return amount
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var remaining := amount
	# 1) Top up existing stacks that still have room.
	for index in SIZE:
		if remaining <= 0:
			break
		if slots[index] != item_id:
			continue
		var room := capacity - counts[index]
		if room <= 0:
			continue
		var moved := mini(room, remaining)
		counts[index] += moved
		remaining -= moved
	# 2) Open new slots for whatever is left.
	for index in SIZE:
		if remaining <= 0:
			break
		if slots[index] != BlockDB.AIR:
			continue
		var moved := mini(capacity, remaining)
		slots[index] = item_id
		counts[index] = moved
		durability[index] = _initial_durability(item_id) if tool_durability < 0 else clampi(tool_durability, 0, maxi(0, ItemDB.max_durability(item_id)))
		remaining -= moved
	if amount != remaining:
		changed.emit()
	return remaining


## Adds a complete stack (item, count and durability) wherever it fits.  Returns
## the part that did not fit as a stack dictionary, so callers such as the
## interface's cursor recovery can never lose a per-tool durability value.
func add_stack(stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	var item_id := int(stack.get("item", BlockDB.AIR))
	var amount := int(stack.get("count", 0))
	if item_id == BlockDB.AIR or amount <= 0 or not ItemDB.is_valid(item_id):
		return stack.duplicate()
	var wear := clampi(int(stack.get("durability", _initial_durability(item_id))),
		0, maxi(0, ItemDB.max_durability(item_id)))
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var remaining := amount
	for index in SIZE:
		if remaining <= 0:
			break
		if slots[index] != item_id or counts[index] >= capacity:
			continue
		var moved := mini(capacity - counts[index], remaining)
		counts[index] += moved
		remaining -= moved
	for index in SIZE:
		if remaining <= 0:
			break
		if not is_empty(index):
			continue
		var moved := mini(capacity, remaining)
		slots[index] = item_id
		counts[index] = moved
		durability[index] = wear
		remaining -= moved
	if remaining != amount:
		changed.emit()
	if remaining <= 0:
		return {}
	return {"item": item_id, "count": remaining, "durability": wear}


## Removes one item from the given slot and returns the item id, or `AIR`.
func take_from_slot(index: int) -> int:
	if index < 0 or index >= SIZE:
		return BlockDB.AIR
	if slots[index] == BlockDB.AIR or counts[index] <= 0:
		return BlockDB.AIR
	var item_id := slots[index]
	counts[index] -= 1
	if counts[index] <= 0:
		_clear_slot(index)
	changed.emit()
	return item_id


## Removes up to `amount` of an item, returning how many were actually removed.
func remove(item_id: int, amount: int = 1) -> int:
	var removed := 0
	for index in SIZE:
		if removed >= amount:
			break
		while removed < amount and slots[index] == item_id and counts[index] > 0:
			counts[index] -= 1
			removed += 1
			if counts[index] <= 0:
				_clear_slot(index)
	if removed > 0:
		changed.emit()
	return removed


## Takes one item out of a specific slot (used by crafting, which needs the input
## to come from a known slot).  Returns how many were actually removed.
func remove_from_slot(index: int, amount: int = 1) -> int:
	if index < 0 or index >= SIZE or amount <= 0:
		return 0
	var removed := mini(counts[index], amount)
	if removed <= 0:
		return 0
	counts[index] -= removed
	if counts[index] <= 0:
		_clear_slot(index)
	changed.emit()
	return removed


func count_of(item_id: int) -> int:
	var total := 0
	for index in SIZE:
		if slots[index] == item_id:
			total += counts[index]
	return total


## Number of items of `item_id` that could still be added to the existing stacks
## before a new slot is needed.  Used for the crafting "does the output fit"
## check.
func stack_room(item_id: int) -> int:
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var room := 0
	for index in SIZE:
		if slots[index] == item_id:
			room += maxi(0, capacity - counts[index])
	return room


func free_slot_count() -> int:
	var free := 0
	for index in SIZE:
		if is_empty(index):
			free += 1
	return free


func used_slots() -> int:
	var used := 0
	for index in SIZE:
		if not is_empty(index):
			used += 1
	return used


func is_empty(index: int) -> bool:
	return index < 0 or index >= SIZE or slots[index] == BlockDB.AIR or counts[index] <= 0


## The item in a slot (`AIR` when it is empty or out of range).  Mirrors
## `StationInventory.item_at`, so interfaces can treat both models alike.
func item_at(index: int) -> int:
	if is_empty(index):
		return BlockDB.AIR
	return slots[index]


## The count in a slot (0 when it is empty or out of range).
func count_at(index: int) -> int:
	if index < 0 or index >= SIZE:
		return 0
	return counts[index]


## Empties one slot (its item, count and durability).
func clear_slot(index: int) -> void:
	if index < 0 or index >= SIZE:
		return
	if is_empty(index):
		return
	_clear_slot(index)
	changed.emit()


## The item id in the selected slot (or `AIR`).
func selected_item() -> int:
	if is_empty(selected):
		return BlockDB.AIR
	return slots[selected]


## The selected block id when the selected item is placeable, else `AIR`.
func selected_block() -> int:
	return ItemDB.placeable_block(selected_item())


## Remaining durability of a tool in a slot (0 for non-tools).
func durability_of(index: int) -> int:
	if index < 0 or index >= SIZE:
		return 0
	return durability[index]


func set_durability(index: int, value: int) -> void:
	if index < 0 or index >= SIZE:
		return
	durability[index] = maxi(0, value)


## Spends durability on the item in a slot.  Returns true when the tool broke and
## its slot was cleared.  Non-tools are unaffected and never break.
func wear(index: int, amount: int = 1) -> bool:
	if index < 0 or index >= SIZE or amount <= 0:
		return false
	if not ItemDB.is_tool_item(slots[index]):
		return false
	durability[index] = maxi(0, durability[index] - amount)
	if durability[index] > 0:
		changed.emit()
		return false
	_clear_slot(index)
	changed.emit()
	return true


## Selects a hotbar slot.  Only 0..8 are selectable; a menu-only main slot can
## never become the item held in the world.
func select(index: int) -> bool:
	if index < 0 or index >= HOTBAR_SIZE or index == selected:
		return false
	selected = index
	changed.emit()
	return true


## Swaps two slots completely (item, count and durability).  Used by the
## inventory interface's drag & drop.
func swap_slots(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= SIZE or b >= SIZE:
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
## (respecting the stack cap) and the remainder stays behind, otherwise the two
## slots are swapped.  Returns true when the inventory changed.
func move_slot(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= SIZE or to >= SIZE:
		return false
	if is_empty(from):
		return false
	if not is_empty(to) and slots[to] == slots[from] and ItemDB.max_stack(slots[from]) > 1:
		var room := maxi(0, ItemDB.max_stack(slots[from]) - counts[to])
		var moved := mini(room, counts[from])
		if moved <= 0:
			return false
		counts[to] += moved
		counts[from] -= moved
		if counts[from] <= 0:
			_clear_slot(from)
		changed.emit()
		return true
	return swap_slots(from, to)


## Shift-click: moves a whole stack between the hotbar and the main rows.
## Matching stacks are topped up first, then empty slots are used; a partial move
## leaves the remainder in the source slot.  Returns true when anything moved.
func quick_move(index: int) -> bool:
	if is_empty(index):
		return false
	var first := 0
	var last := SIZE
	if index < HOTBAR_SIZE:
		first = MAIN_FIRST
	else:
		last = HOTBAR_SIZE
	var item_id := slots[index]
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var remaining := counts[index]
	var wear := durability[index]
	# Top up matching stacks.
	for target in range(first, last):
		if remaining <= 0:
			break
		if slots[target] != item_id or counts[target] >= capacity:
			continue
		var moved := mini(capacity - counts[target], remaining)
		counts[target] += moved
		remaining -= moved
	# Then use empty slots.
	for target in range(first, last):
		if remaining <= 0:
			break
		if not is_empty(target):
			continue
		var moved := mini(capacity, remaining)
		slots[target] = item_id
		counts[target] = moved
		durability[target] = wear
		remaining -= moved
	if remaining == counts[index]:
		return false
	counts[index] = remaining
	if remaining <= 0:
		_clear_slot(index)
	changed.emit()
	return true


## Takes a whole stack out of a slot.  Returns
## `{ "item": id, "count": n, "durability": w }`, or an empty dictionary when the
## slot is empty or the index is out of range.
func take_stack(index: int) -> Dictionary:
	if is_empty(index):
		return {}
	var stack := {"item": slots[index], "count": counts[index], "durability": durability[index]}
	_clear_slot(index)
	changed.emit()
	return stack


## Puts a carried stack into a slot.  Returns whatever the caller must still hold:
## the part that did not fit, or the stack the slot displaced (a swap).  An empty
## dictionary means the slot absorbed everything.
##
##   - an empty slot takes up to the stack cap;
##   - a matching stack is topped up first;
##   - a slot holding something else is swapped, and that stack comes back.
func put_stack(index: int, stack: Dictionary) -> Dictionary:
	if index < 0 or index >= SIZE or stack.is_empty():
		return stack
	var item_id := int(stack.get("item", BlockDB.AIR))
	var amount := int(stack.get("count", 0))
	if item_id == BlockDB.AIR or amount <= 0 or not ItemDB.is_valid(item_id):
		return stack
	var capacity := maxi(1, ItemDB.max_stack(item_id))
	var wear := clampi(int(stack.get("durability", _initial_durability(item_id))),
		0, maxi(0, ItemDB.max_durability(item_id)))
	if is_empty(index):
		var placed := mini(capacity, amount)
		slots[index] = item_id
		counts[index] = placed
		durability[index] = wear
		changed.emit()
		return {} if placed >= amount else {"item": item_id, "count": amount - placed, "durability": wear}
	if slots[index] == item_id and capacity > 1:
		var room := maxi(0, capacity - counts[index])
		var placed := mini(room, amount)
		if placed <= 0:
			return stack
		counts[index] += placed
		changed.emit()
		return {} if placed >= amount else {"item": item_id, "count": amount - placed, "durability": wear}
	# A swap must be able to hold the whole carried stack; otherwise there is no
	# way to return both the displaced stack and the overflow, so refuse it.
	if amount > capacity:
		return stack
	var displaced := {"item": slots[index], "count": counts[index], "durability": durability[index]}
	slots[index] = item_id
	counts[index] = amount
	durability[index] = wear
	changed.emit()
	return displaced


func to_dictionary() -> Dictionary:
	var entries: Array = []
	var wear: Array = []
	for index in SIZE:
		entries.append([slots[index], counts[index]])
		wear.append(durability[index])
	return {"hotbar": entries, "selected": selected, "durability": wear, "size": SIZE}


## Replaces the whole inventory from serialised data.  Atomic: the payload is
## validated into scratch arrays first, so a malformed save leaves the live
## inventory byte-identical instead of half-applied.
##
## Saves written before M20 contain only nine rows; they load into the hotbar and
## the 27 main slots start empty.
func from_dictionary(data: Dictionary) -> bool:
	var entries: Variant = data.get("hotbar")
	if typeof(entries) != TYPE_ARRAY:
		return false
	var array: Array = entries
	if array.size() > SIZE:
		return false
	var new_slots: Array[int] = []
	var new_counts: Array[int] = []
	new_slots.resize(SIZE)
	new_counts.resize(SIZE)
	new_slots.fill(BlockDB.AIR)
	new_counts.fill(0)
	for index in array.size():
		var entry: Variant = array[index]
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 2:
			return false
		var item_id := int((entry as Array)[0])
		var count := int((entry as Array)[1])
		if not ItemDB.is_valid(item_id) or count < 0:
			return false
		if count > maxi(1, ItemDB.max_stack(item_id)):
			return false
		new_slots[index] = item_id
		new_counts[index] = count
	var new_wear: Array[int] = []
	new_wear.resize(SIZE)
	new_wear.fill(0)
	var wear: Variant = data.get("durability", [])
	if typeof(wear) != TYPE_ARRAY:
		return false
	for index in SIZE:
		var full := _initial_durability(new_slots[index])
		if full <= 0:
			continue
		if index >= (wear as Array).size():
			new_wear[index] = full
			continue
		# A tool with an out-of-range saved durability is repaired to a legal one
		# rather than being silently destroyed or made invincible.  A save written
		# before tools existed simply omits the field and starts the tool at full.
		new_wear[index] = clampi(int((wear as Array)[index]), 1, full)
	for index in SIZE:
		slots[index] = new_slots[index]
		counts[index] = new_counts[index]
		durability[index] = new_wear[index]
	selected = clampi(int(data.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	changed.emit()
	return true


func _initial_durability(item_id: int) -> int:
	return ItemDB.max_durability(item_id)


func _clear_slot(index: int) -> void:
	slots[index] = BlockDB.AIR
	counts[index] = 0
	durability[index] = 0
