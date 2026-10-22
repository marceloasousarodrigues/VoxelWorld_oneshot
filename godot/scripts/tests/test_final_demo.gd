extends RefCounted

## M28 final showcase: the village and castle are ordinary voxel data with the
## expected buildings, paths, props and stair roofs, and every piece can be mined.

const FinalDemo = preload("res://scripts/game/final_demo.gd")


func name() -> String:
	return "final village and castle demo"


func run(h: TestHarness) -> void:
	# The fixed showcase site must remain complete on the current generator: the
	# levelled base is capped below WORLD_HEIGHT by FinalDemo itself.
	var world := VoxelWorld.new(17017)
	var report := FinalDemo.build(world)
	h.check(int(report["cottage"]) > 150, "the final demo includes the cottage home")
	h.check(int(report["tower"]) > 80, "the final demo includes the stone/timber tower")
	h.check(int(report["longhouse"]) > 200, "the final demo includes a longhouse hall")
	h.check(int(report["market"]) > 60, "the final demo includes market stalls")
	h.check(int(report["castle"]) > 400, "the final demo includes a castle")
	h.check(int(report["path"]) > 60, "the final demo lays a street network")
	h.check(int(report["stairs"]) > 40, "the final demo builds stair roofs")
	h.check(int(report["lanterns"]) > 10, "the final demo lights the village")

	var base: Vector3i = report["base_y"]
	var cottage := base + Vector3i(FinalDemo.COTTAGE_OFFSET.x, 0, FinalDemo.COTTAGE_OFFSET.y)
	var longhouse := base + Vector3i(FinalDemo.LONGHOUSE_OFFSET.x, 0, FinalDemo.LONGHOUSE_OFFSET.y)
	var market := base + Vector3i(FinalDemo.MARKET_OFFSET.x, 0, FinalDemo.MARKET_OFFSET.y)
	var castle := base + Vector3i(FinalDemo.CASTLE_OFFSET.x, 0, FinalDemo.CASTLE_OFFSET.y)

	h.eq(world.get_block(cottage + Vector3i(0, 1, 3)), BlockDB.DOOR, "the home has a door")
	h.eq(world.get_block(longhouse + Vector3i(-1, 1, 4)), BlockDB.DOOR, "the longhouse has a double door")
	h.eq(world.get_block(longhouse + Vector3i(-5, 1, -2)), BlockDB.CRAFTING_TABLE, "the longhouse is furnished")
	h.eq(world.get_block(market + Vector3i(0, 5, 0)), BlockDB.SLATE_RIDGE, "the market stalls have slate roofs")
	h.eq(world.get_block(castle + Vector3i(-9, 6, -9)), BlockDB.STONE_BRICK, "the castle has a corner tower")
	h.eq(world.get_block(castle + Vector3i(0, 1, 8)), BlockDB.DOOR, "the castle has a gate door")
	h.eq(world.get_block(castle + Vector3i(0, 9, 0)), BlockDB.SLATE_RIDGE, "the keep is closed by a slate roof")
	h.eq(world.get_block(base + Vector3i(0, 0, 12)), BlockDB.PATH, "the village street is laid")
	h.eq(world.get_block(base + Vector3i(-16, 0, 18)), BlockDB.WATER, "the well holds water")
	h.eq(world.get_block(base + Vector3i(-24, 1, 17)), BlockDB.WHEAT_3, "the gardens hold ripe crops")
	# Ordinary world data: a castle wall and a roof ramp can be mined again.
	h.check(world.set_block(castle + Vector3i(8, 2, 0), BlockDB.AIR), "a castle wall block can be mined")
	h.check(world.set_block_state(castle + Vector3i(0, 5, 4), BlockDB.AIR, 0), "a keep roof ramp can be mined")
	h.eq(world.get_block(castle + Vector3i(8, 2, 0)), BlockDB.AIR, "the mined castle block is gone")
	h.finish()
