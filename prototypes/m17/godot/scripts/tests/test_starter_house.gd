extends RefCounted

## A fresh world gets a complete, editable starter cottage near spawn.

const StarterHouse = preload("res://scripts/game/starter_house.gd")


func name() -> String:
	return "starter house"


func run(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var spawn := Vector2i(8, 8)
	var height := world.generator.height_at(spawn.x, spawn.y)
	# The game streams this area before play; load it for the node-free test.
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			world.ensure_chunk(VoxelWorld.world_to_chunk(Vector3i(spawn.x + dx, height, spawn.y + dz)))

	var report := StarterHouse.build(world, spawn)
	h.check(int(report["house"]) > 150, "the starter house places a complete cottage")
	h.check(int(report["blocks"]) > 100, "the starter site is levelled and built")
	h.check(int(report["path"]) > 5, "a path connects the door to the spawn")

	var anchor := Vector3i(spawn.x + StarterHouse.OFFSET.x, height, spawn.y + StarterHouse.OFFSET.y)
	h.eq(world.get_block(anchor + Vector3i(0, 1, 3)), BlockDB.DOOR, "the house has a door facing the spawn")
	h.eq(world.get_block(anchor + Vector3i(3, 2, 3)), BlockDB.WINDOW, "the house has a framed window")
	h.eq(world.get_block(anchor + Vector3i(0, 4, 3)), BlockDB.SLATE_RAMP, "the house has a slate roof")
	h.eq(world.get_orientation(anchor + Vector3i(0, 4, 3)), 0, "the roof slope rises toward the ridge")
	h.eq(world.get_block(anchor + Vector3i(0, 7, 0)), BlockDB.SLATE_RIDGE, "the roof is closed by a slate ridge")
	h.eq(world.get_block(anchor + Vector3i(-3, 1, -2)), BlockDB.CRAFTING_TABLE, "the house is furnished")
	h.eq(world.get_block(anchor + Vector3i(0, 3, 0)), BlockDB.LANTERN, "the house has a hanging lantern")

	# The path meets the player's feet level and the spawn cell stays clear.
	h.eq(world.get_block(Vector3i(anchor.x, height, spawn.y)), BlockDB.PATH,
		"the path reaches the spawn column")
	h.eq(world.get_block(Vector3i(spawn.x, height, spawn.y)), BlockDB.PATH,
		"the spawn column itself is paved")
	h.eq(world.get_block(Vector3i(spawn.x, height + 1, spawn.y)), BlockDB.AIR,
		"the spawn foot cell is clear")
	h.eq(world.get_block(Vector3i(spawn.x, height + 2, spawn.y)), BlockDB.AIR,
		"the spawn head cell is clear")

	# The house is ordinary recorded edits, so it saves and streams like player work.
	h.greater(float(world.edits.size()), 100.0, "the starter house is recorded as player edits")
	var before := world.edits.size()
	StarterHouse.build(world, spawn)
	h.eq(world.edits.size(), before, "rebuilding the starter house adds no duplicate edits")
	h.finish()
