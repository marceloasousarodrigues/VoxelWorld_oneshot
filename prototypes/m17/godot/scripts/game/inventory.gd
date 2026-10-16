class_name Inventory
extends RefCounted

## Player inventory: a fixed hotbar of block stacks plus a optional overflow
## buffer.
##
## The model is deliberately small and serialisable: every slot stores a block id
## and a count, `AIR` means empty, and nothing here knows about nodes or UI.

signal changed()

const HOTBAR_SIZE := 9

## Block ids in the hotbar; `BlockDB.AIR` marks an empty slot.
var slots: Array[int] = []
## Matching stack sizes.
var counts: Array[int] = []
var selected := 0


func _init() -> void:
	slots.resize(HOTBAR_SIZE)
	counts.resize(HOTBAR_SIZE)
	slots.fill(BlockDB.AIR)
	counts.fill(0)


## Gives the player a starter kit so a new world is immediately buildable.
func give_starter_kit() -> void:
	var kit: Array = [
		[BlockDB.GRASS, 64],
		[BlockDB.DIRT, 64],
		[BlockDB.STONE, 64],
		[BlockDB.PLANKS, 64],
		[BlockDB.SAND, 64],
		[BlockDB.GLASS, 32],
		[BlockDB.COBBLESTONE, 64],
		[BlockDB.OAK_LOG, 64],
		[BlockDB.CRAFTING_TABLE, 8],
	]
	for index in HOTBAR_SIZE:
		slots[index] = int(kit[index][0])
		counts[index] = int(kit[index][1])
	changed.emit()


## Adds a stack and returns the number of items that did not fit.
func add(block_id: int, amount: int = 1) -> int:
	if block_id == BlockDB.AIR or amount <= 0:
		return amount
	var remaining := amount
	for index in HOTBAR_SIZE:
		if remaining <= 0:
			break
		if slots[index] == block_id:
			counts[index] += remaining
			remaining = 0
	for index in HOTBAR_SIZE:
		if remaining <= 0:
			break
		if slots[index] == BlockDB.AIR:
			slots[index] = block_id
			counts[index] = remaining
			remaining = 0
	if amount != remaining:
		changed.emit()
	return remaining


## Removes one item from the given slot and returns the block id, or `AIR`.
func take_from_slot(index: int) -> int:
	if index < 0 or index >= HOTBAR_SIZE:
		return BlockDB.AIR
	if slots[index] == BlockDB.AIR or counts[index] <= 0:
		return BlockDB.AIR
	var block_id := slots[index]
	counts[index] -= 1
	if counts[index] <= 0:
		slots[index] = BlockDB.AIR
		counts[index] = 0
	changed.emit()
	return block_id


## Removes up to `amount` of a block, returning how many were actually removed.
func remove(block_id: int, amount: int = 1) -> int:
	var removed := 0
	for index in HOTBAR_SIZE:
		if removed >= amount:
			break
		while removed < amount and slots[index] == block_id and counts[index] > 0:
			counts[index] -= 1
			removed += 1
			if counts[index] <= 0:
				slots[index] = BlockDB.AIR
				counts[index] = 0
	if removed > 0:
		changed.emit()
	return removed


func count_of(block_id: int) -> int:
	var total := 0
	for index in HOTBAR_SIZE:
		if slots[index] == block_id:
			total += counts[index]
	return total


func is_empty(index: int) -> bool:
	return index < 0 or index >= HOTBAR_SIZE or slots[index] == BlockDB.AIR or counts[index] <= 0


func selected_block() -> int:
	if is_empty(selected):
		return BlockDB.AIR
	return slots[selected]


func select(index: int) -> bool:
	if index < 0 or index >= HOTBAR_SIZE or index == selected:
		return false
	selected = index
	changed.emit()
	return true


func used_slots() -> int:
	var used := 0
	for index in HOTBAR_SIZE:
		if not is_empty(index):
			used += 1
	return used


func to_dictionary() -> Dictionary:
	var entries: Array = []
	for index in HOTBAR_SIZE:
		entries.append([slots[index], counts[index]])
	return {"hotbar": entries, "selected": selected}


func from_dictionary(data: Dictionary) -> bool:
	var entries: Variant = data.get("hotbar")
	if typeof(entries) != TYPE_ARRAY:
		return false
	var array: Array = entries
	for index in mini(HOTBAR_SIZE, array.size()):
		var entry: Variant = array[index]
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 2:
			return false
		var block_id := int((entry as Array)[0])
		var count := int((entry as Array)[1])
		if block_id < 0 or block_id >= BlockDB.COUNT or count < 0:
			return false
		slots[index] = block_id
		counts[index] = count
	selected = clampi(int(data.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	changed.emit()
	return true
