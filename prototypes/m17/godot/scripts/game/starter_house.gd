class_name StarterHouse
extends RefCounted

## A complete starter cottage placed near the player's spawn on a fresh world.
##
## It reuses the same `BuildDemo` cottage definition the M25/M28 player demos
## use (stone foundation, timber frame, plank infill, glass windows, door, stair
## roof with ridge and chimney, table/furnace/chest/barrel, lanterns) and writes
## every cell through the normal `world.set_block` path, recorded as a player
## edit.  That means the house persists in the save and streams like any other
## player-built structure; it is not a pre-rendered or non-editable prefab.

const BuildDemo = preload("res://scripts/game/build_demo.gd")

## The house anchor is placed this far from the spawn column, in the direction
## the player initially looks (north-west), with the door facing the spawn.
const OFFSET := Vector2i(-6, -9)


static func build(world: VoxelWorld, spawn_column: Vector2i) -> Dictionary:
	var anchor := Vector3i(spawn_column.x + OFFSET.x, 0, spawn_column.y + OFFSET.y)
	# Level the footprint to the spawn's ground level so the path and door are
	# flush with where the player starts (hills are cut down, dips filled).
	var base_y := world.generator.height_at(spawn_column.x, spawn_column.y)
	anchor.y = base_y
	var report := {"base_y": base_y, "blocks": 0, "house": 0, "path": 0, "lanterns": 0}
	for dz in range(-5, 6):
		for dx in range(-6, 7):
			var x := anchor.x + dx
			var z := anchor.z + dz
			var y := base_y
			report["blocks"] += _change(world, Vector3i(x, y - 1, z), BlockDB.DIRT)
			report["blocks"] += _change(world, Vector3i(x, y, z), BlockDB.GRASS)
			for clear_y in range(y + 1, y + 12):
				report["blocks"] += _change(world, Vector3i(x, clear_y, z), BlockDB.AIR)
	report["house"] = BuildDemo._build_cottage(world, anchor)
	# The v4 canopy can grow a crown over the spawn path; clear a small start
	# clearing so the first view, head space and the path to the door are never
	# inside leaves or a trunk.  Clear only above each column's own surface so
	# the operation never cuts solid terrain or leaves underground cavities.
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var column_x := spawn_column.x + dx
			var column_z := spawn_column.y + dz
			var surface_y := world.generator.height_at(column_x, column_z)
			for clear_y in range(surface_y + 1, surface_y + 15):
				report["blocks"] += _change(world,
					Vector3i(column_x, clear_y, column_z), BlockDB.AIR)
	# A short packed path from the door south, then east to the spawn point.
	for z in range(anchor.z + 4, spawn_column.y + 1):
		report["blocks"] += _change(world, Vector3i(anchor.x, base_y, z), BlockDB.PATH)
		report["path"] += 1
	for x in range(anchor.x, spawn_column.x + 1):
		report["blocks"] += _change(world, Vector3i(x, base_y, spawn_column.y), BlockDB.PATH)
		report["path"] += 1
	print("M29_STARTER_HOUSE built anchor=%s spawn=%s house=%d path=%d blocks=%d" % [
		anchor, spawn_column, int(report["house"]), int(report["path"]), int(report["blocks"])])
	return report


## Writes one cell only when it changes, records it as a player edit, and loads
## the chunk if the streaming/startup path has not reached it yet.
static func _change(world: VoxelWorld, position: Vector3i, block_id: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id:
		return 0
	return 1 if world.set_block(position, block_id, true) else 0
