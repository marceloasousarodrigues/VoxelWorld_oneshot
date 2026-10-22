extends RefCounted

const BuildDemo = preload("res://scripts/game/build_demo.gd")

## M25 player-authored construction demonstration: the scripted cottage and tower
## are ordinary voxel data with the expected materials, stair orientations and
## props, and every block can be mined again.

func name() -> String:
	return "player build demo"


func run(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var report := BuildDemo.build(world)
	h.check(int(report["cottage"]) > 150, "the demo cottage places a full building")
	h.check(int(report["tower"]) > 80, "the demo tower places a full tower")
	h.check(int(report["path"]) > 10, "the demo lays a path between the buildings")
	h.check(int(report["stairs"]) > 10, "the demo uses stair blocks for its steps and roof")

	var base: Vector3i = report["base_y"]
	var cottage := base + Vector3i(BuildDemo.COTTAGE_OFFSET.x, 0, BuildDemo.COTTAGE_OFFSET.y)
	var tower := base + Vector3i(BuildDemo.TOWER_OFFSET.x, 0, BuildDemo.TOWER_OFFSET.y)

	# Cottage: door, glass, stair roof, ridge and furnishing.
	h.eq(world.get_block(cottage + Vector3i(0, 1, 3)), BlockDB.DOOR, "the cottage has a door")
	h.eq(world.get_block(cottage + Vector3i(3, 2, 3)), BlockDB.WINDOW, "the cottage has a framed window")
	h.eq(world.get_block(cottage + Vector3i(0, 4, 3)), BlockDB.SLATE_RAMP, "the cottage roof starts with slate ramps")
	h.eq(world.get_orientation(cottage + Vector3i(0, 4, 3)), 0,
		"the south roof slope rises toward the ridge")
	h.eq(world.get_orientation(cottage + Vector3i(0, 4, -3)), 2,
		"the north roof slope is mirrored")
	h.eq(world.get_block(cottage + Vector3i(0, 7, 0)), BlockDB.SLATE_RIDGE,
		"the cottage roof is closed by a slate ridge")
	h.eq(world.get_block(cottage + Vector3i(-3, 1, -2)), BlockDB.CRAFTING_TABLE,
		"the cottage is furnished with a crafting table")
	h.eq(world.get_block(cottage + Vector3i(0, 3, 0)), BlockDB.LANTERN,
		"the cottage has a hanging lantern")

	# Tower: stone base, timber upper storey, battlements, door and lantern.
	h.eq(world.get_block(tower + Vector3i(0, 1, 2)), BlockDB.DOOR, "the tower has a door")
	h.eq(world.get_block(tower + Vector3i(-2, 1, 0)), BlockDB.STONE_BRICK, "the tower base is stone")
	h.eq(world.get_block(tower + Vector3i(-2, 4, 0)), BlockDB.TIMBER_FRAME,
		"the tower upper storey is timber-framed")
	h.eq(world.get_block(tower + Vector3i(0, 6, 0)), BlockDB.LANTERN, "the tower top has a lantern")

	# Ordinary world data: the demo blocks can be mined again and the stair keeps
	# its orientation state until mined.
	h.check(world.set_block(cottage + Vector3i(0, 1, 3), BlockDB.AIR), "a demo wall block can be mined")
	h.check(world.set_block_state(tower + Vector3i(0, 0, 3), BlockDB.AIR, 0), "a demo stair can be mined")
	h.eq(world.get_block(cottage + Vector3i(0, 1, 3)), BlockDB.AIR, "the mined demo block is gone")
	h.finish()
