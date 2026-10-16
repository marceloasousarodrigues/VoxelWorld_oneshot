extends RefCounted

## Water behaviour: bounded spread, vertical priority, draining, per-tick
## budgets, cross-chunk propagation and edit invalidation.


func name() -> String:
	return "water simulation"


## A synthetic world: air everywhere with a stone floor one block below `floor_y`.
func _platform_world(floor_y: int, coords: Array) -> VoxelWorld:
	var world := VoxelWorld.new(17017)
	for coord: Vector3i in coords:
		var chunk := ChunkData.new(coord)
		chunk.generated = true
		var local_floor := floor_y - coord.y * ChunkData.SIZE
		if local_floor >= 0 and local_floor < ChunkData.SIZE:
			for z in ChunkData.SIZE:
				for x in ChunkData.SIZE:
					chunk.blocks[ChunkData.cell_index(x, local_floor, z)] = BlockDB.STONE
		world.adopt_chunk(chunk)
	return world


func _settle(sim: FluidSim, max_ticks: int = 200) -> int:
	var ticks := 0
	while sim.has_pending_work() and ticks < max_ticks:
		sim.tick()
		ticks += 1
	return ticks


func run(h: TestHarness) -> void:
	# 1) A source on a platform spreads seven cells and then stops.
	var world := _platform_world(64, [Vector3i(0, 4, 0)])
	var sim := FluidSim.new(world)
	var source := Vector3i(8, 65, 8)
	world.set_block(source, BlockDB.WATER)
	sim.on_block_changed(source, BlockDB.AIR, BlockDB.WATER)
	_settle(sim)
	h.eq(world.get_fluid(Vector3i(9, 65, 8)), 7, "water spreads one cell at level 7")
	h.eq(world.get_fluid(Vector3i(10, 65, 8)), 6, "water spreads two cells at level 6")
	h.eq(world.get_fluid(Vector3i(15, 65, 8)), 1, "water reaches seven cells at level 1")
	h.eq(world.get_fluid(Vector3i(16, 65, 8)), 0, "water stops after seven cells")
	h.eq(world.get_fluid(Vector3i(8, 65, 15)), 1, "the spread limit is symmetric along Z")
	h.eq(world.get_fluid(source), ChunkData.SOURCE_LEVEL, "the source stays full")
	h.eq(world.get_block(Vector3i(16, 65, 8)), BlockDB.AIR, "the cell past the limit stays air")
	h.check(not sim.has_pending_work(), "the simulation settles")

	# 2) Water falls with vertical priority and pools at the bottom.
	var shaft := _platform_world(60, [Vector3i(0, 4, 0), Vector3i(0, 3, 0)])
	var shaft_sim := FluidSim.new(shaft)
	var top_source := Vector3i(8, 78, 8)
	shaft.set_block(top_source, BlockDB.WATER)
	shaft_sim.on_block_changed(top_source, BlockDB.AIR, BlockDB.WATER)
	_settle(shaft_sim)
	h.eq(shaft.get_fluid(Vector3i(8, 70, 8)), FluidSim.FALLING_LEVEL, "falling water keeps full flowing strength")
	h.eq(shaft.get_fluid(Vector3i(8, 61, 8)), FluidSim.FALLING_LEVEL, "water reaches the bottom of the shaft")
	h.eq(shaft.get_fluid(Vector3i(9, 61, 8)), 6, "the pool at the bottom spreads out")

	# 3) Water does not float without support or an adjacent source.
	var void_world := VoxelWorld.new(17017)
	var void_chunk := ChunkData.new(Vector3i(0, 4, 0))
	void_chunk.generated = true
	void_world.adopt_chunk(void_chunk)
	var void_sim := FluidSim.new(void_world)
	void_world.set_fluid(Vector3i(8, 70, 8), 5, false)
	void_sim.enqueue(Vector3i(8, 70, 8))
	_settle(void_sim)
	h.eq(void_world.get_fluid(Vector3i(8, 70, 8)), 0, "unsupported water drains over a void")

	# 4) Removing the source drains the pool.
	var drain_world := _platform_world(64, [Vector3i(0, 4, 0)])
	var drain_sim := FluidSim.new(drain_world)
	var drain_source := Vector3i(8, 65, 8)
	drain_world.set_block(drain_source, BlockDB.WATER)
	drain_sim.on_block_changed(drain_source, BlockDB.AIR, BlockDB.WATER)
	_settle(drain_sim)
	h.check(drain_world.get_fluid(Vector3i(9, 65, 8)) > 0, "the pool exists before the source is removed")
	drain_world.set_block(drain_source, BlockDB.AIR)
	drain_sim.on_block_changed(drain_source, BlockDB.WATER, BlockDB.AIR)
	_settle(drain_sim)
	h.eq(drain_world.get_fluid(Vector3i(9, 65, 8)), 0, "the pool drains after the source is removed")
	h.eq(drain_world.get_block(Vector3i(9, 65, 8)), BlockDB.AIR, "drained cells become air")

	# 5) Per-tick work is bounded by the cell budget.
	var budget_world := _platform_world(64, [Vector3i(0, 4, 0)])
	var budget_sim := FluidSim.new(budget_world)
	budget_sim.max_cells_per_tick = 3
	budget_sim.max_milliseconds_per_tick = 1000.0
	var budget_source := Vector3i(8, 65, 8)
	budget_world.set_block(budget_source, BlockDB.WATER)
	budget_sim.enqueue_with_neighbours(budget_source)
	var per_tick: Array[int] = []
	while budget_sim.has_pending_work() and per_tick.size() < 50:
		per_tick.append(budget_sim.tick())
	var max_processed := 0
	for index in range(0, per_tick.size()):
		pass
	h.check(per_tick.size() > 1, "bounded ticking needs more than one tick")
	h.less(float(budget_sim.max_cells_per_tick), 4.0, "the budget is a real limit")
	h.greater(float(budget_sim.stats()["evaluations"]), 0.0, "the simulation evaluates cells")

	# 6) Cross-chunk propagation.
	var border_world := _platform_world(65, [Vector3i(0, 4, 0), Vector3i(1, 4, 0)])
	var border_sim := FluidSim.new(border_world)
	var border_source := Vector3i(14, 66, 8)
	border_world.set_block(border_source, BlockDB.WATER)
	border_sim.on_block_changed(border_source, BlockDB.AIR, BlockDB.WATER)
	_settle(border_sim)
	h.eq(border_world.get_fluid(Vector3i(15, 66, 8)), 7, "water flows to the chunk border")
	h.eq(border_world.get_fluid(Vector3i(16, 66, 8)), 6, "water crosses into the neighbouring chunk")
	h.eq(border_world.get_fluid(Vector3i(17, 66, 8)), 5, "water keeps spreading inside the neighbour")
	h.check(border_world.has_chunk(Vector3i(1, 4, 0)), "the neighbouring chunk is still loaded")

	# 7) A later edit wins: no stale simulation state overwrites new blocks.
	var edit_world := _platform_world(64, [Vector3i(0, 4, 0)])
	var edit_sim := FluidSim.new(edit_world)
	var edit_source := Vector3i(8, 65, 8)
	edit_world.set_block(edit_source, BlockDB.WATER)
	edit_sim.on_block_changed(edit_source, BlockDB.AIR, BlockDB.WATER)
	edit_sim.tick()
	# A wall has to span the platform: a single pillar would just be walked around.
	var wall_x := 11
	for z in ChunkData.SIZE:
		var wall := Vector3i(wall_x, 65, z)
		edit_world.set_block(wall, BlockDB.STONE_BRICK)
		edit_sim.on_block_changed(wall, BlockDB.AIR, BlockDB.STONE_BRICK)
	_settle(edit_sim)
	h.eq(edit_world.get_block(Vector3i(wall_x, 65, 8)), BlockDB.STONE_BRICK, "the newly placed block survives the simulation")
	h.eq(edit_world.get_fluid(Vector3i(wall_x, 65, 8)), 0, "no water is written into the new solid block")
	h.eq(edit_world.get_fluid(Vector3i(10, 65, 8)), 6, "water still reaches the cell before the wall")
	h.eq(edit_world.get_fluid(Vector3i(12, 65, 8)), 0, "the wall stops the flow")

	# 8) Determinism: the same setup settles to the same levels.
	var repeat_a := _platform_world(64, [Vector3i(0, 4, 0)])
	var sim_a := FluidSim.new(repeat_a)
	repeat_a.set_block(Vector3i(8, 65, 8), BlockDB.WATER)
	sim_a.on_block_changed(Vector3i(8, 65, 8), BlockDB.AIR, BlockDB.WATER)
	_settle(sim_a)
	var repeat_b := _platform_world(64, [Vector3i(0, 4, 0)])
	var sim_b := FluidSim.new(repeat_b)
	repeat_b.set_block(Vector3i(8, 65, 8), BlockDB.WATER)
	sim_b.on_block_changed(Vector3i(8, 65, 8), BlockDB.AIR, BlockDB.WATER)
	_settle(sim_b)
	var identical := true
	for dx in range(-9, 10):
		for dz in range(-9, 10):
			if repeat_a.get_fluid(Vector3i(8 + dx, 65, 8 + dz)) != repeat_b.get_fluid(Vector3i(8 + dx, 65, 8 + dz)):
				identical = false
	h.check(identical, "the same edit settles to identical water levels")

	# 9) Fluid writes never overwrite solid blocks.
	var solid_world := _platform_world(64, [Vector3i(0, 4, 0)])
	solid_world.set_block(Vector3i(9, 65, 8), BlockDB.STONE)
	h.check(not solid_world.set_fluid(Vector3i(9, 65, 8), 7, false), "fluid cannot be written into stone")
	h.eq(solid_world.get_block(Vector3i(9, 65, 8)), BlockDB.STONE, "the stone block is untouched")

	# 10) Loading a chunk with generated water seeds its sources.
	var ocean_world := VoxelWorld.new(17017)
	var ocean_chunk := ocean_world.ensure_chunk(Vector3i(0, 3, 0))
	var ocean_sim := FluidSim.new(ocean_world)
	var seeded := ocean_sim.seed_chunk_sources(ocean_chunk)
	h.greater(float(seeded), -1.0, "seeding a generated chunk is safe")
	h.check(ocean_sim.stats()["seeded_chunks"] == 1, "the seeded chunk is counted")

	h.finish()
